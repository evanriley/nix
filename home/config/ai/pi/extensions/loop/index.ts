import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentToolResult } from "@earendil-works/pi-agent-core";
import type { Message, Usage } from "@earendil-works/pi-ai";
import { type ExtensionAPI, getAgentDir, getMarkdownTheme, keyHint, type Theme } from "@earendil-works/pi-coding-agent";
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

async function projectPlansDir(pi: ExtensionAPI, cwd: string): Promise<string> {
	const gitRoot = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd }).catch(() => undefined);
	const projectRoot = gitRoot?.code === 0 && gitRoot.stdout.trim() ? gitRoot.stdout.trim() : cwd;
	return path.join(PLANS_DIR, sessionSlug(projectRoot));
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

function consumeApproval(featureDir: string, specPath: string): void {
	const approvalPath = path.join(featureDir, "approved");
	if (!fs.existsSync(approvalPath)) {
		throw new Error("Not approved: ask the user to run /approve.");
	}
	if (fs.readFileSync(approvalPath, "utf-8").trim() !== hashFile(specPath)) {
		throw new Error("spec.md changed after approval: ask the user to run /approve again.");
	}
	fs.unlinkSync(approvalPath);
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
	const numbers = fs
		.readdirSync(featureDir)
		.map((name) => /^review-(\d+)\.(md|jsonl)$/.exec(name)?.[1])
		.filter((match): match is string => match !== undefined)
		.map(Number);
	return numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
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

async function withLock<T>(role: Role, run: () => Promise<T>): Promise<T> {
	if (runningRole) {
		throw new Error(`The ${runningRole} is already running; wait for it to finish before dispatching the ${role}.`);
	}
	runningRole = role;
	try {
		return await run();
	} finally {
		runningRole = undefined;
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

			return withLock("worker", async () => {
				consumeApproval(featureDir, specPath);
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
							text: `${result.finalText || "(no output)"}\n\n${formatUsage(result)}\nsession: ${sessionFile}`,
						},
					],
					details,
					usage: result.usage,
				};
			});
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

			return withLock("reviewer", async () => {
				const message = [
					`Spec: ${specPath}`,
					params.focus ? `Focus: ${params.focus}` : undefined,
					"Review the uncommitted changes in this repository against the spec: run `git status`, `git diff` and `git diff --cached`, and read every untracked file.",
				]
					.filter((line) => line !== undefined)
					.join("\n\n");
				const reviewNumber = nextReviewNumber(featureDir);
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
			});
		},

		renderCall(args, theme) {
			return callView("reviewer", args.feature, args.focus, theme);
		},

		renderResult(result, options, theme, context) {
			return resultView(result, options, theme, context.state);
		},
	});

	pi.on("session_start", (event) => {
		if (event.reason !== "reload") lastTouchedFeature = undefined;
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName === "worker" || event.toolName === "reviewer") {
			const feature = event.input.feature;
			if (typeof feature === "string" && FEATURE_PATTERN.test(feature)) lastTouchedFeature = feature;
		} else if (event.toolName === "write" || event.toolName === "edit") {
			const filePath = event.input.path;
			if (typeof filePath !== "string") return undefined;
			const feature = await featureOfSpecPath(pi, ctx.cwd, filePath);
			if (feature) lastTouchedFeature = feature;
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
			const specHash = hashFile(path.join(featureDir, "spec.md"));
			fs.writeFileSync(path.join(featureDir, "approved"), `${specHash}\n`, "utf-8");
			ctx.ui.notify(`Approved ${feature}`, "info");
			const notes = args.trim();
			pi.sendUserMessage(`Approved: dispatch the worker for ${feature}.${notes ? `\n\n${notes}` : ""}`);
		},
	});
}
