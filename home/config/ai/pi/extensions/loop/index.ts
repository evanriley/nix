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
const PLANNER_CONTEXT_CAP = 350_000;
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
		model: "openrouter/minimax/minimax-m3.1-flash",
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

function runGit(cwd: string, args: string[], input?: Buffer, env?: NodeJS.ProcessEnv): Promise<Buffer> {
	return new Promise((resolve, reject) => {
		const child = spawn("git", args, { cwd, env, shell: false, stdio: ["pipe", "pipe", "pipe"] });
		const stdout: Buffer[] = [];
		let stderr = "";
		child.stdout.on("data", (data: Buffer) => stdout.push(data));
		child.stderr.on("data", (data) => {
			stderr += data.toString();
		});
		child.on("error", reject);
		child.on("close", (code) => {
			if (code === 0) resolve(Buffer.concat(stdout));
			else reject(new Error(`git ${args.join(" ")} failed (exit ${code}): ${stderr.trim()}`));
		});
		child.stdin.end(input);
	});
}

async function gitText(cwd: string, args: string[]): Promise<string | undefined> {
	const output = await runGit(cwd, args).catch(() => undefined);
	return output?.toString().trim() || undefined;
}

async function nextCheckpointNumber(repoRoot: string, feature: string): Promise<number> {
	const refs = await runGit(repoRoot, ["for-each-ref", "--format=%(refname)", `refs/pi/${feature}/`]);
	const numbers = refs
		.toString()
		.split("\n")
		.map((ref) => Number(ref.slice(`refs/pi/${feature}/`.length)))
		.filter((number) => Number.isInteger(number));
	return numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
}

async function createCheckpoint(repoRoot: string, feature: string): Promise<string> {
	const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-checkpoint-"));
	try {
		const indexFile = path.join(tempDir, "index");
		const realIndex = path.resolve(repoRoot, (await runGit(repoRoot, ["rev-parse", "--git-path", "index"])).toString().trim());
		if (fs.existsSync(realIndex)) fs.copyFileSync(realIndex, indexFile);
		const env = {
			...process.env,
			GIT_INDEX_FILE: indexFile,
			GIT_AUTHOR_NAME: "pi",
			GIT_AUTHOR_EMAIL: "pi@localhost",
			GIT_COMMITTER_NAME: "pi",
			GIT_COMMITTER_EMAIL: "pi@localhost",
		};
		await runGit(repoRoot, ["add", "-A"], undefined, env);
		const tree = (await runGit(repoRoot, ["write-tree"], undefined, env)).toString().trim();
		const number = await nextCheckpointNumber(repoRoot, feature);
		const ref = `refs/pi/${feature}/${number}`;
		const hasHead = (await gitText(repoRoot, ["rev-parse", "--verify", "--quiet", "HEAD"])) !== undefined;
		const parent = hasHead ? ["-p", "HEAD"] : [];
		const commit = (
			await runGit(repoRoot, ["commit-tree", tree, ...parent, "-m", `pi checkpoint ${feature} ${number}`], undefined, env)
		)
			.toString()
			.trim();
		await runGit(repoRoot, ["update-ref", ref, commit]);
		return ref;
	} finally {
		fs.rmSync(tempDir, { recursive: true, force: true });
	}
}

async function currentBranch(repoRoot: string): Promise<string | undefined> {
	return gitText(repoRoot, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
}

async function defaultBranch(repoRoot: string): Promise<string> {
	const remoteHead = await gitText(repoRoot, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]);
	if (remoteHead) return remoteHead.replace(/^origin\//, "");
	return (await gitText(repoRoot, ["config", "init.defaultBranch"])) ?? "main";
}

async function branchExists(repoRoot: string, branch: string): Promise<boolean> {
	return (await gitText(repoRoot, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`])) !== undefined;
}

async function ensureFeatureBranch(repoRoot: string, feature: string): Promise<string | undefined> {
	const enabled = await gitText(repoRoot, ["config", "--type=bool", "pi.featureBranches"]);
	if (enabled === "false") return undefined;
	const current = await currentBranch(repoRoot);
	if (!current) return undefined;
	const base = await defaultBranch(repoRoot);
	if (current !== base) return undefined;
	const args = (await branchExists(repoRoot, feature)) ? ["switch", feature] : ["switch", "-c", feature];
	await runGit(repoRoot, args);
	return base;
}

async function removeScratch(repoRoot: string, scratchDir: string): Promise<void> {
	if (fs.existsSync(scratchDir)) {
		await runGit(repoRoot, ["worktree", "remove", "--force", scratchDir]).catch(() => undefined);
		fs.rmSync(scratchDir, { recursive: true, force: true });
	}
	await runGit(repoRoot, ["worktree", "prune"]).catch(() => undefined);
}

async function createScratch(repoRoot: string, scratchDir: string): Promise<void> {
	await runGit(repoRoot, ["worktree", "add", "--detach", scratchDir, "HEAD"]);
	const diff = await runGit(repoRoot, ["diff", "HEAD", "--binary"]);
	if (diff.length > 0) await runGit(scratchDir, ["apply", "--binary"], diff);
	const untracked = (await runGit(repoRoot, ["ls-files", "--others", "--exclude-standard", "-z"]))
		.toString("utf-8")
		.split("\0")
		.filter((name) => name.length > 0);
	for (const name of untracked) {
		const target = path.join(scratchDir, name);
		fs.mkdirSync(path.dirname(target), { recursive: true });
		fs.cpSync(path.join(repoRoot, name), target, { recursive: true, verbatimSymlinks: true });
	}
}

function countLines(filePath: string): number {
	if (!fs.existsSync(filePath)) return 0;
	return fs.readFileSync(filePath, "utf-8").split("\n").length - 1;
}

function lastNonEmptyLine(text: string): string | undefined {
	const lines = text
		.split("\n")
		.map((line) => line.replace(/\s+/g, " ").trim())
		.filter((line) => line.length > 0);
	return lines.at(-1);
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}
	const execName = path.basename(process.execPath).toLowerCase();
	if (!/^(node|bun)(\.exe)?$/.test(execName)) {
		return { command: process.execPath, args };
	}
	return { command: "pi", args };
}

function buildChildArgs(config: ChildConfig, message: string): string[] {
	return [
		"--mode",
		"json",
		"-p",
		"--session",
		config.sessionFile,
		"--model",
		config.model,
		"--thinking",
		config.thinking,
		"--tools",
		config.tools.join(","),
		"--no-extensions",
		"--extension",
		path.join(getAgentDir(), "extensions", "guard", "index.ts"),
		"--extension",
		path.join(getAgentDir(), "extensions", "vision", "index.ts"),
		...(config.tools.some((tool) => tool.startsWith("mcp__")) ? ["--extension", "builtin:mcp"] : []),
		"--no-prompt-templates",
		"--append-system-prompt",
		config.promptFile,
		"--",
		message,
	];
}

function childEnvironment(config: ChildConfig): NodeJS.ProcessEnv {
	const environment: NodeJS.ProcessEnv = { ...process.env, PI_LOOP_ROLE: config.role };
	delete environment.PI_LOOP_SCRATCH;
	if (config.scratch) environment.PI_LOOP_SCRATCH = config.scratch;
	return environment;
}

function lastAssistantText(message: Message): string | undefined {
	if (message.role !== "assistant") return undefined;
	const texts = message.content.filter((part) => part.type === "text").map((part) => part.text);
	return texts.length > 0 ? texts.join("\n") : undefined;
}

function runChild(
	config: ChildConfig,
	message: string,
	cwd: string,
	signal: AbortSignal | undefined,
	onProgress: (result: ChildResult) => void,
): Promise<ChildResult> {
	const result: ChildResult = {
		exitCode: 0,
		finalText: "",
		stderr: "",
		turns: 0,
		toolCalls: 0,
		usage: emptyUsage(),
	};
	const invocation = getPiInvocation(buildChildArgs(config, message));

	return new Promise((resolve) => {
		const child = spawn(invocation.command, invocation.args, {
			cwd,
			env: childEnvironment(config),
			shell: false,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let buffer = "";
		let thinkingText = "";
		let lastProgressAt = 0;
		let limitTimer: NodeJS.Timeout | undefined;

		const reportProgress = () => {
			lastProgressAt = Date.now();
			onProgress(result);
		};

		const processThinking = (assistantEvent: { type?: string; delta?: string; content?: string }) => {
			if (assistantEvent.type === "thinking_start") thinkingText = "";
			else if (assistantEvent.type === "thinking_delta") thinkingText += assistantEvent.delta ?? "";
			else if (assistantEvent.type === "thinking_end") thinkingText = assistantEvent.content ?? thinkingText;
			else return;
			result.thinkingLine = lastNonEmptyLine(thinkingText) ?? result.thinkingLine;
			if (Date.now() - lastProgressAt >= PROGRESS_INTERVAL_MS) reportProgress();
		};

		const processLine = (line: string) => {
			if (!line.trim()) return;
			let event: {
				type?: string;
				message?: Message;
				assistantMessageEvent?: { type?: string; delta?: string; content?: string };
			};
			try {
				event = JSON.parse(line);
			} catch {
				return;
			}
			if (event.type === "message_update" && event.assistantMessageEvent) {
				processThinking(event.assistantMessageEvent);
				return;
			}
			if (event.type !== "message_end" || event.message?.role !== "assistant") return;
			const assistant = event.message;
			result.turns++;
			result.toolCalls += assistant.content.filter((part) => part.type === "toolCall").length;
			if (assistant.usage) addUsage(result.usage, assistant.usage);
			if (!result.limit && result.turns >= config.maxTurns) {
				stopAtLimit({ kind: "turn", value: `${config.maxTurns} turns` });
			} else if (!result.limit && result.usage.cost.total >= config.maxCost) {
				stopAtLimit({ kind: "cost", value: `$${config.maxCost.toFixed(2)}` });
			}
			result.finalText = lastAssistantText(assistant) ?? result.finalText;
			if (assistant.stopReason) result.stopReason = assistant.stopReason;
			if (assistant.errorMessage) result.errorMessage = assistant.errorMessage;
			reportProgress();
		};

		child.stdout.on("data", (data) => {
			buffer += data.toString();
			const lines = buffer.split("\n");
			buffer = lines.pop() ?? "";
			for (const line of lines) processLine(line);
		});
		child.stderr.on("data", (data) => {
			result.stderr += data.toString();
		});
		const stop = () => {
			child.kill("SIGTERM");
			setTimeout(() => {
				if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
			}, 5000);
		};

		const stopAtLimit = (limit: LimitHit) => {
			result.limit = limit;
			stop();
		};
		limitTimer = setTimeout(
			() => stopAtLimit({ kind: "time", value: `${config.maxMinutes} min` }),
			config.maxMinutes * 60_000,
		);

		child.on("close", (code) => {
			clearTimeout(limitTimer);
			signal?.removeEventListener("abort", stop);
			if (buffer.trim()) processLine(buffer);
			result.exitCode = code ?? 1;
			resolve(result);
		});
		child.on("error", (error) => {
			clearTimeout(limitTimer);
			result.stderr += error.message;
			result.exitCode = 1;
			resolve(result);
		});

		if (signal?.aborted) stop();
		else signal?.addEventListener("abort", stop, { once: true });
	});
}

function isFailed(result: ChildResult): boolean {
	return result.limit !== undefined || result.exitCode !== 0 || result.stopReason === "error" || result.stopReason === "aborted";
}

function failureText(role: Role, result: ChildResult): string {
	if (result.limit) return `The ${role} stopped at its ${result.limit.kind} limit (${result.limit.value})`;
	const reason = result.errorMessage || result.stderr.trim() || result.finalText || "(no output)";
	return `The ${role} failed (exit ${result.exitCode}, stop reason ${result.stopReason ?? "none"}): ${reason}`;
}

function makeDetails(
	stage: Stage,
	feature: string,
	result: ChildResult,
	transcript: TranscriptRef,
	reviewPath?: string,
): LoopDetails {
	return {
		stage,
		feature,
		turns: result.turns,
		toolCalls: result.toolCalls,
		usage: result.usage,
		transcript,
		reviewPath,
	};
}

async function withLock<T>(onChange: () => Promise<void>, run: () => Promise<T>): Promise<T> {
	if (taskRunning) {
		throw new Error("A task is already running; wait for it to finish before starting another.");
	}
	taskRunning = true;
	try {
		return await run();
	} finally {
		taskRunning = false;
		runningStage = undefined;
		await onChange();
	}
}

type OnUpdate = ((partial: AgentToolResult<LoopDetails>) => void) | undefined;

function progressHeader(details: Pick<LoopDetails, "stage" | "turns" | "toolCalls" | "command">): string {
	if (details.stage === "checks") return `checks running: ${details.command ?? ""}`;
	return `${details.stage} running: ${details.turns} turns, ${details.toolCalls} tool calls`;
}

function progressReporter(
	stage: Stage,
	feature: string,
	transcript: TranscriptRef,
	onUpdate: OnUpdate,
): (result: ChildResult) => void {
	return (result) => {
		const details = { ...makeDetails(stage, feature, result, transcript), thinkingLine: result.thinkingLine };
		const thinkText = result.thinkingLine ? `\nthink: ${result.thinkingLine}` : "";
		onUpdate?.({
			content: [{ type: "text", text: `${progressHeader(details)}${thinkText}` }],
			details,
		});
	};
}

function tailToWidth(text: string, width: number): string {
	const textWidth = visibleWidth(text);
	if (textWidth <= width) return text;
	return `…${sliceByColumn(text, textWidth - width + 1, width - 1)}`;
}

function progressView(details: LoopDetails, theme: Theme): Component {
	return {
		invalidate() {},
		render(width) {
			const lines = [truncateToWidth(theme.fg("warning", progressHeader(details)), width)];
			if (details.thinkingLine) {
				const label = "think: ";
				const tail = tailToWidth(details.thinkingLine, Math.max(1, width - visibleWidth(label)));
				lines.push(truncateToWidth(theme.fg("muted", label) + theme.fg("thinkingText", theme.italic(tail)), width));
			}
			return lines;
		},
	};
}

function resultText(result: AgentToolResult<LoopDetails | undefined>): string {
	return result.content
		.filter((part) => part.type === "text")
		.map((part) => part.text)
		.join("\n");
}

function reportView(text: string, expanded: boolean, theme: Theme): Component {
	const lines = text.split("\n");
	const shown = expanded ? lines : lines.slice(0, COLLAPSED_REPORT_LINES);
	let rendered = shown.map((line) => theme.fg("toolOutput", line)).join("\n");
	const remaining = lines.length - shown.length;
	if (remaining > 0) {
		rendered += `${theme.fg("muted", `\n... (${remaining} more lines,`)} ${keyHint("app.tools.expand", "to expand")}${theme.fg("muted", ")")}`;
	}
	return new Text(rendered, 0, 0);
}

function readDispatchMessages(transcript: TranscriptRef): Message[] | undefined {
	if (!fs.existsSync(transcript.file)) return undefined;
	const messages: Message[] = [];
	for (const line of fs.readFileSync(transcript.file, "utf-8").split("\n").slice(transcript.fromLine)) {
		if (!line.trim()) continue;
		let entry: { type?: string; message?: Message };
		try {
			entry = JSON.parse(line);
		} catch {
			continue;
		}
		if (entry.type !== "message" || !entry.message) continue;
		if (entry.message.role === "user" && messages.some((message) => message.role === "user")) break;
		messages.push(entry.message);
	}
	return messages;
}

function cachedDispatchMessages(transcript: TranscriptRef, state: { transcript?: TranscriptCache }) {
	const key = `${transcript.file}:${transcript.fromLine}`;
	if (state.transcript?.key !== key) state.transcript = { key, messages: readDispatchMessages(transcript) };
	return state.transcript.messages;
}

function trimBlock(text: string, theme: Theme): string {
	const lines = text.replace(/\s+$/, "").split("\n");
	if (lines.length <= TRANSCRIPT_BLOCK_LINES) return lines.join("\n");
	const remaining = lines.length - TRANSCRIPT_BLOCK_LINES;
	return `${lines.slice(0, TRANSCRIPT_BLOCK_LINES).join("\n")}\n${theme.fg("muted", `… ${remaining} more lines`)}`;
}

function formatArguments(args: Record<string, unknown>): string {
	return Object.entries(args)
		.map(([key, value]) => `${key}: ${typeof value === "string" ? value : JSON.stringify(value, null, 2)}`)
		.join("\n");
}

function transcriptView(messages: Message[], theme: Theme): Component {
	const container = new Container();
	const markdownTheme = getMarkdownTheme();
	const add = (component: Component) => {
		if (container.children.length > 0) container.addChild(new Spacer(1));
		container.addChild(component);
	};
	for (const message of messages) {
		if (message.role === "user") {
			const text =
				typeof message.content === "string"
					? message.content
					: message.content
							.filter((part) => part.type === "text")
							.map((part) => part.text)
							.join("\n");
			add(new Text(theme.fg("muted", "task\n") + theme.fg("dim", trimBlock(text, theme)), 0, 0));
		} else if (message.role === "assistant") {
			for (const part of message.content) {
				if (part.type === "thinking" && part.thinking.trim()) {
					add(new Text(theme.fg("thinkingText", theme.italic(part.thinking.trim())), 0, 0));
				} else if (part.type === "text" && part.text.trim()) {
					add(new Markdown(part.text.trim(), 0, 0, markdownTheme));
				} else if (part.type === "toolCall") {
					const header = theme.fg("muted", "→ ") + theme.fg("toolTitle", theme.bold(part.name));
					const args = formatArguments(part.arguments);
					add(new Text(args ? `${header}\n${theme.fg("dim", trimBlock(args, theme))}` : header, 0, 0));
				}
			}
		} else if (message.role === "toolResult") {
			const text = message.content
				.filter((part) => part.type === "text")
				.map((part) => part.text)
				.join("\n");
			add(new Text(theme.fg(message.isError ? "error" : "toolOutput", trimBlock(text || "(no output)", theme)), 0, 0));
		}
	}
	if (container.children.length === 0) container.addChild(new Text(theme.fg("muted", "(empty transcript)"), 0, 0));
	return container;
}

function callView(label: string, feature: string | undefined, brief: string | undefined, theme: Theme): Component {
	const header = `${theme.fg("toolTitle", theme.bold(label))} ${theme.fg("accent", feature ?? "...")}`;
	return new TruncatedText(brief ? `${header} ${theme.fg("muted", brief.replace(/\s+/g, " "))}` : header, 0, 0);
}

function resultView(
	result: AgentToolResult<LoopDetails | undefined>,
	options: { expanded: boolean; isPartial: boolean },
	theme: Theme,
	state: { transcript?: TranscriptCache },
): Component {
	const details = result.details;
	if (options.isPartial && details) return progressView(details, theme);
	if (options.expanded && details?.transcript) {
		const messages = cachedDispatchMessages(details.transcript, state);
		if (!messages) return new Text(theme.fg("error", `transcript not found: ${details.transcript.file}`), 0, 0);
		return transcriptView(messages, theme);
	}
	return reportView(resultText(result), options.expanded, theme);
}

class TaskBlocked extends Error {
	stage: BlockedStage;

	constructor(stage: BlockedStage, reason: string) {
		super(reason);
		this.stage = stage;
	}
}

function blocked(stage: BlockedStage, reason: string): never {
	throw new TaskBlocked(stage, reason);
}

interface TaskRun {
	pi: ExtensionAPI;
	ctx: ExtensionContext;
	signal: AbortSignal | undefined;
	onUpdate: OnUpdate;
	feature: string;
	featureDir: string;
	specPath: string;
	repoRoot: string;
	task: SpecTask;
	brief: string;
	checks: string[];
	preexisting: string[];
	earlierReviews: string[];
	record: TaskRecord;
	usage: Usage;
	turns: number;
	toolCalls: number;
	notices: string[];
}

async function enterStage(run: TaskRun, stage: Stage): Promise<void> {
	runningStage = stage;
	await refreshStatus(run.pi, run.ctx);
}

function checkAborted(run: TaskRun): void {
	if (run.signal?.aborted) blocked("aborted", "The task was aborted.");
}

function checkBudget(run: TaskRun): void {
	const cost = featureCost(run.featureDir);
	if (cost >= FEATURE_MAX_COST) {
		blocked(
			"budget",
			`The feature has spent $${cost.toFixed(2)} of its $${FEATURE_MAX_COST.toFixed(2)} budget; ask the user before spending more.`,
		);
	}
}

function addChildResult(run: TaskRun, result: ChildResult): void {
	addUsage(run.usage, result.usage);
	run.turns += result.turns;
	run.toolCalls += result.toolCalls;
}

function taskHeader(run: TaskRun): string {
	return `Spec: ${run.specPath}\nTask ${run.task.number}: ${run.task.subject}`;
}

async function runWorker(run: TaskRun, session: WorkerSession, message: string): Promise<string> {
	checkAborted(run);
	checkBudget(run);
	await enterStage(run, "worker");
	if (session.notice) run.notices.push(session.notice);
	if (!run.record.workers.includes(session.file)) run.record.workers.push(session.file);
	const transcript = { file: session.file, fromLine: session.resumed ? countLines(session.file) : 0 };
	const result = await runChild(
		{ ...ROLE_CONFIG.worker, sessionFile: session.file },
		message,
		run.ctx.cwd,
		run.signal,
		progressReporter("worker", run.feature, transcript, run.onUpdate),
	);
	addChildResult(run, result);
	checkAborted(run);
	if (isFailed(result)) blocked("worker", failureText("worker", result));
	return result.finalText;
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
