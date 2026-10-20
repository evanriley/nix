import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { after, test } from "node:test";
import {
	commitMessage,
	commitTask,
	featureCost,
	findTask,
	parseChecks,
	parseCommitMessage,
	parseTasks,
	parseVerdict,
	runChecks,
	stageChanges,
	trackedChanges,
	untrackedPaths,
	withoutPaths,
} from "./pipeline.ts";

const SPEC = [
	"# Feature",
	"",
	"## Tasks",
	"",
	"### Task 1: feat(loop): add the parser",
	"Owns `loop/pipeline.ts`.",
	"",
	"```sh",
	"## not a heading",
	"```",
	"",
	"### Task 2: fix(loop): handle empty input",
	"Owns `loop/index.ts`.",
	"",
	"## Checks",
	"",
	"Run these:",
	"",
	"```sh",
	"# comment",
	"node --test pipeline.test.ts",
	"",
	"  nix fmt  ",
	"```",
	"",
	"```sh",
	"echo second block",
	"```",
	"",
	"## Notes",
	"### Task 3: chore: not in tasks",
].join("\n");

const tempDirs: string[] = [];

after(() => {
	for (const directory of tempDirs) fs.rmSync(directory, { recursive: true, force: true });
});

function tempDir(prefix: string): string {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
	tempDirs.push(directory);
	return directory;
}

function git(repoRoot: string, ...args: string[]): string {
	const result = spawnSync("git", args, { cwd: repoRoot, encoding: "utf-8" });
	assert.equal(result.status, 0, `git ${args.join(" ")}: ${result.stderr}`);
	return result.stdout;
}

function makeRepo(): string {
	const repoRoot = tempDir("pipeline-repo-");
	git(repoRoot, "init", "-q", "-b", "main");
	git(repoRoot, "config", "user.name", "Test");
	git(repoRoot, "config", "user.email", "test@example.com");
	git(repoRoot, "config", "commit.gpgsign", "false");
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "one\n");
	fs.writeFileSync(path.join(repoRoot, ".gitignore"), "ignored.txt\n");
	git(repoRoot, "add", "-A");
	git(repoRoot, "commit", "-q", "-m", "initial");
	return repoRoot;
}

function stagedPaths(repoRoot: string): string[] {
	return git(repoRoot, "diff", "--cached", "--name-only").split("\n").filter(Boolean);
}

test("parseTasks_specWithTasks_returnsEachTaskInOrder", () => {
	const tasks = parseTasks(SPEC);
	assert.deepEqual(
		tasks.map((task) => [task.number, task.subject]),
		[
			[1, "feat(loop): add the parser"],
			[2, "fix(loop): handle empty input"],
		],
	);
	assert.match(tasks[0].body, /## not a heading/);
});

test("findTask_missingNumber_returnsUndefined", () => {
	assert.equal(findTask(SPEC, 2)?.subject, "fix(loop): handle empty input");
	assert.equal(findTask(SPEC, 3), undefined);
});

test("parseTasks_noTasksSection_returnsEmpty", () => {
	assert.deepEqual(parseTasks("# Feature\n\n### Task 1: feat: x\n"), []);
});

test("parseChecks_firstFencedBlock_skipsBlankAndCommentLines", () => {
	assert.deepEqual(parseChecks(SPEC), ["node --test pipeline.test.ts", "nix fmt"]);
});

test("parseChecks_noChecksSection_returnsEmpty", () => {
	assert.deepEqual(parseChecks("## Tasks\n\n### Task 1: feat: x\n"), []);
});

test("parseChecks_sectionWithoutBlock_returnsEmpty", () => {
	assert.deepEqual(parseChecks("## Checks\n\nnone yet\n\n## Notes\n```sh\nmake\n```\n"), []);
});

const REVIEW_PASS = [
	"## Matches the spec",
	"All addressed.",
	"",
	"## Findings",
	"- [non-blocking] `a.ts:3` rename `x` to `count`",
	"  for clarity.",
	"",
	"Verdict: pass",
].join("\n");

test("parseVerdict_passWithoutBlocking_passes", () => {
	const verdict = parseVerdict(REVIEW_PASS);
	assert.ok(verdict.kind === "pass");
	assert.equal(verdict.pass, true);
	assert.deepEqual(verdict.nonBlocking, ["[non-blocking] `a.ts:3` rename `x` to `count`\nfor clarity."]);
	assert.deepEqual(verdict.blocking, []);
});

test("parseVerdict_passWithBlockingItem_doesNotPass", () => {
	const verdict = parseVerdict(
		[
			"## Findings",
			"- [blocking] `a.ts:1` returns null on empty input",
			"- [non-blocking] `b.ts:2` nit",
			"",
			"Verdict: pass",
		].join("\n"),
	);
	assert.ok(verdict.kind === "pass");
	assert.equal(verdict.pass, false);
	assert.deepEqual(verdict.blocking, ["[blocking] `a.ts:1` returns null on empty input"]);
});

test("parseVerdict_changesNeeded_doesNotPass", () => {
	const verdict = parseVerdict(
		["## Findings", "1. [blocking] `a.ts:1` missing test", "", "Verdict: changes needed"].join("\n"),
	);
	assert.ok(verdict.kind === "changes needed");
	assert.equal(verdict.pass, false);
	assert.deepEqual(verdict.blocking, ["[blocking] `a.ts:1` missing test"]);
});

test("parseVerdict_noVerdictLine_returnsMissing", () => {
	assert.deepEqual(parseVerdict("## Findings\n- [blocking] `a.ts:1` broken\n"), { kind: "missing" });
});

test("parseCommitMessage_presentBlock_returnsContents", () => {
	const report = [
		"### Files changed",
		"- `a.ts:1` - x",
		"",
		"### Commit message",
		"```",
		"feat(loop): add the parser",
		"",
		"Explain why.",
		"```",
	].join("\n");
	assert.equal(parseCommitMessage(report), "feat(loop): add the parser\n\nExplain why.");
	assert.equal(commitMessage(report, "fallback"), "feat(loop): add the parser\n\nExplain why.");
});

test("commitMessage_absentOrEmptyBlock_fallsBackToSubject", () => {
	assert.equal(commitMessage("### Files changed\n- x\n", "feat: subject"), "feat: subject");
	assert.equal(commitMessage("### Commit message\n```\n\n```\n", "feat: subject"), "feat: subject");
});

test("trackedChanges_cleanAndDirtyTrees_listsOnlyTrackedPaths", async () => {
	const repoRoot = makeRepo();
	fs.writeFileSync(path.join(repoRoot, "new.txt"), "new\n");
	fs.writeFileSync(path.join(repoRoot, "ignored.txt"), "ignored\n");
	assert.deepEqual(await trackedChanges(repoRoot), []);
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "two\n");
	assert.deepEqual(await trackedChanges(repoRoot), ["tracked.txt"]);
	git(repoRoot, "checkout", "--", "tracked.txt");
	git(repoRoot, "mv", "tracked.txt", "moved.txt");
	assert.deepEqual(await trackedChanges(repoRoot), ["moved.txt"]);
});

test("stageChanges_preexistingUntracked_staysUnstaged", async () => {
	const repoRoot = makeRepo();
	fs.mkdirSync(path.join(repoRoot, "dir"));
	fs.writeFileSync(path.join(repoRoot, "dir", "pre*existing.txt"), "keep out\n");
	fs.writeFileSync(path.join(repoRoot, "ignored.txt"), "ignored\n");
	const preexisting = await untrackedPaths(repoRoot);
	assert.deepEqual(preexisting, ["dir/pre*existing.txt"]);
	fs.writeFileSync(path.join(repoRoot, "dir", "pre-new.txt"), "task file\n");
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "two\n");
	await stageChanges(repoRoot, preexisting);
	assert.deepEqual(stagedPaths(repoRoot), ["dir/pre-new.txt", "tracked.txt"]);
	const outcome = await commitTask(repoRoot, "feat: task", preexisting);
	assert.equal(outcome.kind, "committed");
	assert.deepEqual(await untrackedPaths(repoRoot), ["dir/pre*existing.txt"]);
});

test("withoutPaths_removedSubset_keepsOrderOfTheRest", () => {
	assert.deepEqual(withoutPaths(["a.txt", "b.txt", "c.txt"], ["b.txt", "missing.txt"]), ["a.txt", "c.txt"]);
	assert.deepEqual(withoutPaths([], ["a.txt"]), []);
	assert.deepEqual(withoutPaths(["a.txt"], []), ["a.txt"]);
});

test("stageChanges_blockedRunCreatedFiles_stagesThemOnRerun", async () => {
	const repoRoot = makeRepo();
	fs.writeFileSync(path.join(repoRoot, "before.txt"), "user file\n");
	const firstPreexisting = await untrackedPaths(repoRoot);
	fs.writeFileSync(path.join(repoRoot, "created.txt"), "from blocked run\n");
	const created = withoutPaths(await untrackedPaths(repoRoot), firstPreexisting);
	assert.deepEqual(created, ["created.txt"]);
	const rerunPreexisting = withoutPaths(await untrackedPaths(repoRoot), created);
	await stageChanges(repoRoot, rerunPreexisting);
	assert.deepEqual(stagedPaths(repoRoot), ["created.txt"]);
});

test("commitTask_nothingToCommit_returnsNothing", async () => {
	const repoRoot = makeRepo();
	fs.writeFileSync(path.join(repoRoot, "pre.txt"), "pre\n");
	assert.deepEqual(await commitTask(repoRoot, "feat: task", ["pre.txt"]), { kind: "nothing" });
});

test("commitTask_hookRewritesFileOnce_restagesAndCommits", async () => {
	const repoRoot = makeRepo();
	const hook = path.join(repoRoot, ".git", "hooks", "pre-commit");
	fs.writeFileSync(
		hook,
		[
			"#!/usr/bin/env bash",
			"set -euo pipefail",
			'if grep -q "unformatted" tracked.txt; then',
			"  sed -i 's/unformatted/formatted/' tracked.txt",
			'  echo "reformatted tracked.txt" >&2',
			"  exit 1",
			"fi",
		].join("\n"),
		{ mode: 0o755 },
	);
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "unformatted\n");
	const outcome = await commitTask(repoRoot, "feat: format\n\nBody line.", []);
	assert.equal(outcome.kind, "committed");
	assert.ok(outcome.kind === "committed");
	assert.equal(outcome.sha, git(repoRoot, "rev-parse", "HEAD").trim());
	assert.equal(git(repoRoot, "show", "HEAD:tracked.txt"), "formatted\n");
	assert.equal(git(repoRoot, "log", "-1", "--format=%B").trim(), "feat: format\n\nBody line.");
	assert.deepEqual(await trackedChanges(repoRoot), []);
});

test("commitTask_hookAlwaysFails_returnsFailedWithOutput", async () => {
	const repoRoot = makeRepo();
	const hook = path.join(repoRoot, ".git", "hooks", "pre-commit");
	fs.writeFileSync(hook, '#!/usr/bin/env bash\necho "lint failed" >&2\nexit 1\n', { mode: 0o755 });
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "two\n");
	const head = git(repoRoot, "rev-parse", "HEAD");
	const outcome = await commitTask(repoRoot, "feat: task", []);
	assert.ok(outcome.kind === "failed");
	assert.match(outcome.output, /lint failed/);
	assert.equal(git(repoRoot, "rev-parse", "HEAD"), head);
});

test("commitTask_commitMsgHookFails_unstagesAndKeepsWorktree", async () => {
	const repoRoot = makeRepo();
	const hook = path.join(repoRoot, ".git", "hooks", "commit-msg");
	fs.writeFileSync(hook, '#!/usr/bin/env bash\necho "bad message" >&2\nexit 1\n', { mode: 0o755 });
	fs.writeFileSync(path.join(repoRoot, "tracked.txt"), "two\n");
	fs.writeFileSync(path.join(repoRoot, "new.txt"), "new\n");
	const outcome = await commitTask(repoRoot, "feat: task", []);
	assert.ok(outcome.kind === "failed");
	assert.match(outcome.output, /bad message/);
	assert.equal(spawnSync("git", ["diff", "--cached", "--quiet"], { cwd: repoRoot }).status, 0);
	assert.equal(fs.readFileSync(path.join(repoRoot, "tracked.txt"), "utf-8"), "two\n");
	assert.equal(fs.readFileSync(path.join(repoRoot, "new.txt"), "utf-8"), "new\n");
	assert.deepEqual(await untrackedPaths(repoRoot), ["new.txt"]);
});

test("runChecks_failingCommand_stopsAndReportsTail", async () => {
	const repoRoot = makeRepo();
	const logPath = path.join(tempDir("pipeline-log-"), "checks-1.log");
	const run = await runChecks(
		repoRoot,
		["echo first", "echo broken >&2; exit 3", "touch never"],
		60_000,
		logPath,
		undefined,
	);
	assert.deepEqual(run, {
		ok: false,
		command: "echo broken >&2; exit 3",
		exitCode: 3,
		timedOut: false,
		tail: "broken",
	});
	assert.equal(fs.existsSync(path.join(repoRoot, "never")), false);
	assert.match(fs.readFileSync(logPath, "utf-8"), /first[\s\S]*broken/);
});

test("runChecks_slowCommand_timesOut", async () => {
	const repoRoot = makeRepo();
	const logPath = path.join(tempDir("pipeline-log-"), "checks-1.log");
	const run = await runChecks(repoRoot, ["sleep 30"], 200, logPath, undefined);
	assert.ok(!run.ok);
	assert.equal(run.timedOut, true);
});

test("runChecks_passingCommands_returnsOk", async () => {
	const repoRoot = makeRepo();
	const logPath = path.join(tempDir("pipeline-log-"), "checks-1.log");
	assert.deepEqual(await runChecks(repoRoot, ["true", "pwd"], 60_000, logPath, undefined), { ok: true });
	assert.match(fs.readFileSync(logPath, "utf-8"), new RegExp(fs.realpathSync(repoRoot)));
});

test("featureCost_workerAndReviewSessions_sumsAssistantCosts", () => {
	const featureDir = tempDir("pipeline-feature-");
	const assistant = (total: number) =>
		JSON.stringify({ type: "message", message: { role: "assistant", usage: { cost: { total } } } });
	const user = JSON.stringify({ type: "message", message: { role: "user", usage: { cost: { total: 100 } } } });
	fs.writeFileSync(path.join(featureDir, "worker.jsonl"), `${assistant(1.5)}\n${user}\n`);
	fs.writeFileSync(path.join(featureDir, "worker-2.jsonl"), `${assistant(2)}\n`);
	fs.writeFileSync(path.join(featureDir, "review-1.jsonl"), `${assistant(0.5)}\nnot json\n`);
	fs.writeFileSync(path.join(featureDir, "other.jsonl"), `${assistant(50)}\n`);
	assert.equal(featureCost(featureDir), 4);
});
