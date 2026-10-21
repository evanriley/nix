import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface SpecTask {
	number: number;
	subject: string;
	body: string;
}

interface Finding {
	severity: "blocking" | "non-blocking";
	text: string;
}

export type Verdict =
	| { kind: "missing" }
	| { kind: "pass" | "changes needed"; pass: boolean; blocking: string[]; nonBlocking: string[] };

export type CheckRun =
	| { ok: true }
	| { ok: false; command: string; exitCode?: number; timedOut: boolean; tail: string };

export type CommitOutcome =
	| { kind: "committed"; sha: string }
	| { kind: "nothing" }
	| { kind: "failed"; output: string };

export interface TaskRecord {
	task: number;
	subject: string;
	status: "committed" | "blocked";
	stage?: string;
	sha?: string;
	workers: string[];
	reviews: string[];
	checks: string[];
	nonBlocking: string[];
	created?: string[];
	cost: number;
}

interface ProcessResult {
	code: number;
	stdout: string;
	stderr: string;
}

const LIST_ITEM = /^ {0,1}(?:[-*+]|\d+[.)])\s+(.*)$/;
const VERDICT_LINE = /^\s*[*_`]*Verdict:[*_`]*\s*(.*?)\s*$/i;
const SEVERITY_TAG = /^[*_`]*\[(blocking|non-blocking)\]/i;
const FENCE = /^\s{0,3}(`{3,}|~{3,})/;

function sectionLines(markdown: string, heading: string): string[] | undefined {
	const lines = markdown.split("\n");
	let fence: string | undefined;
	let start: number | undefined;
	for (let index = 0; index < lines.length; index++) {
		const line = lines[index];
		const fenceMatch = FENCE.exec(line);
		if (fenceMatch) {
			if (!fence) fence = fenceMatch[1];
			else if (line.trim().startsWith(fence) && /^[`~]+$/.test(line.trim())) fence = undefined;
			continue;
		}
		if (fence || !/^## /.test(line)) continue;
		if (start !== undefined) return lines.slice(start, index);
		if (line.slice(3).trim().toLowerCase() === heading.toLowerCase()) start = index + 1;
	}
	return start === undefined ? undefined : lines.slice(start);
}

function firstFencedBlock(lines: string[]): string[] | undefined {
	let fence: string | undefined;
	const content: string[] = [];
	for (const line of lines) {
		if (!fence) {
			const fenceMatch = FENCE.exec(line);
			if (fenceMatch) fence = fenceMatch[1];
			continue;
		}
		if (line.trim().startsWith(fence) && /^[`~]+$/.test(line.trim())) return content;
		content.push(line);
	}
	return fence ? content : undefined;
}

export function parseTasks(spec: string): SpecTask[] {
	const lines = sectionLines(spec, "Tasks");
	if (!lines) return [];
	const tasks: SpecTask[] = [];
	let current: { number: number; subject: string; body: string[] } | undefined;
	const finish = () => {
		if (current) tasks.push({ number: current.number, subject: current.subject, body: current.body.join("\n").trim() });
	};
	for (const line of lines) {
		const heading = /^### Task (\d+):\s*(.*?)\s*$/.exec(line);
		if (heading) {
			finish();
			current = { number: Number(heading[1]), subject: heading[2], body: [] };
		} else if (current) {
			current.body.push(line);
		}
	}
	finish();
	return tasks;
}

export function findTask(spec: string, number: number): SpecTask | undefined {
	return parseTasks(spec).find((task) => task.number === number && task.subject.length > 0);
}

export function parseChecks(spec: string): string[] {
	const lines = sectionLines(spec, "Checks");
	if (!lines) return [];
	return (firstFencedBlock(lines) ?? [])
		.map((line) => line.trim())
		.filter((line) => line.length > 0 && !line.startsWith("#"));
}

function parseFindings(review: string): Finding[] {
	const lines = sectionLines(review, "Findings") ?? [];
	const items: string[][] = [];
	let current: string[] | undefined;
	for (const line of lines) {
		const item = LIST_ITEM.exec(line);
		if (item) {
			current = [item[1]];
			items.push(current);
		} else if (current && /^\s+\S/.test(line) && !VERDICT_LINE.test(line)) {
			current.push(line.trim());
		} else if (line.trim().length > 0) {
			current = undefined;
		}
	}
	return items.map((itemLines) => {
		const text = itemLines.join("\n");
		const tag = SEVERITY_TAG.exec(text);
		return { severity: tag?.[1].toLowerCase() === "blocking" ? "blocking" : "non-blocking", text };
	});
}

export function parseVerdict(review: string): Verdict {
	const verdictLine = review
		.split("\n")
		.map((line) => VERDICT_LINE.exec(line))
		.filter((match) => match !== null)
		.at(-1);
	const value = verdictLine?.[1]
		.replace(/[*_`.]/g, "")
		.trim()
		.toLowerCase();
	if (value !== "pass" && value !== "changes needed") return { kind: "missing" };
	const findings = parseFindings(review);
	const blocking = findings.filter((finding) => finding.severity === "blocking").map((finding) => finding.text);
	const nonBlocking = findings.filter((finding) => finding.severity === "non-blocking").map((finding) => finding.text);
	return { kind: value, pass: value === "pass" && blocking.length === 0, blocking, nonBlocking };
}

export function parseCommitMessage(report: string): string | undefined {
	const lines = report.split("\n");
	const headingIndex = lines.findLastIndex((line) => /^###\s+Commit message\s*$/i.test(line));
	if (headingIndex === -1) return undefined;
	const following = lines.slice(headingIndex + 1);
	const nextHeading = following.findIndex((line) => /^#{1,3}\s/.test(line));
	const block = firstFencedBlock(nextHeading === -1 ? following : following.slice(0, nextHeading));
	const message = block?.join("\n").trim();
	return message ? message : undefined;
}

export function commitMessage(report: string, subject: string): string {
	return parseCommitMessage(report) ?? subject;
}

export function tailLines(text: string, count: number): string {
	const lines = text.replace(/\s+$/, "").split("\n");
	return lines.slice(-count).join("\n");
}

function runProcess(
	command: string,
	args: string[],
	cwd: string,
	options: { input?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<ProcessResult> {
	return new Promise((resolve, reject) => {
		const child = spawn(command, args, {
			cwd,
			env: options.env ?? process.env,
			shell: false,
			stdio: ["pipe", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		child.stdout.on("data", (data: Buffer) => {
			stdout += data.toString();
		});
		child.stderr.on("data", (data: Buffer) => {
			stderr += data.toString();
		});
		child.on("error", reject);
		child.on("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
		child.stdin.end(options.input);
	});
}

async function git(repoRoot: string, args: string[], options: { input?: string; env?: NodeJS.ProcessEnv } = {}) {
	return runProcess("git", args, repoRoot, options);
}

async function gitChecked(repoRoot: string, args: string[], options: { input?: string; env?: NodeJS.ProcessEnv } = {}) {
	const result = await git(repoRoot, args, options);
	if (result.code !== 0) throw new Error(`git ${args.join(" ")} failed (exit ${result.code}): ${result.stderr.trim()}`);
	return result.stdout;
}

function nulSeparated(output: string): string[] {
	return output.split("\0").filter((entry) => entry.length > 0);
}

export function withoutPaths(paths: string[], removed: string[]): string[] {
	const removedSet = new Set(removed);
	return paths.filter((filePath) => !removedSet.has(filePath));
}

export async function trackedChanges(repoRoot: string): Promise<string[]> {
	const entries = nulSeparated(await gitChecked(repoRoot, ["status", "--porcelain=v1", "-z"]));
	const paths: string[] = [];
	for (let index = 0; index < entries.length; index++) {
		const entry = entries[index];
		const status = entry.slice(0, 2);
		if (status === "??" || status === "!!") continue;
		paths.push(entry.slice(3));
		if (status[0] === "R" || status[0] === "C") index++;
	}
	return paths;
}

export async function untrackedPaths(repoRoot: string): Promise<string[]> {
	return nulSeparated(await gitChecked(repoRoot, ["ls-files", "--others", "--exclude-standard", "-z"]));
}

export async function stageChanges(repoRoot: string, excluded: string[]): Promise<void> {
	await gitChecked(repoRoot, ["add", "-A"]);
	if (excluded.length === 0) return;
	await gitChecked(repoRoot, ["reset", "-q", "--pathspec-from-file=-", "--pathspec-file-nul"], {
		input: `${excluded.join("\0")}\0`,
		env: { ...process.env, GIT_LITERAL_PATHSPECS: "1" },
	});
}

async function hasStagedChanges(repoRoot: string): Promise<boolean> {
	const result = await git(repoRoot, ["diff", "--cached", "--quiet"]);
	if (result.code > 1)
		throw new Error(`git diff --cached --quiet failed (exit ${result.code}): ${result.stderr.trim()}`);
	return result.code === 1;
}

async function hasUnstagedChanges(repoRoot: string): Promise<boolean> {
	const result = await git(repoRoot, ["diff", "--quiet"]);
	if (result.code > 1) throw new Error(`git diff --quiet failed (exit ${result.code}): ${result.stderr.trim()}`);
	return result.code === 1;
}

export async function commitTask(repoRoot: string, message: string, excluded: string[]): Promise<CommitOutcome> {
	await stageChanges(repoRoot, excluded);
	if (!(await hasStagedChanges(repoRoot))) return { kind: "nothing" };
	const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-commit-"));
	try {
		const messageFile = path.join(tempDir, "message");
		fs.writeFileSync(messageFile, `${message.trim()}\n`, "utf-8");
		let result = await git(repoRoot, ["commit", "-F", messageFile]);
		if (result.code !== 0 && (await hasUnstagedChanges(repoRoot))) {
			await stageChanges(repoRoot, excluded);
			result = await git(repoRoot, ["commit", "-F", messageFile]);
		}
		if (result.code !== 0) {
			await gitChecked(repoRoot, ["reset", "-q"]);
			return { kind: "failed", output: `${result.stdout}${result.stderr}`.trim() };
		}
		return { kind: "committed", sha: (await gitChecked(repoRoot, ["rev-parse", "HEAD"])).trim() };
	} finally {
		fs.rmSync(tempDir, { recursive: true, force: true });
	}
}

function runCheck(
	repoRoot: string,
	command: string,
	timeoutMs: number,
	logPath: string,
	signal: AbortSignal | undefined,
): Promise<{ exitCode?: number; timedOut: boolean; output: string }> {
	return new Promise((resolve) => {
		fs.appendFileSync(logPath, `$ ${command}\n`);
		const child = spawn("bash", ["-c", command], {
			cwd: repoRoot,
			env: process.env,
			detached: true,
			stdio: ["ignore", "pipe", "pipe"],
		});
		let output = "";
		let timedOut = false;
		let finished = false;
		const append = (data: Buffer) => {
			const text = data.toString();
			fs.appendFileSync(logPath, text);
			output = (output + text).slice(-1_000_000);
		};
		child.stdout.on("data", append);
		child.stderr.on("data", append);
		const kill = () => {
			try {
				if (child.pid !== undefined) process.kill(-child.pid, "SIGKILL");
			} catch {}
		};
		const timer = setTimeout(() => {
			timedOut = true;
			kill();
		}, timeoutMs);
		signal?.addEventListener("abort", kill, { once: true });
		const finish = (exitCode: number | undefined, extra = "") => {
			if (finished) return;
			finished = true;
			clearTimeout(timer);
			signal?.removeEventListener("abort", kill);
			output += extra;
			const status = timedOut ? `timed out after ${timeoutMs / 60_000} min` : `exit ${exitCode ?? "signal"}`;
			fs.appendFileSync(logPath, `${extra}\n[${status}]\n\n`);
			resolve({ exitCode, timedOut, output });
		};
		child.on("error", (error) => finish(undefined, error.message));
		child.on("close", (code) => finish(code ?? undefined));
		if (signal?.aborted) kill();
	});
}

export async function runChecks(
	repoRoot: string,
	commands: string[],
	timeoutMs: number,
	logPath: string,
	signal: AbortSignal | undefined,
	onCommand: (command: string) => void = () => {},
): Promise<CheckRun> {
	fs.writeFileSync(logPath, "", { encoding: "utf-8", flag: "wx" });
	for (const command of commands) {
		onCommand(command);
		const result = await runCheck(repoRoot, command, timeoutMs, logPath, signal);
		if (result.timedOut || result.exitCode !== 0) {
			return {
				ok: false,
				command,
				exitCode: result.exitCode,
				timedOut: result.timedOut,
				tail: tailLines(result.output, 150),
			};
		}
	}
	return { ok: true };
}

function assistantCosts(file: string): number {
	let total = 0;
	for (const line of fs.readFileSync(file, "utf-8").split("\n")) {
		if (!line.includes('"usage"')) continue;
		try {
			const entry = JSON.parse(line);
			const cost = entry?.message?.role === "assistant" ? entry.message.usage?.cost?.total : undefined;
			if (typeof cost === "number") total += cost;
		} catch {}
	}
	return total;
}

export function featureCost(featureDir: string): number {
	if (!fs.existsSync(featureDir)) return 0;
	return fs
		.readdirSync(featureDir)
		.filter((name) => /^worker(?:-\d+)?\.jsonl$/.test(name) || /^review-\d+\.jsonl$/.test(name))
		.reduce((total, name) => total + assistantCosts(path.join(featureDir, name)), 0);
}

export function nextNumber(featureDir: string, pattern: RegExp): number {
	if (!fs.existsSync(featureDir)) return 1;
	const numbers = fs
		.readdirSync(featureDir)
		.map((name) => pattern.exec(name)?.[1])
		.filter((match): match is string => match !== undefined)
		.map(Number);
	return numbers.length > 0 ? Math.max(...numbers) + 1 : 1;
}

export function reviewNumbers(featureDir: string, pattern: RegExp): number[] {
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

export function workerSessionNumbers(featureDir: string): number[] {
	const numbers = reviewNumbers(featureDir, /^worker(?:-(\d+))?\.jsonl$/);
	return fs.existsSync(path.join(featureDir, "worker.jsonl")) ? [0, ...numbers] : numbers;
}

export function workerSessionPath(featureDir: string, number: number): string {
	return path.join(featureDir, number === 0 ? "worker.jsonl" : `worker-${number}.jsonl`);
}

export function lastContextTokens(file: string): number {
	if (!fs.existsSync(file)) return 0;
	let tokens = 0;
	for (const line of fs.readFileSync(file, "utf-8").split("\n")) {
		if (!line.includes('"usage"')) continue;
		try {
			const entry = JSON.parse(line);
			const usage = entry?.message?.role === "assistant" ? entry.message.usage : undefined;
			if (usage) tokens = (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheWrite ?? 0);
		} catch {}
	}
	return tokens;
}

export interface WorkerSession {
	file: string;
	resumed: boolean;
	notice?: string;
}

export function chooseWorkerSession(featureDir: string, resume: boolean, maxResumeTokens: number): WorkerSession {
	const newest = workerSessionNumbers(featureDir).at(-1);
	const fresh = workerSessionPath(featureDir, (newest ?? 0) + 1);
	const freshName = path.basename(fresh, ".jsonl");
	if (!resume) return { file: fresh, resumed: false };
	if (newest === undefined) {
		return { file: fresh, resumed: false, notice: `nothing to resume; started ${freshName}` };
	}
	const newestFile = workerSessionPath(featureDir, newest);
	const tokens = lastContextTokens(newestFile);
	if (tokens > maxResumeTokens) {
		return {
			file: fresh,
			resumed: false,
			notice: `resume refused: previous session at ${Math.round(tokens / 1000)}k tokens; started ${freshName}`,
		};
	}
	return { file: newestFile, resumed: true };
}

export function taskRecordPath(featureDir: string, task: number): string {
	return path.join(featureDir, `task-${task}.json`);
}

export function readTaskRecord(featureDir: string, task: number): TaskRecord | undefined {
	const recordPath = taskRecordPath(featureDir, task);
	if (!fs.existsSync(recordPath)) return undefined;
	try {
		const record = JSON.parse(fs.readFileSync(recordPath, "utf-8"));
		return Array.isArray(record?.reviews) ? record : undefined;
	} catch {
		return undefined;
	}
}

export function writeTaskRecord(featureDir: string, record: TaskRecord): void {
	fs.writeFileSync(taskRecordPath(featureDir, record.task), `${JSON.stringify(record, null, "\t")}\n`, "utf-8");
}

export function parseContextCap(value: string | undefined, fallback: number): number {
	const trimmed = value?.trim() ?? "";
	if (!/^[1-9]\d*$/.test(trimmed)) return fallback;
	const cap = Number(trimmed);
	return Number.isSafeInteger(cap) ? cap : fallback;
}

export interface ContextCapState {
	warned: boolean;
	aborted: boolean;
}

export function contextCapStep(
	tokens: number,
	cap: number,
	hardMargin: number,
	state: ContextCapState,
): { warn: boolean; abort: boolean } {
	const abort = !state.aborted && tokens >= cap + hardMargin;
	const warn = !abort && !state.warned && tokens >= cap;
	return { warn, abort };
}
