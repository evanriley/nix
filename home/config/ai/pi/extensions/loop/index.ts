import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentToolResult } from "@earendil-works/pi-agent-core";
import type { Message, Usage } from "@earendil-works/pi-ai";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const EXTENSION_DIR = path.dirname(fileURLToPath(import.meta.url));
const PLANS_DIR = path.join(os.homedir(), ".pi", "plans");
const FEATURE_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

type Role = "worker" | "reviewer";

interface ChildConfig {
	model: string;
	thinking: string;
	tools: string[];
	promptFile: string;
	session: { kind: "persistent"; file: string } | { kind: "none" };
}

const ROLE_CONFIG: Record<Role, Omit<ChildConfig, "session">> = {
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
}

interface LoopDetails {
	role: Role;
	feature: string;
	turns: number;
	toolCalls: number;
	usage: Usage;
	reviewPath?: string;
}

let runningRole: Role | undefined;

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

async function resolveFeatureDir(pi: ExtensionAPI, cwd: string, feature: string): Promise<string> {
	if (!FEATURE_PATTERN.test(feature)) {
		throw new Error(
			`Invalid feature "${feature}"; expected a kebab-case slug matching ${FEATURE_PATTERN.source}, such as "add-login-form".`,
		);
	}
	const gitRoot = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd }).catch(() => undefined);
	const projectRoot = gitRoot?.code === 0 && gitRoot.stdout.trim() ? gitRoot.stdout.trim() : cwd;
	return path.join(PLANS_DIR, sessionSlug(projectRoot), feature);
}

function requireSpec(featureDir: string): string {
	const specPath = path.join(featureDir, "spec.md");
	if (!fs.existsSync(specPath)) {
		throw new Error(`Spec not found at ${specPath}; write the approved spec there before dispatching.`);
	}
	return specPath;
}

function nextReviewPath(featureDir: string): string {
	const numbers = fs
		.readdirSync(featureDir)
		.map((name) => /^review-(\d+)\.md$/.exec(name)?.[1])
		.filter((match): match is string => match !== undefined)
		.map(Number);
	const next = numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
	return path.join(featureDir, `review-${next}.md`);
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
	const sessionArgs = config.session.kind === "persistent" ? ["--session", config.session.file] : ["--no-session"];
	return [
		"--mode",
		"json",
		"-p",
		...sessionArgs,
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

		const processLine = (line: string) => {
			if (!line.trim()) return;
			let event: { type?: string; message?: Message };
			try {
				event = JSON.parse(line);
			} catch {
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
			onProgress(result);
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

function makeDetails(role: Role, feature: string, result: ChildResult, reviewPath?: string): LoopDetails {
	return {
		role,
		feature,
		turns: result.turns,
		toolCalls: result.toolCalls,
		usage: result.usage,
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

function progressReporter(role: Role, feature: string, onUpdate: OnUpdate): (result: ChildResult) => void {
	return (result) => {
		onUpdate?.({
			content: [
				{
					type: "text",
					text: `${role} running: ${result.turns} turns, ${result.toolCalls} tool calls\n${result.finalText}`,
				},
			],
			details: makeDetails(role, feature, result),
		});
	};
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
			"The user must approve every dispatch. The worker keeps one session per feature, so later calls are fix passes that see earlier work.",
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
			if (!ctx.hasUI) {
				throw new Error(
					"The worker needs an interactive UI to confirm each dispatch; run pi interactively to dispatch workers.",
				);
			}
			const featureDir = await resolveFeatureDir(pi, ctx.cwd, params.feature);
			const specPath = requireSpec(featureDir);

			return withLock("worker", async () => {
				const approved = await ctx.ui.confirm(
					"Dispatch worker?",
					`Feature: ${params.feature}\nSpec: ${specPath}\n\nTask:\n${params.task}`,
				);
				if (!approved) {
					return {
						content: [
							{
								type: "text",
								text: "Worker dispatch not approved by the user. Stop and ask the user how to proceed.",
							},
						],
						details: undefined,
					};
				}

				const sessionFile = path.join(featureDir, "worker.jsonl");
				const result = await runChild(
					{ ...ROLE_CONFIG.worker, session: { kind: "persistent", file: sessionFile } },
					`Spec: ${specPath}\n\n${params.task}`,
					ctx.cwd,
					signal,
					progressReporter("worker", params.feature, onUpdate),
				);
				const details = makeDetails("worker", params.feature, result);
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
				const result = await runChild(
					{ ...ROLE_CONFIG.reviewer, session: { kind: "none" } },
					message,
					ctx.cwd,
					signal,
					progressReporter("reviewer", params.feature, onUpdate),
				);
				if (isFailed(result)) {
					return {
						content: [{ type: "text", text: failureText("reviewer", result) }],
						details: makeDetails("reviewer", params.feature, result),
						usage: result.usage,
						isError: true,
					};
				}
				if (!result.finalText.trim()) {
					return {
						content: [{ type: "text", text: `The reviewer returned no verdict.\n\n${formatUsage(result)}` }],
						details: makeDetails("reviewer", params.feature, result),
						usage: result.usage,
						isError: true,
					};
				}
				const reviewPath = nextReviewPath(featureDir);
				fs.writeFileSync(reviewPath, `${result.finalText.trim()}\n`, { encoding: "utf-8", flag: "wx" });
				return {
					content: [{ type: "text", text: `${result.finalText}\n\n${formatUsage(result)}\nreview: ${reviewPath}` }],
					details: makeDetails("reviewer", params.feature, result, reviewPath),
					usage: result.usage,
				};
			});
		},
	});
}
