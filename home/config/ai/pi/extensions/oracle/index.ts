import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { Message } from "@earendil-works/pi-ai";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const EXTENSION_DIR = path.dirname(fileURLToPath(import.meta.url));
const ORACLE_DIR = path.join(os.homedir(), ".pi", "oracle");
const THREAD_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
const MODEL = "openrouter/tencent/hy4-preview";
const THINKING = "high";
const TOOLS = ["read", "grep", "find", "ls", "bash", "mcp__kagi__kagi_search_fetch"];
const MAX_TURNS = 100;
const MAX_MINUTES = 30;
const MAX_COST = 2;
const KILL_GRACE_MS = 5000;

interface OracleRun {
	exitCode: number;
	finalText: string;
	stderr: string;
	turns: number;
	toolCalls: number;
	cost: number;
	stopReason?: string;
	errorMessage?: string;
	limit?: string;
}

let oracleRunning = false;

function projectSlug(directory: string): string {
	return `--${path
		.resolve(directory)
		.replace(/^[/\\]/, "")
		.replace(/[/\\:]/g, "-")}--`;
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	if (currentScript && !currentScript.startsWith("/$bunfs/root/") && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}
	const execName = path.basename(process.execPath).toLowerCase();
	return /^(node|bun)(\.exe)?$/.test(execName)
		? { command: "pi", args }
		: { command: process.execPath, args };
}

function childArgs(sessionFile: string | undefined, question: string): string[] {
	return [
		"--mode",
		"json",
		"-p",
		...(sessionFile ? ["--session", sessionFile] : ["--no-session"]),
		"--model",
		MODEL,
		"--thinking",
		THINKING,
		"--tools",
		TOOLS.join(","),
		"--no-extensions",
		"--extension",
		path.join(getAgentDir(), "extensions", "guard", "index.ts"),
		"--extension",
		"builtin:mcp",
		"--no-prompt-templates",
		"--append-system-prompt",
		path.join(EXTENSION_DIR, "oracle.md"),
		"--",
		question,
	];
}

function assistantText(message: Message): string | undefined {
	if (message.role !== "assistant") return undefined;
	const texts = message.content.filter((part) => part.type === "text").map((part) => part.text);
	return texts.length > 0 ? texts.join("\n") : undefined;
}

function runOracle(
	sessionFile: string | undefined,
	question: string,
	cwd: string,
	signal: AbortSignal | undefined,
	onProgress: (run: OracleRun) => void,
): Promise<OracleRun> {
	const run: OracleRun = { exitCode: 0, finalText: "", stderr: "", turns: 0, toolCalls: 0, cost: 0 };
	const invocation = getPiInvocation(childArgs(sessionFile, question));
	const environment: NodeJS.ProcessEnv = { ...process.env, PI_LOOP_ROLE: "oracle" };
	delete environment.PI_LOOP_SCRATCH;

	return new Promise((resolve) => {
		const child = spawn(invocation.command, invocation.args, {
			cwd,
			env: environment,
			shell: false,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let buffer = "";

		const stop = () => {
			child.kill("SIGTERM");
			setTimeout(() => {
				if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
			}, KILL_GRACE_MS);
		};
		const stopAtLimit = (limit: string) => {
			run.limit = limit;
			stop();
		};
		const limitTimer = setTimeout(() => stopAtLimit(`${MAX_MINUTES} min`), MAX_MINUTES * 60_000);

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
			run.turns++;
			run.toolCalls += assistant.content.filter((part) => part.type === "toolCall").length;
			run.cost += assistant.usage?.cost?.total || 0;
			run.finalText = assistantText(assistant) ?? run.finalText;
			if (assistant.stopReason) run.stopReason = assistant.stopReason;
			if (assistant.errorMessage) run.errorMessage = assistant.errorMessage;
			if (!run.limit && run.turns >= MAX_TURNS) stopAtLimit(`${MAX_TURNS} turns`);
			else if (!run.limit && run.cost >= MAX_COST) stopAtLimit(`$${MAX_COST.toFixed(2)}`);
			onProgress(run);
		};

		child.stdout.on("data", (data) => {
			buffer += data.toString();
			const lines = buffer.split("\n");
			buffer = lines.pop() ?? "";
			for (const line of lines) processLine(line);
		});
		child.stderr.on("data", (data) => {
			run.stderr += data.toString();
		});
		child.on("close", (code) => {
			clearTimeout(limitTimer);
			signal?.removeEventListener("abort", stop);
			if (buffer.trim()) processLine(buffer);
			run.exitCode = code ?? 1;
			resolve(run);
		});
		child.on("error", (error) => {
			clearTimeout(limitTimer);
			run.stderr += error.message;
			run.exitCode = 1;
			resolve(run);
		});

		if (signal?.aborted) stop();
		else signal?.addEventListener("abort", stop, { once: true });
	});
}

function failure(run: OracleRun): string | undefined {
	if (run.limit) return `The oracle stopped at its limit (${run.limit}).`;
	if (run.exitCode === 0 && run.stopReason !== "error" && run.stopReason !== "aborted" && run.finalText.trim()) {
		return undefined;
	}
	const reason = run.errorMessage || run.stderr.trim() || run.finalText || "(no output)";
	return `The oracle failed (exit ${run.exitCode}, stop reason ${run.stopReason ?? "none"}): ${reason}`;
}

async function threadFile(pi: ExtensionAPI, cwd: string, thread: string | undefined): Promise<string | undefined> {
	if (thread === undefined) return undefined;
	if (!THREAD_PATTERN.test(thread)) {
		throw new Error(
			`Invalid thread "${thread}"; expected a kebab-case slug matching ${THREAD_PATTERN.source}, such as "add-retry-backoff".`,
		);
	}
	const gitRoot = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd }).catch(() => undefined);
	const root = gitRoot?.code === 0 && gitRoot.stdout.trim() ? gitRoot.stdout.trim() : cwd;
	const directory = path.join(ORACLE_DIR, projectSlug(root));
	fs.mkdirSync(directory, { recursive: true });
	return path.join(directory, `${thread}.jsonl`);
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "oracle",
		label: "Oracle",
		description: [
			"Consult the oracle, Tencent Hy4 preview at high reasoning effort, for complex reasoning on code: approach design, architecture calls, hard failure diagnosis and review of risky diffs.",
			"It reads the repository and the web but changes nothing, and returns a recommendation with file:line references, risks and what would change its answer.",
			"Consult it without asking when critical, weakly-verifiable work (concurrency, data loss, security, boot) needs its spec, when a root cause is still unknown after narrowing it, when task is blocked on Checks or review after its fix passes, or when a long-lived decision (schema, on-disk or wire format, public API) has two viable options you cannot choose between; otherwise only when the user asks. One call runs at a time.",
			"Give the question as a self-contained brief: the problem, the relevant paths, what is already known or tried, and the decision wanted.",
			"Pass the same `thread` slug on later calls to resume that conversation; use one thread per feature.",
		].join(" "),
		parameters: Type.Object({
			question: Type.String({ description: "Self-contained brief for the oracle" }),
			thread: Type.Optional(
				Type.String({
					description: "Kebab-case slug; calls with the same slug in this project resume one conversation. Omit for a one-off consultation.",
				}),
			),
		}),

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			if (oracleRunning) throw new Error("An oracle is already running; wait for it to finish before consulting another.");
			oracleRunning = true;
			try {
				const sessionFile = await threadFile(pi, ctx.cwd, params.thread);
				const run = await runOracle(sessionFile, params.question, ctx.cwd, signal, (progress) =>
					onUpdate?.({
						content: [
							{
								type: "text",
								text: `oracle running: ${progress.turns} turns, ${progress.toolCalls} tool calls`,
							},
						],
						details: undefined,
					}),
				);
				const problem = failure(run);
				if (problem) throw new Error(problem);
				const footer = `oracle: ${run.turns} turns, $${run.cost.toFixed(2)}${params.thread ? `, thread ${params.thread}` : ""}`;
				return {
					content: [{ type: "text", text: `${run.finalText.trim()}\n\n${footer}` }],
					details: undefined,
				};
			} finally {
				oracleRunning = false;
			}
		},
	});
}
