export type Role = "main" | "worker" | "reviewer" | "oracle";
export type Action = "allow" | "confirm" | "block";

export interface Decision {
	action: Action;
	reason?: string;
}

export interface ClassifyOptions {
	home: string;
	scratch?: string;
	cwd?: string;
}

type Severity = "secret" | "risky" | "childOnly";

interface Finding {
	severity: Severity;
	reason: string;
	scratchExempt: boolean;
}

const MAX_NESTING = 8;
const SHELLS = new Set(["bash", "sh", "zsh", "fish", "dash", "ksh"]);
const KEYWORDS = new Set(["{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until"]);
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
const PATH_TOKEN_END = "[^\\s'\"`;|&<>()]*";
const PATH_METACHARACTERS = /[*?[{`$]/;
const FIND_VALUE_GLOBALS = new Set(["-maxdepth", "-mindepth"]);
const DOTENV_TEMPLATES = new Set([".env.example", ".env.sample", ".env.template"]);
const PATH_TOOLS = new Set(["read", "grep", "find", "ls", "edit", "write"]);

function finding(severity: Severity, reason: string, scratchExempt = false): Finding {
	return { severity, reason, scratchExempt };
}

const secret = (reason: string) => finding("secret", reason);
const risky = (reason: string, scratchExempt = false) => finding("risky", reason, scratchExempt);
const childOnly = (reason: string, scratchExempt = false) => finding("childOnly", reason, scratchExempt);

interface Token {
	kind: "word" | "separator" | "redirect";
	text: string;
	substituted?: boolean;
}

interface Lexed {
	commands: string[][];
	redirectTargets: string[][];
	substitutedCommands: boolean[];
	substitutions: string[];
}

function redirectWritesPath(operator: string, target: string): boolean {
	if (!(operator.startsWith(">") || operator.startsWith("&>") || operator === "<>")) return false;
	return !/^\d+$/.test(target) && target !== "-";
}

function matchingParen(source: string, openIndex: number): number {
	let depth = 0;
	for (let index = openIndex; index < source.length; index++) {
		const char = source[index];
		if (char === "\\") {
			index++;
		} else if (char === "'") {
			const close = source.indexOf("'", index + 1);
			index = close === -1 ? source.length : close;
		} else if (char === '"') {
			index++;
			while (index < source.length && source[index] !== '"') {
				if (source[index] === "\\") index++;
				index++;
			}
		} else if (char === "(") {
			depth++;
		} else if (char === ")") {
			depth--;
			if (depth === 0) return index;
		}
	}
	return source.length;
}

function closingBacktick(source: string, openIndex: number): number {
	for (let index = openIndex + 1; index < source.length; index++) {
		if (source[index] === "\\") index++;
		else if (source[index] === "`") return index;
	}
	return source.length;
}

function lex(source: string): Lexed {
	const tokens: Token[] = [];
	const substitutions: string[] = [];
	const pendingHeredocs: string[] = [];
	let word = "";
	let inWord = false;
	let wordSubstituted = false;
	let expectHeredocDelimiter = false;
	let index = 0;

	const endWord = () => {
		if (!inWord) return;
		tokens.push({ kind: "word", text: word, substituted: wordSubstituted });
		if (expectHeredocDelimiter) {
			pendingHeredocs.push(word);
			expectHeredocDelimiter = false;
		}
		word = "";
		inWord = false;
		wordSubstituted = false;
	};
	const separator = () => {
		endWord();
		tokens.push({ kind: "separator", text: "" });
	};
	const skipHeredocBodies = () => {
		for (const delimiter of pendingHeredocs) {
			while (index < source.length) {
				const lineEnd = source.indexOf("\n", index);
				const end = lineEnd === -1 ? source.length : lineEnd;
				const line = source.slice(index, end).trim();
				index = end + 1;
				if (line === delimiter) break;
			}
		}
		pendingHeredocs.length = 0;
	};
	const substitute = (start: number, end: number) => {
		substitutions.push(source.slice(start, end));
		inWord = true;
		wordSubstituted = true;
	};

	while (index < source.length) {
		const char = source[index];
		const next = source[index + 1];
		if (char === "\\") {
			if (next !== "\n" && next !== undefined) {
				word += next;
				inWord = true;
			}
			index += 2;
		} else if (char === "'") {
			const close = source.indexOf("'", index + 1);
			const end = close === -1 ? source.length : close;
			word += source.slice(index + 1, end);
			inWord = true;
			index = end + 1;
		} else if (char === '"') {
			index++;
			inWord = true;
			while (index < source.length && source[index] !== '"') {
				const inner = source[index];
				if (inner === "\\" && index + 1 < source.length && '"$`\\\n'.includes(source[index + 1])) {
					word += source[index + 1];
					index += 2;
				} else if (inner === "$" && source[index + 1] === "(") {
					const close = matchingParen(source, index + 1);
					substitute(index + 2, close);
					index = close + 1;
				} else if (inner === "`") {
					const close = closingBacktick(source, index);
					substitute(index + 1, close);
					index = close + 1;
				} else {
					word += inner;
					index++;
				}
			}
			index++;
		} else if ((char === "$" || char === "<" || char === ">") && next === "(") {
			const close = matchingParen(source, index + 1);
			substitute(index + 2, close);
			index = close + 1;
		} else if (char === "`") {
			const close = closingBacktick(source, index);
			substitute(index + 1, close);
			index = close + 1;
		} else if (char === "<" || char === ">" || (char === "&" && next === ">")) {
			if (inWord && /^\d+$/.test(word)) {
				word = "";
				inWord = false;
			}
			endWord();
			let operator = char;
			index++;
			if (char === "&") {
				operator += ">";
				index++;
				if (source[index] === ">") {
					operator += ">";
					index++;
				}
			} else if (source[index] === char) {
				operator += char;
				index++;
				if (char === "<" && source[index] === "<") {
					operator += "<";
					index++;
				} else if (char === "<" && source[index] === "-") {
					operator += "-";
					index++;
				}
			} else if (source[index] === "&" || source[index] === "|" || (char === "<" && source[index] === ">")) {
				operator += source[index];
				index++;
			}
			tokens.push({ kind: "redirect", text: operator });
			if (operator === "<<" || operator === "<<-") expectHeredocDelimiter = true;
		} else if (char === "&" || char === ";" || char === "|" || char === "(" || char === ")") {
			separator();
			index += (char === "&" || char === "|") && (next === char || next === "&") ? 2 : 1;
		} else if (char === "\n") {
			separator();
			index++;
			skipHeredocBodies();
		} else if (char === "#" && !inWord) {
			const lineEnd = source.indexOf("\n", index);
			index = lineEnd === -1 ? source.length : lineEnd;
		} else if (char === " " || char === "\t" || char === "\r") {
			endWord();
			index++;
		} else {
			word += char;
			inWord = true;
			index++;
		}
	}
	endWord();

	const commands: string[][] = [];
	const redirectTargets: string[][] = [];
	const substitutedCommands: boolean[] = [];
	let current: string[] = [];
	let currentTargets: string[] = [];
	let currentSubstituted = false;
	for (let position = 0; position < tokens.length; position++) {
		const token = tokens[position];
		if (token.kind === "separator") {
			if (current.length > 0 || currentTargets.length > 0) {
				commands.push(current);
				redirectTargets.push(currentTargets);
				substitutedCommands.push(currentSubstituted);
			}
			current = [];
			currentTargets = [];
			currentSubstituted = false;
		} else if (token.kind === "redirect") {
			const target = tokens[position + 1];
			if (target?.kind === "word") {
				if (redirectWritesPath(token.text, target.text)) currentTargets.push(target.text);
				position++;
			}
		} else {
			current.push(token.text);
			if (token.substituted) currentSubstituted = true;
		}
	}
	if (current.length > 0 || currentTargets.length > 0) {
		commands.push(current);
		redirectTargets.push(currentTargets);
		substitutedCommands.push(currentSubstituted);
	}
	return { commands, redirectTargets, substitutedCommands, substitutions };
}

function basename(word: string): string {
	const slash = word.lastIndexOf("/");
	return slash === -1 ? word : word.slice(slash + 1);
}

function skipOptions(words: string[], start: number, optionsWithArgument: Set<string>): number {
	let index = start;
	while (index < words.length && words[index].startsWith("-") && words[index] !== "-") {
		if (words[index] === "--") return index + 1;
		index += optionsWithArgument.has(words[index]) ? 2 : 1;
	}
	return index;
}

const SUDO_OPTIONS = new Set(["-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "--user", "--group"]);
const ENV_OPTIONS = new Set(["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]);
const XARGS_OPTIONS = new Set(["-I", "-L", "-n", "-P", "-s", "-d", "-E", "-a", "--arg-file", "--delimiter"]);
const TIME_OPTIONS = new Set(["-f", "-o", "--format", "--output"]);
const TIMEOUT_OPTIONS = new Set(["-s", "-k", "--signal", "--kill-after"]);
const NICE_OPTIONS = new Set(["-n", "--adjustment"]);
const NO_OPTIONS = new Set<string>();

function unwrapPrefixes(words: string[], findings: Finding[]): string[] {
	let index = 0;
	while (index < words.length) {
		const word = words[index];
		if (ASSIGNMENT.test(word) || KEYWORDS.has(word)) {
			index++;
			continue;
		}
		const name = basename(word);
		switch (name) {
			case "sudo":
			case "doas":
				findings.push(risky(`${name} runs a command with elevated privileges`));
				index = skipOptions(words, index + 1, SUDO_OPTIONS);
				break;
			case "pkexec":
				findings.push(risky("pkexec runs a command with elevated privileges"));
				index = skipOptions(words, index + 1, SUDO_OPTIONS);
				break;
			case "env":
				index = skipOptions(words, index + 1, ENV_OPTIONS);
				break;
			case "command":
				if (words.slice(index + 1).some((argument) => argument === "-v" || argument === "-V")) return [];
				index = skipOptions(words, index + 1, NO_OPTIONS);
				break;
			case "exec":
				index = skipOptions(words, index + 1, new Set(["-a"]));
				break;
			case "xargs":
				index = skipOptions(words, index + 1, XARGS_OPTIONS);
				break;
			case "nohup":
			case ",":
				index++;
				break;
			case "time":
				index = skipOptions(words, index + 1, TIME_OPTIONS);
				break;
			case "timeout":
				index = skipOptions(words, index + 1, TIMEOUT_OPTIONS) + 1;
				break;
			case "nice":
				index = skipOptions(words, index + 1, NICE_OPTIONS);
				break;
			case "nix": {
				if (words[index + 1] !== "shell" && words[index + 1] !== "develop") return words.slice(index);
				const commandFlag = words.findIndex(
					(argument, position) => position > index && (argument === "-c" || argument === "--command"),
				);
				if (commandFlag === -1) return words.slice(index);
				index = commandFlag + 1;
				break;
			}
			default:
				return words.slice(index);
		}
	}
	return [];
}

function shortFlags(argument: string): string | undefined {
	return /^-[A-Za-z0-9]+$/.test(argument) ? argument.slice(1) : undefined;
}

function hasShortFlag(args: string[], letter: string): boolean {
	return args.some((argument) => shortFlags(argument)?.includes(letter) ?? false);
}

function shellBody(name: string, args: string[]): string | undefined {
	if (!SHELLS.has(name) && name !== "su") return undefined;
	for (let index = 0; index < args.length; index++) {
		const argument = args[index];
		if (argument.startsWith("--command=")) return argument.slice("--command=".length);
		const isCommandFlag = argument === "--command" || (shortFlags(argument)?.includes("c") ?? false);
		if (isCommandFlag) return args.slice(index + 1).find((candidate) => !candidate.startsWith("-"));
	}
	return undefined;
}

function findExecCommands(args: string[]): string[][] {
	const commands: string[][] = [];
	for (let index = 0; index < args.length; index++) {
		if (!["-exec", "-execdir", "-ok", "-okdir"].includes(args[index])) continue;
		const end = args.findIndex((argument, position) => position > index && (argument === ";" || argument === "+"));
		const stop = end === -1 ? args.length : end;
		commands.push(args.slice(index + 1, stop));
		index = stop;
	}
	return commands;
}

const GIT_GLOBAL_OPTIONS = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"]);

const PUSH_OPTIONS = new Set(["--repo", "-o", "--push-option", "--receive-pack", "--exec"]);
const PROTECTED_BRANCHES = new Set(["main", "master"]);
const PUSH_BULK_OPTIONS = new Set(["--all", "--branches", "--mirror", "--tags", "--follow-tags"]);
const PUSH_DELETE_OPTIONS = new Set(["--delete", "--prune", "--mirror"]);
const UNRESOLVED_DESTINATION = /[$`*()]/;
const SSH_PORT = /^\d+$/;
const SSH_USER = /^[A-Za-z0-9._][A-Za-z0-9._-]*$/;
const SSH_DESTINATION = /^(?:[A-Za-z0-9._-]+@)?[A-Za-z0-9.-]+$/;
const SSH_REMOTE_METACHARACTERS = /[;&|<>$`()'"\\\n*?[]/;
const REVIEW_DESTINATION = /^refs\/for\/[^%]+(%.*)?$/;

function pushFindings(rest: string[]): Finding[] {
	const positionals: string[] = [];
	for (let index = 0; index < rest.length; index++) {
		const word = rest[index];
		if (word === "--") {
			positionals.push(...rest.slice(index + 1));
			break;
		}
		if (word.startsWith("-") && word !== "-") {
			if (PUSH_OPTIONS.has(word)) index++;
		} else {
			positionals.push(word);
		}
	}
	const refspecs = positionals.slice(1);
	const destinations = refspecs.map((refspec) => {
		const target = refspec.replace(/^\+/, "");
		const colon = target.indexOf(":");
		return colon === -1 ? target : target.slice(colon + 1);
	});

	const findings: Finding[] = [];
	if (
		rest.includes("--force") ||
		hasShortFlag(rest, "f") ||
		rest.some((word) => word.startsWith("--force-with-lease") || word.startsWith("--force-if-includes")) ||
		refspecs.some((refspec) => refspec.startsWith("+"))
	) {
		findings.push(risky("git push --force overwrites remote history"));
	}
	if (
		rest.some((word) => PUSH_DELETE_OPTIONS.has(word)) ||
		hasShortFlag(rest, "d") ||
		refspecs.some((refspec) => refspec.startsWith(":"))
	) {
		findings.push(risky("git push deletes a remote ref"));
	}
	if (
		rest.some((word) => PUSH_BULK_OPTIONS.has(word)) ||
		refspecs.includes("tag") ||
		destinations.some(
			(destination) =>
				destination.startsWith("refs/") &&
				!destination.startsWith("refs/heads/") &&
				!REVIEW_DESTINATION.test(destination),
		)
	) {
		findings.push(risky("git push publishes tags or every branch"));
	}
	if (
		refspecs.length === 0 ||
		destinations.some(
			(destination) =>
				destination === "HEAD" ||
				destination === "@" ||
				destination === "" ||
				destination.endsWith("/") ||
				UNRESOLVED_DESTINATION.test(destination),
		)
	) {
		findings.push(risky("git push names no branch, so it may publish to main"));
	}
	for (const destination of destinations) {
		const branch = destination.replace(/^refs\/heads\//, "");
		if (PROTECTED_BRANCHES.has(branch)) findings.push(risky(`git push publishes to ${destination}`));
	}
	if (findings.length > 0) return findings;
	if (destinations.every((destination) => REVIEW_DESTINATION.test(destination))) {
		return [childOnly("git push sends a change for review")];
	}
	return [childOnly("git push publishes to a remote")];
}

const REVIEW_INFO_LONG_FLAGS = ["--help", "--version"];
const REVIEW_BRANCH_LONG_FLAGS = ["--download", "--cherrypick", "--cherrypickindicate", "--cherrypickonly", "--compare"];
const REVIEW_BRANCH_SHORT_FLAGS = ["d", "x", "X", "N", "m"];

function reviewFindings(args: string[]): Finding[] {
	const hasLongFlag = (flags: string[]) =>
		args.some((argument) => flags.some((flag) => argument === flag || argument.startsWith(`${flag}=`)));
	if (hasLongFlag(REVIEW_INFO_LONG_FLAGS) || args.includes("-h")) return [];
	if (hasLongFlag(REVIEW_BRANCH_LONG_FLAGS) || REVIEW_BRANCH_SHORT_FLAGS.some((letter) => hasShortFlag(args, letter)))
		return [childOnly("git review changes branches")];
	if (hasLongFlag(["--list"]) || args.some((argument) => /^-l+$/.test(argument))) return [];
	return [childOnly("git review sends changes for review")];
}

function gitFindings(args: string[]): Finding[] {
	const start = skipOptions(args, 0, GIT_GLOBAL_OPTIONS);
	const subcommand = args[start];
	const rest = args.slice(start + 1);
	switch (subcommand) {
		case "reset":
			return rest.includes("--hard") ? [risky("git reset --hard discards uncommitted work", true)] : [];
		case "clean":
			return rest.includes("--force") || hasShortFlag(rest, "f")
				? [risky("git clean -f deletes untracked files", true)]
				: [];
		case "checkout": {
			const createsBranch =
				rest.includes("--orphan") || hasShortFlag(rest, "b") || hasShortFlag(rest, "B")
					? [childOnly("git checkout -b creates a branch")]
					: [];
			if (rest.includes("--"))
				return [...createsBranch, risky("git checkout -- discards uncommitted changes", true)];
			if (rest.includes(".")) return [...createsBranch, risky("git checkout . discards uncommitted changes", true)];
			return [...createsBranch, childOnly("git checkout switches branches", true)];
		}
		case "restore": {
			const staged = rest.includes("--staged") || hasShortFlag(rest, "S");
			const worktree = rest.includes("--worktree") || hasShortFlag(rest, "W");
			return staged && !worktree ? [] : [risky("git restore discards uncommitted changes", true)];
		}
		case "stash":
			return rest[0] === "drop" || rest[0] === "clear" ? [risky(`git stash ${rest[0]} deletes stashed work`, true)] : [];
		case "branch": {
			const forceDelete =
				rest.includes("-D") ||
				hasShortFlag(rest, "D") ||
				((rest.includes("--delete") || hasShortFlag(rest, "d")) && (rest.includes("--force") || hasShortFlag(rest, "f")));
			return forceDelete ? [risky("git branch -D deletes an unmerged branch")] : [];
		}
		case "push":
			return pushFindings(rest);
		case "review":
			return reviewFindings(rest);
		case "commit":
			return rest.includes("--amend")
				? [risky("git commit --amend rewrites history")]
				: [childOnly("git commit records history")];
		case "rebase":
			return [risky("git rebase rewrites history")];
		case "filter-branch":
		case "filter-repo":
			return [risky(`git ${subcommand} rewrites history`)];
		case "update-ref":
			return rest.includes("-d") ? [risky("git update-ref -d deletes a ref")] : [];
		case "reflog":
			return rest[0] === "expire" || rest[0] === "delete" ? [risky(`git reflog ${rest[0]} drops recovery points`)] : [];
		case "gc":
			return rest.some((argument) => argument.startsWith("--prune"))
				? [risky("git gc --prune deletes unreachable objects")]
				: [];
		case "merge":
		case "switch":
		case "cherry-pick":
		case "tag":
		case "worktree":
			return [childOnly(`git ${subcommand} changes branches or history`)];
		default:
			return [];
	}
}

const SYSTEMCTL_READ_ONLY = new Set(["status", "show", "is-active", "is-enabled", "is-failed", "cat"]);

function systemctlFindings(args: string[]): Finding[] {
	if (args.includes("--user")) return [];
	const subcommand = args.find((argument) => !argument.startsWith("-"));
	if (subcommand === undefined || SYSTEMCTL_READ_ONLY.has(subcommand) || subcommand.startsWith("list-")) return [];
	return [risky(`systemctl ${subcommand} changes system services`)];
}

function curlSendsData(args: string[]): boolean {
	return args.some(
		(argument) =>
			argument.startsWith("--data") ||
			argument.startsWith("--form") ||
			argument === "--json" ||
			argument === "--upload-file" ||
			/^-[A-Za-z]*[dFT]/.test(argument),
	);
}

const GH_READ_ONLY_COMMANDS = new Set(["status", "search", "help", "version", "--version", "--help"]);
const GH_GROUPS = new Set([
	"pr",
	"issue",
	"run",
	"repo",
	"release",
	"workflow",
	"cache",
	"label",
	"gist",
	"variable",
	"secret",
	"ruleset",
	"auth",
	"config",
	"extension",
	"alias",
	"org",
	"project",
]);
const GH_READ_ONLY_VERBS = new Set(["view", "list", "status", "diff", "checks", "watch", "download", "get"]);

function ghApiIsRead(args: string[]): boolean {
	const methods: (string | undefined)[] = [];
	for (let index = 1; index < args.length; index++) {
		const argument = args[index];
		const attached = /^-[A-Za-z]*X=?(.*)$/.exec(argument);
		if (argument === "--method") {
			methods.push(args[++index]);
		} else if (argument.startsWith("--method=")) {
			methods.push(argument.slice("--method=".length));
		} else if (!argument.startsWith("--") && attached !== null) {
			methods.push(attached[1] === "" ? args[++index] : attached[1]);
		}
	}
	if (methods.length > 0) return methods.every((method) => method !== undefined && /^GET$/i.test(method));
	return !args.some(
		(argument) =>
			argument === "--field" ||
			argument === "--raw-field" ||
			argument === "--input" ||
			argument.startsWith("--field=") ||
			argument.startsWith("--raw-field=") ||
			argument.startsWith("--input=") ||
			(!argument.startsWith("--") && /^-[A-Za-z]*[fF]/.test(argument)),
	);
}

function ghIsReadOnly(args: string[]): boolean {
	const [first, second] = args;
	if (first === undefined) return false;
	if (GH_READ_ONLY_COMMANDS.has(first)) return true;
	if (first === "api") return ghApiIsRead(args);
	return GH_GROUPS.has(first) && second !== undefined && GH_READ_ONLY_VERBS.has(second);
}

function sshIsGerritQuery(args: string[]): boolean {
	let index = 0;
	while (index < args.length && args[index].startsWith("-")) {
		const option = args[index];
		if (option === "-q" || option === "-T") {
			index += 1;
		} else if (option === "-p" && SSH_PORT.test(args[index + 1] ?? "")) {
			index += 2;
		} else if (option === "-l" && SSH_USER.test(args[index + 1] ?? "")) {
			index += 2;
		} else {
			return false;
		}
	}
	const [destination, command, subcommand, ...rest] = args.slice(index);
	if (destination === undefined || !SSH_DESTINATION.test(destination)) return false;
	if (command !== "gerrit" || subcommand !== "query") return false;
	return ![command, subcommand, ...rest].some((word) => SSH_REMOTE_METACHARACTERS.test(word));
}

function isRemoteRsyncArgument(argument: string): boolean {
	return !argument.startsWith("-") && (argument.startsWith("rsync://") || /^(?:[^\s/@:]+@)?[^\s/:]+:/.test(argument));
}

interface ParsedOptions {
	operands: string[];
	seen: Set<string>;
	values: Map<string, string[]>;
}

function parseOptions(
	args: string[],
	shortOptions: Record<string, string>,
	longOptions: Record<string, string>,
	valueOptions: Set<string>,
	optionalValueOptions: Set<string> = new Set(),
): ParsedOptions {
	const operands: string[] = [];
	const seen = new Set<string>();
	const values = new Map<string, string[]>();
	const record = (name: string, value?: string) => {
		seen.add(name);
		if (value !== undefined) values.set(name, [...(values.get(name) ?? []), value]);
	};
	let index = 0;
	let optionsEnded = false;
	while (index < args.length) {
		const argument = args[index];
		if (optionsEnded || argument === "-" || !argument.startsWith("-")) {
			operands.push(argument);
			index++;
			continue;
		}
		if (argument === "--") {
			optionsEnded = true;
			index++;
			continue;
		}
		if (argument.startsWith("--")) {
			const equals = argument.indexOf("=");
			const name = equals === -1 ? argument : argument.slice(0, equals);
			const canonical = longOptions[name];
			index++;
			if (canonical === undefined) continue;
			record(canonical, equals === -1 ? undefined : argument.slice(equals + 1));
			if (equals === -1 && valueOptions.has(canonical) && index < args.length) {
				record(canonical, args[index]);
				index++;
			}
			continue;
		}
		let position = 1;
		while (position < argument.length) {
			const canonical = shortOptions[argument[position]];
			position++;
			if (canonical === undefined) continue;
			const rest = argument.slice(position);
			if (valueOptions.has(canonical)) {
				if (rest !== "") {
					record(canonical, rest);
				} else if (index + 1 < args.length) {
					record(canonical, args[index + 1]);
					index++;
				} else {
					record(canonical);
				}
				position = argument.length;
				break;
			}
			if (optionalValueOptions.has(canonical)) {
				record(canonical, rest === "" ? undefined : rest);
				position = argument.length;
				break;
			}
			record(canonical);
		}
		index++;
	}
	return { operands, seen, values };
}

const TARGET_DIRECTORY_OPTIONS = new Set(["target-directory"]);
const SED_VALUE_OPTIONS = new Set(["expression", "file"]);
const SED_OPTIONAL_VALUE_OPTIONS = new Set(["in-place"]);
const OUTPUT_OPTIONS = new Set(["output"]);
const OUTPUT_DOCUMENT_OPTIONS = new Set(["output-document"]);
const EMPTY_OPTIONS = new Set<string>();

function writeDestinations(name: string, args: string[]): string[] {
	switch (name) {
		case "cp":
		case "mv":
		case "ln":
		case "install": {
			const parsed = parseOptions(
				args,
				{ t: "target-directory" },
				{ "--target-directory": "target-directory" },
				TARGET_DIRECTORY_OPTIONS,
			);
			const directories = parsed.values.get("target-directory");
			if (directories !== undefined && directories.length > 0) return directories.slice(-1);
			return parsed.operands.length > 0 ? [parsed.operands[parsed.operands.length - 1]] : [];
		}
		case "tee":
			return parseOptions(args, {}, {}, EMPTY_OPTIONS).operands;
		case "sed": {
			const parsed = parseOptions(
				args,
				{ i: "in-place", e: "expression", f: "file" },
				{ "--in-place": "in-place", "--expression": "expression", "--file": "file" },
				SED_VALUE_OPTIONS,
				SED_OPTIONAL_VALUE_OPTIONS,
			);
			if (!parsed.seen.has("in-place")) return [];
			const script = parsed.seen.has("expression") || parsed.seen.has("file") ? 0 : 1;
			return parsed.operands.slice(script);
		}
		case "curl":
			return (
				parseOptions(args, { o: "output" }, { "--output": "output" }, OUTPUT_OPTIONS).values.get("output") ?? []
			);
		case "wget":
			return (
				parseOptions(args, { O: "output-document" }, { "--output-document": "output-document" }, OUTPUT_DOCUMENT_OPTIONS).values.get(
					"output-document",
				) ?? []
			);
		case "rsync": {
			if (args.some(isRemoteRsyncArgument)) return [];
			const parsed = parseOptions(args, {}, {}, EMPTY_OPTIONS);
			return parsed.operands.length > 0 ? [parsed.operands[parsed.operands.length - 1]] : [];
		}
		default:
			return [];
	}
}

function scratchRoot(options: ClassifyOptions): string | undefined {
	if (options.scratch === undefined || options.scratch === "") return undefined;
	return normalizePath(options.scratch, options);
}

function unresolvedOperands(operands: string[]): boolean {
	return operands.some((operand) => operand === "-" || PATH_METACHARACTERS.test(operand));
}

function rmFindings(
	args: string[],
	hasSubstitution: boolean,
	cwd: string | undefined,
	cwdKnown: boolean,
	options: ClassifyOptions,
): Finding[] {
	if (!args.includes("--recursive") && !hasShortFlag(args, "r") && !hasShortFlag(args, "R")) return [];
	const blocked = [risky("rm -r deletes directories")];
	const operands = parseOptions(args, {}, {}, EMPTY_OPTIONS).operands;
	if (operands.length === 0 || cwd === undefined || unresolvedOperands(operands)) return blocked;
	const targets = operands.map((operand) => normalizePath(operand, { ...options, cwd }));
	const scratch = scratchRoot(options);
	if (scratch !== undefined && targets.every((target) => isWithin(target, scratch))) return [];
	const root = options.cwd === undefined ? undefined : normalizePath(options.cwd, options);
	if (root === undefined || !cwdKnown || hasSubstitution) return blocked;
	const contained = targets.every(
		(target) =>
			isWithin(target, root) &&
			target !== root &&
			target
				.slice(root.length + 1)
				.split("/")
				.every((segment) => !segment.startsWith(".")),
	);
	return contained ? [] : blocked;
}

function findRoots(args: string[]): string[] {
	let index = 0;
	while (index < args.length) {
		const argument = args[index];
		if (["-H", "-L", "-P"].includes(argument) || /^-O\d*$/.test(argument)) {
			index++;
			continue;
		}
		if (argument === "-D" || FIND_VALUE_GLOBALS.has(argument)) {
			index += 2;
			continue;
		}
		break;
	}
	const roots: string[] = [];
	while (index < args.length && !args[index].startsWith("-") && args[index] !== "(" && args[index] !== "!") {
		roots.push(args[index]);
		index++;
	}
	return roots;
}

function findDeleteFindings(
	args: string[],
	hasSubstitution: boolean,
	cwd: string | undefined,
	cwdKnown: boolean,
	options: ClassifyOptions,
): Finding[] {
	const blocked = [risky("find -delete deletes files")];
	const scratch = scratchRoot(options);
	const roots = findRoots(args);
	if (scratch === undefined || !cwdKnown || hasSubstitution || cwd === undefined) return blocked;
	if (roots.length === 0 || unresolvedOperands(roots)) return blocked;
	const targets = roots.map((root) => normalizePath(root, { ...options, cwd }));
	return targets.every((target) => isWithin(target, scratch)) ? [] : blocked;
}

function commandFindings(
	name: string,
	args: string[],
	hasSubstitution: boolean,
	cwd: string | undefined,
	cwdKnown: boolean,
	options: ClassifyOptions,
): Finding[] {
	if (name.startsWith("mkfs")) return [risky(`${name} formats a filesystem`)];
	switch (name) {
		case "age":
		case "rage":
			return args.includes("--decrypt") || hasShortFlag(args, "d") ? [secret(`${name} decrypts secrets`)] : [];
		case "agenix":
			return args.includes("--decrypt") || hasShortFlag(args, "d") ? [secret("agenix decrypts secrets")] : [];
		case "gh":
			if (args[0] === "auth" && args[1] === "token") return [secret("gh auth token prints a credential")];
			if (args[0] === "auth" && (args.includes("--show-token") || hasShortFlag(args, "t")))
				return [secret("gh auth --show-token prints a credential")];
			return ghIsReadOnly(args) ? [] : [childOnly(`${["gh", ...args.slice(0, 2)].join(" ")} may change GitHub state`)];
		case "git-review":
			return reviewFindings(args);
		case "security":
			return ["find-generic-password", "find-internet-password", "dump-keychain"].includes(args[0])
				? [secret(`security ${args[0]} reads the keychain`)]
				: [];
		case "rm":
			return rmFindings(args, hasSubstitution, cwd, cwdKnown, options);
		case "find":
			return args.includes("-delete") ? findDeleteFindings(args, hasSubstitution, cwd, cwdKnown, options) : [];
		case "shred":
			return [risky("shred destroys files")];
		case "dd":
			return args.some((argument) => argument.startsWith("of=")) ? [risky("dd of= overwrites a file or device")] : [];
		case "chmod":
		case "chown":
			return args.includes("--recursive") ||
				hasShortFlag(args, "R") ||
				args.some((argument) => argument.includes("777"))
				? [risky(`${name} -R or 777 changes permissions broadly`)]
				: [];
		case "su":
			return [risky("su switches user")];
		case "nix":
			if (args.includes("profile") && ["install", "remove", "add"].includes(args[args.indexOf("profile") + 1]))
				return [risky("nix profile changes the global profile")];
			if (args.includes("store") && args[args.indexOf("store") + 1] === "gc")
				return [risky("nix store gc deletes store paths")];
			return [];
		case "nix-env":
			return args.some((argument) => ["--install", "--uninstall", "--erase"].includes(argument)) ||
				hasShortFlag(args, "i") ||
				hasShortFlag(args, "e")
				? [risky("nix-env changes the global profile")]
				: [];
		case "nix-collect-garbage":
			return [risky("nix-collect-garbage deletes store paths")];
		case "nix-store":
			return args.includes("--gc") || args.includes("--delete") ? [risky("nix-store --gc deletes store paths")] : [];
		case "npm":
		case "pnpm":
			return args.includes("-g") || args.includes("--global") || args.includes("--location=global")
				? [risky(`${name} global install changes the system`)]
				: [];
		case "yarn":
			return args[0] === "global" ? [risky("yarn global changes the system")] : [];
		case "pip":
		case "pip3":
			return args.includes("install") && args.includes("--user") ? [risky("pip install --user installs globally")] : [];
		case "cargo":
		case "go":
		case "brew":
			return args[0] === "install" ? [risky(`${name} install installs globally`)] : [];
		case "nixos-rebuild":
		case "darwin-rebuild":
			return [risky(`${name} changes the system configuration`)];
		case "nh":
			if (args[0] === "os" && ["switch", "boot", "test"].includes(args[1]))
				return [risky(`nh os ${args[1]} changes the system configuration`)];
			if (args[0] === "darwin" && args[1] === "switch") return [risky("nh darwin switch changes the system configuration")];
			return [];
		case "systemctl":
			return systemctlFindings(args);
		case "shutdown":
		case "reboot":
		case "poweroff":
		case "halt":
		case "launchctl":
			return [risky(`${name} changes system state`)];
		case "kill":
		case "pkill":
		case "killall":
			return [risky(`${name} signals processes`)];
		case "curl":
			return curlSendsData(args) ? [risky("curl uploads data")] : [];
		case "wget":
			return args.some((argument) => /^--(post|body)-(data|file)/.test(argument)) ? [risky("wget uploads data")] : [];
		case "nc":
		case "ncat":
		case "socat":
		case "scp":
		case "sftp":
			return [risky(`${name} opens a network connection`)];
		case "ssh":
			return !hasSubstitution && sshIsGerritQuery(args) ? [childOnly("ssh runs a Gerrit query")] : [risky("ssh opens a network connection")];
		case "rsync":
			return args.some(isRemoteRsyncArgument) ? [risky("rsync transfers to or from a remote host")] : [];
		case "git":
			return gitFindings(args);
		default:
			return [];
	}
}

function secretPathReason(text: string): string | undefined {
	if (text.includes("/run/agenix")) return "/run/agenix holds decrypted secrets";
	for (const match of text.matchAll(new RegExp(`\\.ssh/(${PATH_TOKEN_END})`, "g"))) {
		const name = match[1];
		if ((name.startsWith("id_") || /[*?[]/.test(name)) && !name.endsWith(".pub")) return "SSH private keys are secret";
	}
	for (const match of text.matchAll(new RegExp(`ssh_host_(${PATH_TOKEN_END})`, "g"))) {
		if (!match[1].endsWith(".pub")) return "SSH host private keys are secret";
	}
	if (/\.gnupg(?![\w-])/.test(text)) return "~/.gnupg holds private keys";
	if (/\.config\/age(?![\w.-])/.test(text)) return "~/.config/age holds age identities";
	for (const match of text.matchAll(new RegExp(`\\.config/gh/(${PATH_TOKEN_END})`, "g"))) {
		if (match[1].startsWith("hosts") || /[*?[]/.test(match[1])) return "~/.config/gh/hosts.yml holds GitHub tokens";
	}
	if (/\.netrc(?![\w.-])/.test(text)) return "~/.netrc holds credentials";
	return undefined;
}

function analyzeBash(command: string, options: ClassifyOptions): Finding[] {
	const findings: Finding[] = [];
	const visitSource = (source: string, depth: number, initialCwd = options.cwd, initialCwdKnown = true) => {
		if (depth > MAX_NESTING) {
			findings.push(risky("the command nests too deeply to check"));
			return;
		}
		const lexed = lex(source);
		let cwd = initialCwd;
		let cwdKnown = initialCwdKnown;
		lexed.commands.forEach((words, position) => {
			const hasSubstitution = lexed.substitutedCommands[position] ?? false;
			visitWords(words, depth, hasSubstitution, lexed.redirectTargets[position] ?? [], cwd, cwdKnown);
			const change = cdChange(words, cwd, options, hasSubstitution);
			if (change !== undefined) {
				cwd = change.cwd;
				cwdKnown = change.known;
			}
		});
		for (const substitution of lexed.substitutions) visitSource(substitution, depth + 1, cwd, cwdKnown);
	};
	const visitWords = (
		words: string[],
		depth: number,
		hasSubstitution = false,
		redirectTargets: string[] = [],
		cwd = options.cwd,
		cwdKnown = true,
	) => {
		const secretReason = secretPathReason(words.join(" "));
		if (secretReason) findings.push(secret(secretReason));
		const command = unwrapPrefixes(words, findings);
		if (command.length === 0) {
			findings.push(...writeFindings(redirectTargets, cwd, options));
			return;
		}
		const name = basename(command[0]);
		const args = command.slice(1);
		const body = shellBody(name, args);
		if (body !== undefined) visitSource(body, depth + 1, cwd, cwdKnown);
		if (name === "eval") visitSource(args.join(" "), depth + 1, cwd, cwdKnown);
		if (name === "find") {
			for (const execCommand of findExecCommands(args)) {
				if (execCommand.length > 0 && basename(execCommand[0]) === "rm") findings.push(risky("find -exec rm deletes files"));
				visitWords(execCommand, depth + 1, false, [], cwd, cwdKnown);
			}
		}
		findings.push(...commandFindings(name, args, hasSubstitution, cwd, cwdKnown, options));
		findings.push(...writeFindings([...redirectTargets, ...writeDestinations(name, args)], cwd, options));
	};
	const rawSecretReason = secretPathReason(command);
	if (rawSecretReason) findings.push(secret(rawSecretReason));
	visitSource(command, 0);
	return findings;
}

function normalizePath(rawPath: string, options: ClassifyOptions): string {
	let expanded = rawPath.replace(/^(?:~|\$HOME|\$\{HOME\})(?=\/|$)/, () => options.home);
	if (!expanded.startsWith("/") && options.cwd) expanded = `${options.cwd}/${expanded}`;
	const absolute = expanded.startsWith("/");
	const segments: string[] = [];
	for (const segment of expanded.split("/")) {
		if (segment === "" || segment === ".") continue;
		if (segment === ".." && segments.length > 0 && segments[segments.length - 1] !== "..") segments.pop();
		else segments.push(segment);
	}
	const joined = segments.join("/");
	return absolute ? `/${joined}` : joined || ".";
}

function isWithin(candidate: string, directory: string): boolean {
	return candidate === directory || candidate.startsWith(directory.endsWith("/") ? directory : `${directory}/`);
}

function isScratchPath(filePath: string, options: ClassifyOptions): boolean {
	if (options.scratch === undefined || options.scratch === "") return false;
	return isWithin(filePath, normalizePath(options.scratch, options));
}

interface CdChange {
	cwd: string | undefined;
	known: boolean;
}

function cdChange(
	words: string[],
	cwd: string | undefined,
	options: ClassifyOptions,
	hasSubstitution: boolean,
): CdChange | undefined {
	let index = 0;
	while (index < words.length && (ASSIGNMENT.test(words[index]) || KEYWORDS.has(words[index]))) index++;
	if (basename(words[index] ?? "") !== "cd") return undefined;
	const args = words.slice(index + 1);
	let operand: string | undefined;
	for (let position = 0; position < args.length; position++) {
		const argument = args[position];
		if (argument === "--") {
			operand = args.slice(position + 1).find((candidate) => candidate !== "") ?? operand;
			break;
		}
		if (argument.startsWith("-") && argument !== "-") continue;
		if (argument !== "") operand = argument;
	}
	if (hasSubstitution || operand === undefined || operand === "-" || PATH_METACHARACTERS.test(operand))
		return { cwd: options.cwd, known: false };
	return { cwd: normalizePath(operand, { ...options, cwd }), known: true };
}

function writeFindings(targets: string[], cwd: string | undefined, options: ClassifyOptions): Finding[] {
	const findings: Finding[] = [];
	const allowedRoots = ["/tmp", `${options.home}/.cache`, `${options.home}/.local`];
	if (options.cwd !== undefined) allowedRoots.push(normalizePath(options.cwd, options));
	if (options.scratch !== undefined && options.scratch !== "") allowedRoots.push(normalizePath(options.scratch, options));
	for (const target of targets) {
		if (target === "" || target === "-") continue;
		const filePath = normalizePath(target, { ...options, cwd });
		const secretReason = secretPathReason(filePath) ?? secretPathReason(target);
		if (secretReason !== undefined) {
			findings.push(secret(secretReason));
			continue;
		}
		if (!filePath.startsWith("/") || allowedRoots.some((root) => isWithin(filePath, root))) continue;
		findings.push(
			isWithin(filePath, `${options.home}/.pi/plans`)
				? childOnly("bash writes the loop's state files")
				: risky("bash writes outside the session"),
		);
	}
	return findings;
}

function isDotenv(filePath: string): boolean {
	const name = basename(filePath);
	return /^\.env(\..+)?$/.test(name) && !DOTENV_TEMPLATES.has(name);
}

function secretRoots(home: string): string[] {
	return ["/run/agenix", `${home}/.ssh`, `${home}/.gnupg`, `${home}/.config/age`, `${home}/.config/gh`, `${home}/.netrc`];
}

function analyzePath(toolName: string, rawPath: unknown, options: ClassifyOptions): Finding[] {
	if (typeof rawPath !== "string" || rawPath === "") return [];
	const filePath = normalizePath(rawPath, options);
	const secretReason = secretPathReason(filePath) ?? secretPathReason(rawPath);
	if (secretReason) return [secret(secretReason)];
	if (toolName === "grep" && secretRoots(options.home).some((root) => isWithin(root, filePath)))
		return [secret(`grep in ${filePath} would search secret files; search a narrower directory`)];
	if (toolName === "read" || toolName === "grep")
		return isDotenv(filePath) ? [risky(`${toolName} of ${basename(filePath)} may expose credentials`)] : [];
	if (toolName !== "edit" && toolName !== "write") return [];
	const protectedDirectories = ["/etc", `${options.home}/.ssh`, `${options.home}/.pi/agent`];
	const protectedDirectory = protectedDirectories.find((directory) => isWithin(filePath, directory));
	if (protectedDirectory) return [risky(`${toolName} under ${protectedDirectory}`)];
	if (isWithin(filePath, `${options.home}/.pi/plans`) && !isScratchPath(filePath, options))
		return [childOnly(`${toolName} under ${options.home}/.pi/plans changes the loop's state files`)];
	if (/(^|\/)\.git(\/|$)/.test(filePath)) return [risky(`${toolName} of git internals`)];
	if (isDotenv(filePath)) return [risky(`${toolName} of ${basename(filePath)} may change credentials`)];
	return [];
}

export const DEFAULT_BASH_TIMEOUT_SECONDS = 600;
export const MAX_BASH_TIMEOUT_SECONDS = 1800;

export function bashTimeout(role: Role, requested: unknown): number | undefined {
	if (role === "main") return undefined;
	if (typeof requested !== "number" || !Number.isFinite(requested) || requested <= 0) return DEFAULT_BASH_TIMEOUT_SECONDS;
	return requested > MAX_BASH_TIMEOUT_SECONDS ? MAX_BASH_TIMEOUT_SECONDS : undefined;
}

function decide(findings: Finding[], role: Role, scratchCommand: boolean): Decision {
	const describe = (selected: Finding[]) => [...new Set(selected.map((item) => item.reason))].join("; ");
	const secrets = findings.filter((item) => item.severity === "secret");
	if (secrets.length > 0) return { action: "block", reason: describe(secrets) };
	const relevant = findings.filter(
		(item) =>
			!(role === "reviewer" && scratchCommand && item.scratchExempt) && (role !== "main" || item.severity === "risky"),
	);
	if (relevant.length === 0) return { action: "allow" };
	return { action: role === "main" ? "confirm" : "block", reason: describe(relevant) };
}

export function classify(
	toolName: string,
	input: Record<string, unknown>,
	role: Role,
	options: ClassifyOptions,
): Decision {
	if (toolName === "bash") {
		const command = typeof input.command === "string" ? input.command : "";
		const scratchCommand = options.scratch !== undefined && options.scratch !== "" && command.includes(options.scratch);
		return decide(analyzeBash(command, options), role, scratchCommand);
	}
	if (PATH_TOOLS.has(toolName)) return decide(analyzePath(toolName, input.path, options), role, false);
	return { action: "allow" };
}
