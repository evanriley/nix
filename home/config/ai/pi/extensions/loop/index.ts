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

const EXTENSION_DIR = path.dirname(fileURLToPath(import.meta.url));
const PLANS_DIR = path.join(os.homedir(), ".pi", "plans");
const FEATURE_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
const PROGRESS_INTERVAL_MS = 250;
const COLLAPSED_REPORT_LINES = 10;
const TRANSCRIPT_BLOCK_LINES = 20;
const APPROVAL_ENTRY = "loop-approval";
const STATUS_KEY = "loop";

type Role = "worker" | "reviewer";

interface ChildConfig {
	model: string;
	thinking: string;
	tools: string[];
	promptFile: string;
	sessionFile: string;
}

const ROLE_CONFIG: Record<Role, Omit<ChildConfig, "sessionFile">> = {
	worker: {
		model: "coralbricks/deepseek-v4.1-flash-fast",
		thinking: "high",
		tools: ["read", "bash", "edit", "write"],
		promptFile: path.join(EXTENSION_DIR, "worker.md"),
	},
	reviewer: {
		model: "coralbricks/glm-5.3-fast",
		thinking: "high",
		tools: ["read", "grep", "find", "ls", "bash"],
		promptFile: path.join(EXTENSION_DIR, "reviewer.md"),
	},
};

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
}

interface TranscriptRef {
	file: string;
	fromLine: number;
}

interface LoopDetails {
	role: Role;
	feature: string;
	turns: number;
	toolCalls: number;
	usage: Usage;
	transcript?: TranscriptRef;
	reviewPath?: string;
	thinkingLine?: string;
}

interface TranscriptCache {
	key: string;
	messages: Message[] | undefined;
}

let runningRole: Role | undefined;
let lastTouchedFeature: string | undefined;
const approvals = new Map<string, string>();

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

function formatUsage(result: ChildResult): string {
	const { usage } = result;
	return `usage: input=${usage.input} cacheRead=${usage.cacheRead} cacheWrite=${usage.cacheWrite} output=${usage.output} cost=$${usage.cost.total.toFixed(4)} turns=${result.turns}`;
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

function consumeApproval(pi: ExtensionAPI, feature: string): void {
	recordApproval(pi, feature, null);
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
	if (runningRole) return `${runningRole} running`;
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

function reviewNumbers(featureDir: string, pattern: RegExp): number[] {
	if (!fs.existsSync(featureDir)) return [];
	return fs
		.readdirSync(featureDir)
		.map((name) =>
			pattern
				.exec(name)
				?.slice(1)
				.find((group) => group !== undefined),
		)
		.filter((match): match is string => match !== undefined)
		.map(Number)
		.sort((left, right) => left - right);
}

function nextReviewNumber(featureDir: string): number {
	const numbers = reviewNumbers(featureDir, /^(?:review-(\d+)\.(?:md|jsonl)|scratch-(\d+))$/);
	return numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
}

function previousReviewPaths(featureDir: string): string[] {
	return reviewNumbers(featureDir, /^review-(\d+)\.md$/).map((number) => path.join(featureDir, `review-${number}.md`));
}

function runGit(cwd: string, args: string[], input?: Buffer): Promise<Buffer> {
	return new Promise((resolve, reject) => {
		const child = spawn("git", args, { cwd, shell: false, stdio: ["pipe", "pipe", "pipe"] });
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

async function reviewScope(repoRoot: string | undefined, feature: string): Promise<string> {
	const uncommitted =
		"Review the uncommitted changes in this repository against the spec: run `git status`, `git diff` and `git diff --cached`, and read every untracked file.";
	if (!repoRoot || (await currentBranch(repoRoot)) !== feature) return uncommitted;
	const base = await defaultBranch(repoRoot);
	const ref = (await branchExists(repoRoot, base)) ? base : `origin/${base}`;
	const mergeBase = await gitText(repoRoot, ["merge-base", "HEAD", ref]);
	if (!mergeBase) return uncommitted;
	return `Review the changes on this branch against the spec: run \`git status\`, \`git log --oneline ${mergeBase}..HEAD\` and \`git diff ${mergeBase}\`, and read every untracked file.`;
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
		path.join(getAgentDir(), "extensions", "permission-gate.ts"),
		"--no-prompt-templates",
		"--append-system-prompt",
		config.promptFile,
		"--",
		message,
	];
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
		const child = spawn(invocation.command, invocation.args, { cwd, shell: false, stdio: ["ignore", "pipe", "pipe"] });
		let buffer = "";
		let thinkingText = "";
		let lastProgressAt = 0;

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

		child.on("close", (code) => {
			signal?.removeEventListener("abort", stop);
			if (buffer.trim()) processLine(buffer);
			result.exitCode = code ?? 1;
			resolve(result);
		});
		child.on("error", (error) => {
			result.stderr += error.message;
			result.exitCode = 1;
			resolve(result);
		});

		if (signal?.aborted) stop();
		else signal?.addEventListener("abort", stop, { once: true });
	});
}

function isFailed(result: ChildResult): boolean {
	return result.exitCode !== 0 || result.stopReason === "error" || result.stopReason === "aborted";
}

function failureText(role: Role, result: ChildResult): string {
	const reason = result.errorMessage || result.stderr.trim() || result.finalText || "(no output)";
	return `The ${role} failed (exit ${result.exitCode}, stop reason ${result.stopReason ?? "none"}): ${reason}\n\n${formatUsage(result)}`;
}

function makeDetails(
	role: Role,
	feature: string,
	result: ChildResult,
	transcript: TranscriptRef,
	reviewPath?: string,
): LoopDetails {
	return {
		role,
		feature,
		turns: result.turns,
		toolCalls: result.toolCalls,
		usage: result.usage,
		transcript,
		reviewPath,
	};
}

async function withLock<T>(role: Role, onChange: () => Promise<void>, run: () => Promise<T>): Promise<T> {
	if (runningRole) {
		throw new Error(`The ${runningRole} is already running; wait for it to finish before dispatching the ${role}.`);
	}
	runningRole = role;
	try {
		await onChange();
		return await run();
	} finally {
		runningRole = undefined;
		await onChange();
	}
}

type OnUpdate = ((partial: AgentToolResult<LoopDetails>) => void) | undefined;

function progressHeader(details: Pick<LoopDetails, "role" | "turns" | "toolCalls">): string {
	return `${details.role} running: ${details.turns} turns, ${details.toolCalls} tool calls`;
}

function progressReporter(
	role: Role,
	feature: string,
	transcript: TranscriptRef,
	onUpdate: OnUpdate,
): (result: ChildResult) => void {
	return (result) => {
		const details = { ...makeDetails(role, feature, result, transcript), thinkingLine: result.thinkingLine };
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

function callView(role: Role, feature: string | undefined, brief: string | undefined, theme: Theme): Component {
	const header = `${theme.fg("toolTitle", theme.bold(role))} ${theme.fg("accent", feature ?? "...")}`;
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

const FeatureParam = Type.String({
	description: "Kebab-case feature slug; the spec lives at ~/.pi/plans/<project-slug>/<feature>/spec.md",
});

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "worker",
		label: "Worker",
		description: [
			"Dispatch the implementation worker (DeepSeek V4.1 Flash) for a feature whose spec.md exists.",
			"Each dispatch needs the user's /approve; one approval allows exactly one call. The worker keeps one session per feature, so later calls are fix passes that see earlier work.",
			"From the repository's default branch, a dispatch first switches to a branch named after the feature.",
			"Only one worker or reviewer runs at a time. Returns the worker's report and token usage.",
		].join(" "),
		parameters: Type.Object({
			feature: FeatureParam,
			task: Type.String({
				description:
					"Task brief: which spec section or which review fixes to implement, and anything the worker must know",
			}),
		}),

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const featureDir = await resolveFeatureDir(pi, ctx.cwd, params.feature);
			const specPath = requireSpec(featureDir);

			return withLock(
				"worker",
				() => refreshStatus(pi, ctx),
				async () => {
					checkApproval(params.feature, specPath);
					const repoRoot = await gitTopLevel(pi, ctx.cwd);
					const switchedFrom = repoRoot ? await ensureFeatureBranch(repoRoot, params.feature) : undefined;
					consumeApproval(pi, params.feature);
					if (switchedFrom) ctx.ui.notify(`Switched to branch ${params.feature}`, "info");
					const sessionFile = path.join(featureDir, "worker.jsonl");
					const transcript = { file: sessionFile, fromLine: countLines(sessionFile) };
					const result = await runChild(
						{ ...ROLE_CONFIG.worker, sessionFile },
						`Spec: ${specPath}\n\n${params.task}`,
						ctx.cwd,
						signal,
						progressReporter("worker", params.feature, transcript, onUpdate),
					);
					const details = makeDetails("worker", params.feature, result, transcript);
					if (isFailed(result)) {
						return {
							content: [{ type: "text", text: failureText("worker", result) }],
							details,
							usage: result.usage,
							isError: true,
						};
					}
					return {
						content: [
							{
								type: "text",
								text: `${result.finalText || "(no output)"}\n\n${formatUsage(result)}\nsession: ${sessionFile}${switchedFrom ? `\nbranch: ${params.feature} (from ${switchedFrom})` : ""}`,
							},
						],
						details,
						usage: result.usage,
					};
				},
			);
		},

		renderCall(args, theme) {
			return callView("worker", args.feature, args.task, theme);
		},

		renderResult(result, options, theme, context) {
			return resultView(result, options, theme, context.state);
		},
	});

	pi.registerTool({
		name: "reviewer",
		label: "Reviewer",
		description: [
			"Run a fresh read-only reviewer (GLM 5.3) on the uncommitted changes against the feature's spec.md.",
			"Writes the verdict to review-<n>.md next to the spec and returns it with token usage.",
			"Only one worker or reviewer runs at a time.",
		].join(" "),
		parameters: Type.Object({
			feature: FeatureParam,
			focus: Type.Optional(Type.String({ description: "Optional area the reviewer should examine most closely" })),
		}),

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const featureDir = await resolveFeatureDir(pi, ctx.cwd, params.feature);
			const specPath = requireSpec(featureDir);

			return withLock(
				"reviewer",
				() => refreshStatus(pi, ctx),
				async () => {
					const reviewNumber = nextReviewNumber(featureDir);
					const previousReviews = previousReviewPaths(featureDir);
					const repoRoot = await gitTopLevel(pi, ctx.cwd);
					const scratchDir = path.join(featureDir, `scratch-${reviewNumber}`);
					let scratchReady = false;
					if (repoRoot) {
						try {
							await createScratch(repoRoot, scratchDir);
							scratchReady = true;
						} catch (error) {
							await removeScratch(repoRoot, scratchDir);
							const reason = error instanceof Error ? error.message : String(error);
							ctx.ui.notify(`Reviewer scratch copy failed; reviewing without it: ${reason}`, "warning");
						}
					}
					const scope = await reviewScope(repoRoot, params.feature);
					try {
						return await runReview(reviewNumber, previousReviews, scratchReady ? scratchDir : undefined, scope);
					} finally {
						if (repoRoot) await removeScratch(repoRoot, scratchDir);
					}
				},
			);

			async function runReview(reviewNumber: number, previousReviews: string[], scratch: string | undefined, scope: string) {
				const message = [
					`Spec: ${specPath}`,
					scratch ? `Scratch: ${scratch}` : undefined,
					previousReviews.length > 0 ? `Previous reviews:\n${previousReviews.join("\n")}` : undefined,
					params.focus ? `Focus: ${params.focus}` : undefined,
					scope,
				]
					.filter((line) => line !== undefined)
					.join("\n\n");
				const transcript = { file: path.join(featureDir, `review-${reviewNumber}.jsonl`), fromLine: 0 };
				const result = await runChild(
					{ ...ROLE_CONFIG.reviewer, sessionFile: transcript.file },
					message,
					ctx.cwd,
					signal,
					progressReporter("reviewer", params.feature, transcript, onUpdate),
				);
				if (isFailed(result)) {
					return {
						content: [{ type: "text", text: failureText("reviewer", result) }],
						details: makeDetails("reviewer", params.feature, result, transcript),
						usage: result.usage,
						isError: true,
					};
				}
				if (!result.finalText.trim()) {
					return {
						content: [{ type: "text", text: `The reviewer returned no verdict.\n\n${formatUsage(result)}` }],
						details: makeDetails("reviewer", params.feature, result, transcript),
						usage: result.usage,
						isError: true,
					};
				}
				const reviewPath = path.join(featureDir, `review-${reviewNumber}.md`);
				fs.writeFileSync(reviewPath, `${result.finalText.trim()}\n`, { encoding: "utf-8", flag: "wx" });
				return {
					content: [{ type: "text", text: `${result.finalText}\n\n${formatUsage(result)}\nreview: ${reviewPath}` }],
					details: makeDetails("reviewer", params.feature, result, transcript, reviewPath),
					usage: result.usage,
				};
			}
		},

		renderCall(args, theme) {
			return callView("reviewer", args.feature, args.focus, theme);
		},

		renderResult(result, options, theme, context) {
			return resultView(result, options, theme, context.state);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		restoreFromBranch(pi, ctx);
		await refreshStatus(pi, ctx);
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName === "worker" || event.toolName === "reviewer") {
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
		description: "Approve the current spec or fix pass so the worker can run once; text after it goes to the agent",
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
			pi.sendUserMessage(`Approved: dispatch the worker for ${feature}.${notes ? `\n\n${notes}` : ""}`);
		},
	});
}
