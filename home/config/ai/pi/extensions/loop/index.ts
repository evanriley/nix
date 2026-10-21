import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentToolResult } from "@earendil-works/pi-agent-core";
import type { Message, Usage } from "@earendil-works/pi-ai";
import {
	type ExtensionAPI,
	type ExtensionCommandContext,
	type ExtensionContext,
	getAgentDir,
	getMarkdownTheme,
	keyHint,
	type Theme,
} from "@earendil-works/pi-coding-agent";
import {
	type Component,
	Container,
	Markdown,
	sliceByColumn,
	Spacer,
	Text,
	TruncatedText,
	truncateToWidth,
	visibleWidth,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
	type CheckRun,
	type ContextCapState,
	chooseWorkerSession,
	commitMessage,
	commitTask,
	contextCapStep,
	featureCost,
	findTask,
	nextNumber,
	parseChecks,
	parseContextCap,
	parseVerdict,
	readTaskRecord,
	reviewNumbers,
	runChecks,
	type SpecTask,
	type TaskRecord,
	tailLines,
	taskRecordPath,
	trackedChanges,
	untrackedPaths,
	type Verdict,
	type WorkerSession,
	withoutPaths,
	writeTaskRecord,
} from "./pipeline.ts";

const EXTENSION_DIR = path.dirname(fileURLToPath(import.meta.url));
const PLANS_DIR = path.join(os.homedir(), ".pi", "plans");
const FEATURE_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
const PROGRESS_INTERVAL_MS = 250;
const COLLAPSED_REPORT_LINES = 10;
const TRANSCRIPT_BLOCK_LINES = 20;
const APPROVAL_ENTRY = "loop-approval";
const STATUS_KEY = "loop";
const FEATURE_MAX_COST = 15;
const CHECK_TIMEOUT_MINUTES = 30;
const MAX_CHECK_RETRIES = 2;
const MAX_FIX_PASSES = 2;
const REASON_LINES = 40;
const PLANNER_CONTEXT_CAP = 160_000;
const PLANNER_CONTEXT_HARD_MARGIN = 30_000;
const plannerContextCap = parseContextCap(process.env.PI_LOOP_CONTEXT_CAP, PLANNER_CONTEXT_CAP);
const REVIEW_SCOPE =
	"Review the uncommitted changes in this repository against the spec: run `git status`, `git diff` and `git diff --cached`, and read every file listed by `git ls-files --others --exclude-standard`.";

type Role = "worker" | "reviewer";
type Stage = "worker" | "checks" | "review" | "commit";
type BlockedStage = "budget" | "checks" | "review" | "commit" | "worker" | "aborted";

interface ChildConfig {
	role: Role;
	scratch?: string;
	model: string;
	thinking: string;
	tools: string[];
	promptFile: string;
	sessionFile: string;
	maxTurns: number;
	maxMinutes: number;
	maxCost: number;
	maxResumeTokens?: number;
}

const ROLE_CONFIG: Record<Role, Omit<ChildConfig, "sessionFile">> = {
	worker: {
		role: "worker",
		model: "coralbricks/deepseek-v4.1-flash-fast",
		thinking: "high",
		tools: ["read", "bash", "edit", "write", "mcp__grep_app__searchGitHub", "mcp__kagi__kagi_search_fetch"],
		promptFile: path.join(EXTENSION_DIR, "worker.md"),
		maxTurns: 500,
		maxMinutes: 120,
		maxCost: 3,
		maxResumeTokens: 200_000,
	},
	reviewer: {
		role: "reviewer",
		model: "openrouter/minimax/minimax-m3.1-flash:free",
		thinking: "high",
		tools: ["read", "grep", "find", "ls", "bash", "mcp__kagi__kagi_search_fetch"],
		promptFile: path.join(EXTENSION_DIR, "reviewer.md"),
		maxTurns: 200,
		maxMinutes: 60,
		maxCost: 3,
	},
};

interface LimitHit {
	kind: "turn" | "time" | "cost";
	value: string;
}

interface ChildResult {
	exitCode: number;
	finalText: string;
	stderr: string;
	stopReason?: string;
	errorMessage?: string;
	turns: number;
	toolCalls: number;
	usage: Usage;
	thinkingLine?: string;
	limit?: LimitHit;
}

interface TranscriptRef {
	file: string;
	fromLine: number;
}

interface LoopDetails {
	stage: Stage;
	feature: string;
	turns: number;
	toolCalls: number;
	usage: Usage;
	transcript?: TranscriptRef;
	reviewPath?: string;
	thinkingLine?: string;
	command?: string;
}

interface TranscriptCache {
	key: string;
	messages: Message[] | undefined;
}

let taskRunning = false;
let runningStage: Stage | undefined;
let lastTouchedFeature: string | undefined;
const approvals = new Map<string, string>();
const contextCapState: ContextCapState = { warned: false, aborted: false };

interface ApprovalEntryData {
	feature: string;
	specHash: string | null;
}

function emptyUsage(): Usage {
	return {
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		totalTokens: 0,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
	};
}

function addUsage(total: Usage, usage: Usage): void {
	total.input += usage.input || 0;
	total.output += usage.output || 0;
	total.cacheRead += usage.cacheRead || 0;
	total.cacheWrite += usage.cacheWrite || 0;
	total.totalTokens += usage.totalTokens || 0;
	total.cost.input += usage.cost?.input || 0;
	total.cost.output += usage.cost?.output || 0;
	total.cost.cacheRead += usage.cost?.cacheRead || 0;
	total.cost.cacheWrite += usage.cost?.cacheWrite || 0;
	total.cost.total += usage.cost?.total || 0;
}

function sessionSlug(directory: string): string {
	return `--${path
		.resolve(directory)
		.replace(/^[/\\]/, "")
		.replace(/[/\\:]/g, "-")}--`;
}

async function gitTopLevel(pi: ExtensionAPI, cwd: string): Promise<string | undefined> {
	const gitRoot = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd }).catch(() => undefined);
	return gitRoot?.code === 0 && gitRoot.stdout.trim() ? gitRoot.stdout.trim() : undefined;
}

async function projectPlansDir(pi: ExtensionAPI, cwd: string): Promise<string> {
	return path.join(PLANS_DIR, sessionSlug((await gitTopLevel(pi, cwd)) ?? cwd));
}

async function resolveFeatureDir(pi: ExtensionAPI, cwd: string, feature: string): Promise<string> {
	if (!FEATURE_PATTERN.test(feature)) {
		throw new Error(
			`Invalid feature "${feature}"; expected a kebab-case slug matching ${FEATURE_PATTERN.source}, such as "add-login-form".`,
		);
	}
	return path.join(await projectPlansDir(pi, cwd), feature);
}

function hashFile(filePath: string): string {
	return createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function recordApproval(pi: ExtensionAPI, feature: string, specHash: string | null): void {
	if (specHash) approvals.set(feature, specHash);
	else approvals.delete(feature);
	pi.appendEntry(APPROVAL_ENTRY, { feature, specHash });
}

function checkApproval(feature: string, specPath: string): void {
	const approvedHash = approvals.get(feature);
	if (!approvedHash) {
		throw new Error("Not approved: ask the user to run /approve.");
	}
	if (approvedHash !== hashFile(specPath)) {
		throw new Error("spec.md changed after approval: ask the user to run /approve again.");
	}
}

function touchFeature(pi: ExtensionAPI, feature: string): void {
	lastTouchedFeature = feature;
	if (!pi.getSessionName()) pi.setSessionName(feature);
}

function isApprovalEntryData(data: unknown): data is ApprovalEntryData {
	if (typeof data !== "object" || data === null) return false;
	const { feature, specHash } = data as Partial<ApprovalEntryData>;
	return (
		typeof feature === "string" && FEATURE_PATTERN.test(feature) && (typeof specHash === "string" || specHash === null)
	);
}

function restoreFromBranch(pi: ExtensionAPI, ctx: ExtensionContext): void {
	approvals.clear();
	lastTouchedFeature = undefined;
	let latestFeature: string | undefined;
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "custom" || entry.customType !== APPROVAL_ENTRY || !isApprovalEntryData(entry.data)) continue;
		if (entry.data.specHash) approvals.set(entry.data.feature, entry.data.specHash);
		else approvals.delete(entry.data.feature);
		latestFeature = entry.data.feature;
	}
	if (latestFeature) touchFeature(pi, latestFeature);
}

function latestVerdict(featureDir: string): string | undefined {
	const latestReview = reviewNumbers(featureDir, /^review-(\d+)\.md$/).at(-1);
	if (latestReview === undefined) return undefined;
	const verdictLine = fs
		.readFileSync(path.join(featureDir, `review-${latestReview}.md`), "utf-8")
		.split("\n")
		.filter((line) => line.startsWith("Verdict:"))
		.at(-1);
	return verdictLine?.slice("Verdict:".length).trim() || undefined;
}

function loopState(feature: string, featureDir: string): string {
	if (runningStage) return `${runningStage} running`;
	if (approvals.has(feature)) return "approved";
	const verdict = latestVerdict(featureDir);
	return verdict ? `review: ${verdict}` : "spec";
}

async function refreshStatus(pi: ExtensionAPI, ctx: ExtensionContext): Promise<void> {
	const feature = lastTouchedFeature;
	if (!feature) {
		ctx.ui.setStatus(STATUS_KEY, undefined);
		return;
	}
	const featureDir = path.join(await projectPlansDir(pi, ctx.cwd), feature);
	const theme = ctx.ui.theme;
	ctx.ui.setStatus(STATUS_KEY, theme.fg("accent", feature) + theme.fg("dim", ` · ${loopState(feature, featureDir)}`));
}

function expandHome(filePath: string): string {
	return filePath === "~" || filePath.startsWith("~/") ? path.join(os.homedir(), filePath.slice(1)) : filePath;
}

async function featureOfSpecPath(pi: ExtensionAPI, cwd: string, filePath: string): Promise<string | undefined> {
	const absolutePath = path.resolve(cwd, expandHome(filePath));
	if (path.basename(absolutePath) !== "spec.md") return undefined;
	const featureDir = path.dirname(absolutePath);
	const feature = path.basename(featureDir);
	if (!FEATURE_PATTERN.test(feature)) return undefined;
	return path.dirname(featureDir) === (await projectPlansDir(pi, cwd)) ? feature : undefined;
}

function newestSpecFeature(plansDir: string): string | undefined {
	if (!fs.existsSync(plansDir)) return undefined;
	let newest: { feature: string; modifiedMs: number } | undefined;
	for (const feature of fs.readdirSync(plansDir)) {
		if (!FEATURE_PATTERN.test(feature)) continue;
		const specPath = path.join(plansDir, feature, "spec.md");
		if (!fs.existsSync(specPath)) continue;
		const modifiedMs = fs.statSync(specPath).mtimeMs;
		if (!newest || modifiedMs > newest.modifiedMs) newest = { feature, modifiedMs };
	}
	return newest?.feature;
}

async function featureToApprove(pi: ExtensionAPI, cwd: string): Promise<string | undefined> {
	const plansDir = await projectPlansDir(pi, cwd);
	if (lastTouchedFeature && fs.existsSync(path.join(plansDir, lastTouchedFeature, "spec.md"))) {
		return lastTouchedFeature;
	}
	return newestSpecFeature(plansDir);
}

function requireSpec(featureDir: string): string {
	const specPath = path.join(featureDir, "spec.md");
	if (!fs.existsSync(specPath)) {
		throw new Error(`Spec not found at ${specPath}; write the approved spec there before dispatching.`);
	}
	return specPath;
}

function nextReviewNumber(featureDir: string): number {
	const numbers = reviewNumbers(featureDir, /^(?:review-(\d+)\.(?:md|jsonl)|scratch-(\d+))$/);
	return numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
}

function freshWorkerSession(run: TaskRun): WorkerSession {
	return chooseWorkerSession(run.featureDir, false, ROLE_CONFIG.worker.maxResumeTokens ?? 0);
}

function checkFailureText(failure: Extract<CheckRun, { ok: false }>, logPath: string): string {
	const outcome = failure.timedOut
		? `timed out after ${CHECK_TIMEOUT_MINUTES} min`
		: `exit ${failure.exitCode ?? "signal"}`;
	return `\`${failure.command}\` failed (${outcome}); log: ${logPath}\n\n${failure.tail}`;
}

function checkFailureMessage(
	run: TaskRun,
	session: WorkerSession,
	failure: Extract<CheckRun, { ok: false }>,
	logPath: string,
) {
	const outcome = failure.timedOut
		? `timed out after ${CHECK_TIMEOUT_MINUTES} min`
		: `exited with ${failure.exitCode ?? "a signal"}`;
	const lines = [
		"The spec's Checks failed after your report.",
		`Command: ${failure.command}`,
		`Result: ${outcome}`,
		`Log: ${logPath}`,
		"Last lines of its output:",
		`~~~~\n${failure.tail}\n~~~~`,
		"Fix the cause, run the Checks yourself, and report again.",
	];
	const intro = session.resumed ? "" : `${taskHeader(run)}\n\n${run.brief}\n\n`;
	return `${intro}${lines.join("\n")}`;
}

async function passChecks(run: TaskRun, report: string): Promise<string> {
	for (let retries = 0; ; retries++) {
		checkAborted(run);
		await enterStage(run, "checks");
		const logPath = path.join(run.featureDir, `checks-${nextNumber(run.featureDir, /^checks-(\d+)\.log$/)}.log`);
		run.record.checks.push(logPath);
		const result = await runChecks(
			run.repoRoot,
			run.checks,
			CHECK_TIMEOUT_MINUTES * 60_000,
			logPath,
			run.signal,
			(command) =>
				run.onUpdate?.({
					content: [{ type: "text", text: `checks running: ${command}` }],
					details: { stage: "checks", feature: run.feature, turns: 0, toolCalls: 0, usage: emptyUsage(), command },
				}),
		);
		checkAborted(run);
		if (result.ok) return report;
		if (retries >= MAX_CHECK_RETRIES) blocked("checks", checkFailureText(result, logPath));
		const session = chooseWorkerSession(run.featureDir, true, ROLE_CONFIG.worker.maxResumeTokens ?? 0);
		report = await runWorker(run, session, checkFailureMessage(run, session, result, logPath));
	}
}

async function reviewTask(
	run: TaskRun,
): Promise<{ verdict: Exclude<Verdict, { kind: "missing" }>; reviewPath: string }> {
	checkAborted(run);
	checkBudget(run);
	await enterStage(run, "review");
	const reviewNumber = nextReviewNumber(run.featureDir);
	const previousReviews = [...run.earlierReviews, ...run.record.reviews];
	const scratchDir = path.join(run.featureDir, `scratch-${reviewNumber}`);
	let scratch: string | undefined;
	try {
		await createScratch(run.repoRoot, scratchDir);
		scratch = scratchDir;
	} catch (error) {
		await removeScratch(run.repoRoot, scratchDir);
		const reason = error instanceof Error ? error.message : String(error);
		run.ctx.ui.notify(`Reviewer scratch copy failed; reviewing without it: ${reason}`, "warning");
	}
	const transcript = { file: path.join(run.featureDir, `review-${reviewNumber}.jsonl`), fromLine: 0 };
	let result: ChildResult;
	try {
		const message = [
			`Spec: ${run.specPath}`,
			scratch ? `Scratch: ${scratch}` : undefined,
			`Task ${run.task.number}: ${run.task.subject}`,
			run.brief,
			previousReviews.length > 0 ? `Previous reviews:\n${previousReviews.join("\n")}` : undefined,
			REVIEW_SCOPE,
			run.preexisting.length > 0
				? `These untracked files existed before this task and are not part of it; ignore them:\n${run.preexisting.join("\n")}`
				: undefined,
		]
			.filter((line) => line !== undefined)
			.join("\n\n");
		result = await runChild(
			{ ...ROLE_CONFIG.reviewer, sessionFile: transcript.file, scratch },
			message,
			run.ctx.cwd,
			run.signal,
			progressReporter("review", run.feature, transcript, run.onUpdate),
		);
	} finally {
		await removeScratch(run.repoRoot, scratchDir);
	}
	addChildResult(run, result);
	checkAborted(run);
	if (isFailed(result)) blocked("review", failureText("reviewer", result));
	if (!result.finalText.trim()) blocked("review", "The reviewer returned no verdict.");
	const reviewPath = path.join(run.featureDir, `review-${reviewNumber}.md`);
	fs.writeFileSync(reviewPath, `${result.finalText.trim()}\n`, { encoding: "utf-8", flag: "wx" });
	run.record.reviews.push(reviewPath);
	const verdict = parseVerdict(result.finalText);
	if (verdict.kind === "missing") blocked("review", `The reviewer returned no verdict; see ${reviewPath}.`);
	return { verdict, reviewPath };
}

function fixMessage(run: TaskRun, reviewPath: string, blocking: string[]): string {
	const findings =
		blocking.length > 0
			? blocking.map((finding) => `- ${finding}`).join("\n")
			: "(The reviewer asked for changes without marking a finding [blocking]; read the review for what it requires.)";
	return `${taskHeader(run)}\n\n${run.brief}\n\nReview: ${reviewPath}\n\nFix exactly these blocking findings from the review, nothing else:\n${findings}`;
}

async function commitReviewedTask(run: TaskRun, report: string): Promise<string> {
	checkAborted(run);
	await enterStage(run, "commit");
	const outcome = await commitTask(run.repoRoot, commitMessage(report, run.task.subject), run.preexisting);
	if (outcome.kind === "nothing") blocked("commit", "The task left no changes to commit.");
	if (outcome.kind === "failed") blocked("commit", `git commit failed:\n${tailLines(outcome.output, REASON_LINES)}`);
	return outcome.sha;
}

async function runTaskPipeline(run: TaskRun): Promise<string> {
	let report = await runWorker(run, freshWorkerSession(run), `${taskHeader(run)}\n\n${run.brief}`);
	report = await passChecks(run, report);
	for (let fixPasses = 0; ; fixPasses++) {
		const { verdict, reviewPath } = await reviewTask(run);
		if (verdict.pass) {
			run.record.nonBlocking = verdict.nonBlocking;
			break;
		}
		if (fixPasses >= MAX_FIX_PASSES) {
			blocked(
				"review",
				`Blocking findings remain after ${MAX_FIX_PASSES} fix passes (${reviewPath}):\n${verdict.blocking.join("\n")}`,
			);
		}
		report = await runWorker(run, freshWorkerSession(run), fixMessage(run, reviewPath, verdict.blocking));
		report = await passChecks(run, report);
	}
	return commitReviewedTask(run, report);
}

function trimReason(reason: string): string {
	const lines = reason.trim().split("\n");
	return lines.length > REASON_LINES
		? `${lines.slice(0, REASON_LINES).join("\n")}\n… ${lines.length - REASON_LINES} more lines`
		: lines.join("\n");
}

function recordFiles(run: TaskRun): string {
	const lines = [
		`workers: ${run.record.workers.join(", ") || "none"}`,
		`reviews: ${run.record.reviews.join(", ") || "none"}`,
		`checks: ${run.record.checks.join(", ") || "none"}`,
		`record: ${taskRecordPath(run.featureDir, run.task.number)}`,
	];
	return [...run.notices, ...lines].join("\n");
}

function finishRecord(run: TaskRun, status: TaskRecord["status"], extra: Partial<TaskRecord>): void {
	run.record = { ...run.record, ...extra, status, cost: run.usage.cost.total };
	writeTaskRecord(run.featureDir, run.record);
}

async function preexistingFiles(repoRoot: string): Promise<string[]> {
	const changed = await trackedChanges(repoRoot);
	if (changed.length > 0) {
		throw new Error(
			`Tracked files have uncommitted changes: ${changed.join(", ")}; expected a clean worktree so the task commits only its own work. Ask the user to commit, stash or revert them.`,
		);
	}
	return untrackedPaths(repoRoot);
}

async function startTaskRun(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	params: { feature: string; task: number; brief: string },
	signal: AbortSignal | undefined,
	onUpdate: OnUpdate,
): Promise<TaskRun> {
	const featureDir = await resolveFeatureDir(pi, ctx.cwd, params.feature);
	const specPath = requireSpec(featureDir);
	checkApproval(params.feature, specPath);
	const repoRoot = await gitTopLevel(pi, ctx.cwd);
	if (!repoRoot)
		throw new Error(`${ctx.cwd} is not inside a git repository; the task tool commits each task, so run it from one.`);
	const spec = fs.readFileSync(specPath, "utf-8");
	const task = findTask(spec, params.task);
	if (!task) {
		throw new Error(
			`Task ${params.task} not found in ${specPath}; expected a "### Task ${params.task}: <commit subject>" heading under "## Tasks".`,
		);
	}
	const checks = parseChecks(spec);
	if (checks.length === 0) {
		throw new Error(
			`No checks in ${specPath}; expected a "## Checks" section whose first fenced block lists shell commands.`,
		);
	}
	const previousRecord = readTaskRecord(featureDir, task.number);
	const untracked = await preexistingFiles(repoRoot);
	const preexisting =
		previousRecord?.status === "blocked" ? withoutPaths(untracked, previousRecord.created ?? []) : untracked;
	const switchedFrom = await ensureFeatureBranch(repoRoot, params.feature);
	if (switchedFrom) ctx.ui.notify(`Switched to branch ${params.feature}`, "info");
	const checkpoint = await createCheckpoint(repoRoot, params.feature).catch((error: unknown) => {
		ctx.ui.notify(
			`Checkpoint failed; continuing without it: ${error instanceof Error ? error.message : String(error)}`,
			"warning",
		);
		return undefined;
	});
	const notices = [
		...(switchedFrom ? [`branch: ${params.feature} (from ${switchedFrom})`] : []),
		...(checkpoint ? [`checkpoint: ${checkpoint}`] : []),
	];
	return {
		pi,
		ctx,
		signal,
		onUpdate,
		feature: params.feature,
		featureDir,
		specPath,
		repoRoot,
		task,
		brief: params.brief,
		checks,
		preexisting,
		earlierReviews: previousRecord?.reviews ?? [],
		record: {
			task: task.number,
			subject: task.subject,
			status: "blocked",
			workers: [],
			reviews: [],
			checks: [],
			nonBlocking: [],
			cost: 0,
		},
		usage: emptyUsage(),
		turns: 0,
		toolCalls: 0,
		notices,
	};
}

function taskDetails(run: TaskRun): LoopDetails {
	return {
		stage: runningStage ?? "worker",
		feature: run.feature,
		turns: run.turns,
		toolCalls: run.toolCalls,
		usage: run.usage,
	};
}

async function blockedResult(run: TaskRun, error: unknown) {
	const stage: BlockedStage =
		error instanceof TaskBlocked ? error.stage : run.signal?.aborted ? "aborted" : (runningStage ?? "worker");
	const reason = error instanceof Error ? error.message : String(error);
	const untracked = await untrackedPaths(run.repoRoot).catch(() => []);
	finishRecord(run, "blocked", { stage, created: withoutPaths(untracked, run.preexisting) });
	return {
		content: [
			{
				type: "text" as const,
				text: `blocked: ${stage}\n${trimReason(reason)}\ncost: $${run.usage.cost.total.toFixed(2)}\n\n${recordFiles(run)}`,
			},
		],
		details: taskDetails(run),
		usage: run.usage,
		isError: true,
	};
}

async function executeTask(run: TaskRun) {
	let sha: string;
	try {
		sha = await runTaskPipeline(run);
	} catch (error) {
		return blockedResult(run, error);
	}
	finishRecord(run, "committed", { sha });
	const shortSha = (await gitText(run.repoRoot, ["rev-parse", "--short", sha])) ?? sha.slice(0, 12);
	const subject = (await gitText(run.repoRoot, ["log", "-1", "--format=%s", sha])) ?? run.task.subject;
	const nonBlocking = run.record.nonBlocking.map((finding) => `- ${finding}`).join("\n") || "none";
	return {
		content: [
			{
				type: "text" as const,
				text: `committed ${shortSha} ${subject}\ncost: $${run.usage.cost.total.toFixed(2)}\n\nnon-blocking findings:\n${nonBlocking}\n\n${recordFiles(run)}`,
			},
		],
		details: taskDetails(run),
		usage: run.usage,
	};
}

interface FeatureTarget {
	feature: string;
	featureDir: string;
}

function contextCapMessage(tokens: number, target: FeatureTarget | undefined): string {
	const reached = `The context cap was reached: context is at ${tokens} tokens (cap ${plannerContextCap}). Finish the current step only if it is one tool call.`;
	if (!target) {
		return `${reached} Then summarise in chat what is done, the current state, the next steps, open questions and decisions, and STOP. Tell the user to start a new session and paste the summary there.`;
	}
	return `${reached} Then write ${path.join(target.featureDir, "status.md")}: the tasks committed with their SHAs, the current task and its state, the next steps, open questions, decisions, and anything the user said that the spec does not record. Then STOP and tell the user to run /resume-feature ${target.feature}.`;
}

async function enforceContextCap(pi: ExtensionAPI, ctx: ExtensionContext): Promise<void> {
	const tokens = ctx.getContextUsage()?.tokens;
	if (tokens === undefined || tokens === null) return;
	const step = contextCapStep(tokens, plannerContextCap, PLANNER_CONTEXT_HARD_MARGIN, contextCapState);
	const feature = lastTouchedFeature;
	if (step.abort) {
		contextCapState.aborted = true;
		ctx.abort();
		const resume = feature ? `/resume-feature ${feature}` : "/resume-feature <feature>, or start a new session,";
		ctx.ui.notify(
			`Context at ${tokens} tokens passed the hard stop of ${plannerContextCap + PLANNER_CONTEXT_HARD_MARGIN}; aborted the agent. Run ${resume} to continue.`,
			"warning",
		);
	}
	if (step.warn) {
		contextCapState.warned = true;
		const target = feature ? { feature, featureDir: path.join(await projectPlansDir(pi, ctx.cwd), feature) } : undefined;
		pi.sendUserMessage(contextCapMessage(tokens, target), { deliverAs: "steer" });
	}
}

function resumeMessage(target: FeatureTarget, approved: boolean): string {
	const { feature, featureDir } = target;
	const reads = [
		`Resume feature ${feature}.`,
		`Read ${path.join(featureDir, "spec.md")}, ${path.join(featureDir, "status.md")} if it exists, every task-*.json in ${featureDir}, and \`git log --oneline\` since the feature started (from the upstream default branch to HEAD).`,
		`The rules of /feature are in ${path.join(getAgentDir(), "prompts", "feature.md")}; follow them.`,
	].join(" ");
	const next = approved
		? "Then continue from the first task that is not committed by calling `task`."
		: "The spec changed after its approval or was never approved: present it to the user and STOP until they run /approve.";
	return `${reads}\n\n${next}`;
}

async function resumeFeature(pi: ExtensionAPI, args: string, ctx: ExtensionCommandContext): Promise<void> {
	if (!ctx.isIdle()) {
		ctx.ui.notify("The agent is busy; wait for it to stop, then run /resume-feature again.", "warning");
		return;
	}
	const feature = args.trim() || lastTouchedFeature;
	if (!feature) {
		ctx.ui.notify("No feature to resume; run /resume-feature <feature>.", "warning");
		return;
	}
	let featureDir: string;
	try {
		featureDir = await resolveFeatureDir(pi, ctx.cwd, feature);
	} catch (error) {
		ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		return;
	}
	const specPath = path.join(featureDir, "spec.md");
	if (!fs.existsSync(specPath)) {
		ctx.ui.notify(`Spec not found at ${specPath}; expected an existing feature. Check the slug.`, "error");
		return;
	}
	const specHash = hashFile(specPath);
	const approved = approvals.get(feature) === specHash;
	const message = resumeMessage({ feature, featureDir }, approved);
	const result = await ctx.newSession({
		setup: async (sessionManager) => {
			sessionManager.appendCustomEntry(APPROVAL_ENTRY, {
				feature,
				specHash: approved ? specHash : null,
			} satisfies ApprovalEntryData);
		},
		withSession: async (sessionCtx) => {
			sessionCtx.sendUserMessage(message).catch((error: unknown) => {
				sessionCtx.ui.notify(
					`Failed to send the resume prompt: ${error instanceof Error ? error.message : String(error)}`,
					"error",
				);
			});
		},
	});
	if (result.cancelled) ctx.ui.notify("Resume cancelled; stayed in this session.", "info");
}

const FeatureParam = Type.String({
	description: "Kebab-case feature slug; the spec lives at ~/.pi/plans/<project-slug>/<feature>/spec.md",
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "task",
		label: "Task",
		description: [
			"Run one task of a feature's spec.md end to end: the DeepSeek V4.1 Flash worker implements it, the spec's Checks run, the MiniMax M3.1 Flash reviewer reviews it, up to 2 fix passes address blocking findings, then the loop commits it.",
			"Needs the user's /approve of the current spec.md; the approval covers every task until spec.md changes.",
			"Needs a clean worktree for tracked files. From the repository's default branch, the first task switches to a branch named after the feature.",
			"One task runs at a time. Returns `committed <sha> <subject>` with the non-blocking findings, or `blocked: <stage>` with the reason and file paths.",
			"Each task and each fix pass runs a fresh worker; only a failed check returns to the same worker.",
		].join(" "),
		parameters: Type.Object({
			feature: FeatureParam,
			task: Type.Integer({ minimum: 1, description: "Task number from the spec's `### Task <n>: <subject>` heading" }),
			brief: Type.String({ description: "What the worker must know beyond the spec" }),
		}),

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			return withLock(
				() => refreshStatus(pi, ctx),
				async () => executeTask(await startTaskRun(pi, ctx, params, signal, onUpdate)),
			);
		},

		renderCall(args, theme) {
			return callView(
				"task",
				args.feature,
				args.task === undefined ? args.brief : `${args.task}: ${args.brief ?? ""}`,
				theme,
			);
		},

		renderResult(result, options, theme, context) {
			return resultView(result, options, theme, context.state);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		contextCapState.warned = false;
		contextCapState.aborted = false;
		restoreFromBranch(pi, ctx);
		await refreshStatus(pi, ctx);
	});

	pi.on("turn_end", async (_event, ctx) => {
		await enforceContextCap(pi, ctx);
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName === "task") {
			const feature = event.input.feature;
			if (typeof feature !== "string" || !FEATURE_PATTERN.test(feature)) return undefined;
			touchFeature(pi, feature);
			await refreshStatus(pi, ctx);
		} else if (event.toolName === "write" || event.toolName === "edit") {
			const filePath = event.input.path;
			if (typeof filePath !== "string") return undefined;
			const feature = await featureOfSpecPath(pi, ctx.cwd, filePath);
			if (!feature) return undefined;
			touchFeature(pi, feature);
			await refreshStatus(pi, ctx);
		}
		return undefined;
	});

	pi.registerCommand("approve", {
		description: "Approve the current spec so its tasks can run; text after it goes to the agent",
		handler: async (args, ctx) => {
			if (!ctx.isIdle()) {
				ctx.ui.notify("The agent is busy; wait for it to stop, then run /approve again.", "warning");
				return;
			}
			const feature = await featureToApprove(pi, ctx.cwd);
			if (!feature) {
				ctx.ui.notify("No spec to approve", "warning");
				return;
			}
			const featureDir = path.join(await projectPlansDir(pi, ctx.cwd), feature);
			recordApproval(pi, feature, hashFile(path.join(featureDir, "spec.md")));
			touchFeature(pi, feature);
			await refreshStatus(pi, ctx);
			ctx.ui.notify(`Approved ${feature}`, "info");
			const notes = args.trim();
			pi.sendUserMessage(`Approved: run the tasks for ${feature}.${notes ? `\n\n${notes}` : ""}`);
		},
	});

	pi.registerCommand("resume-feature", {
		description:
			"Continue a feature in a fresh session from its spec, status.md and task records; the approval carries only while spec.md is unchanged",
		handler: async (args, ctx) => resumeFeature(pi, args, ctx),
	});
}
