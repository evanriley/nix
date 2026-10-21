import assert from "node:assert/strict";
import { test } from "node:test";
import {
	type Action,
	bashTimeout,
	type ClassifyOptions,
	classify,
	DEFAULT_BASH_TIMEOUT_SECONDS,
	MAX_BASH_TIMEOUT_SECONDS,
	type Role,
} from "./rules.ts";

const HOME = "/home/tester";
const SCRATCH = "/home/tester/.pi/plans/repo/feature/scratch-1";
const ROLES: Role[] = ["main", "worker", "reviewer", "oracle"];

type Expected = Action | { main: Action; children: Action };

interface Case {
	tool: string;
	input: Record<string, unknown>;
	roles?: Role[];
	scratch?: string;
	expected: Expected;
}

const bash = (command: string, expected: Expected, roles?: Role[], scratch?: string): Case => ({
	tool: "bash",
	input: { command },
	expected,
	roles,
	scratch,
});
const tool = (name: string, path: string | undefined, expected: Expected, roles?: Role[], scratch?: string): Case => ({
	tool: name,
	input: path === undefined ? {} : { path },
	expected,
	roles,
	scratch,
});

const RISKY: Expected = { main: "confirm", children: "block" };
const CHILD_ONLY: Expected = { main: "allow", children: "block" };

const cases: Case[] = [
	bash('rg -n "rm -rf" src', "allow", ["worker"]),
	bash("cd build && rm -rf out", "allow", ["worker"]),
	bash("git push", "confirm", ["main"]),
	bash('git commit -m "fix sudo prompt"', "allow", ["main"]),
	bash("cat /run/agenix/kagi-key", "block"),
	tool("read", "~/.ssh/id_ed25519.pub", "allow", ["main"]),
	tool("read", "~/.ssh/id_ed25519", "block", ["main"]),
	bash(`cd ${SCRATCH} && git checkout -- f`, "allow", ["reviewer"], SCRATCH),
	bash("git checkout -- f", "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout src/a.zig`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout .`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout -b x`, "block", ["reviewer", "worker"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout -B x`, "block", ["reviewer", "worker"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout --orphan x`, "block", ["reviewer", "worker"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout -b x -- f`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git checkout src/a.zig`, "block", ["worker"], SCRATCH),
	bash("git checkout src/a.zig", "block", ["reviewer", "worker"], SCRATCH),
	bash("git checkout src/a.zig", "allow", ["main"]),
	bash("git checkout -b x", "allow", ["main"]),
	bash("bash -c 'git reset --hard'", "block", ["worker"]),
	bash("git -C /x push origin main", "block", ["worker"]),
	bash("git restore --staged f", "allow", ["main"]),
	bash("git restore f", "confirm", ["main"]),
	bash("FOO=1 timeout 5 sudo ls", "block", ["worker"]),
	bash("curl -s https://example.com", "allow", ["main"]),
	bash("curl -d @f https://x", "confirm", ["main"]),
	tool("write", ".env.example", "allow", ["worker"]),
	tool("write", ".env", "block", ["worker"]),
	bash("nix build .#x", "allow", ["main"]),
	bash("git status && git diff", "allow", ["worker"]),

	bash("ls /run/agenix", "block"),
	bash("cat /run/age''nix/x", "block"),
	bash("ls /run/user", "allow"),
	tool("read", "/run/agenix/kagi-key", "block"),
	tool("grep", "/run", "block"),
	tool("grep", "/", "block"),
	tool("grep", "/home/tester/project", "allow"),
	tool("grep", undefined, "allow"),
	tool("ls", "/run/agenix", "block"),
	tool("find", "/run/agenix", "block"),
	tool("edit", "/run/agenix/x", "block"),
	bash("cat ~/.ssh/id_rsa", "block"),
	bash("cat $HOME/.ssh/id_ed25519", "block"),
	bash("cat ~/.ssh/*", "block"),
	bash("cat ~/.ssh/id_ed25519.pub", "allow"),
	bash("ls ~/.ssh", "allow"),
	tool("ls", "~/.ssh", "allow"),
	tool("grep", "~/.ssh", "block"),
	tool("grep", "~", "block"),
	bash("cat /etc/ssh/ssh_host_ed25519_key", "block"),
	bash("cat /etc/ssh/ssh_host_ed25519_key.pub", "allow"),
	tool("read", "/etc/ssh/ssh_host_rsa_key", "block"),
	tool("read", "/etc/ssh/ssh_host_rsa_key.pub", "allow"),
	bash("ls ~/.gnupg/private-keys-v1.d", "block"),
	tool("read", "/home/tester/.gnupg/pubring.kbx", "block"),
	bash("cat ~/.gnupg-notes.md", "allow"),
	bash("cat ~/.config/age/keys.txt", "block"),
	tool("read", "~/.config/age/keys.txt", "block"),
	bash("cat ~/.config/ageing.txt", "allow"),
	bash("cat ~/.config/gh/hosts.yml", "block"),
	tool("read", "/home/tester/.config/gh/hosts.yml", "block"),
	bash("cat ~/.config/gh/config.yml", "allow"),
	bash("cat ~/.netrc", "block"),
	tool("read", "~/.netrc", "block"),
	bash("cat ~/.netrc.example", "allow"),

	bash("age -d -i key secret.age", "block"),
	bash("age --decrypt secret.age", "block"),
	bash("age -e -r key file", "allow"),
	bash("rage -d secret.age", "block"),
	bash("rage --decrypt secret.age", "block"),
	bash("agenix -d secrets/kagi-key.age", "block"),
	bash("agenix -e secrets/kagi-key.age", "allow", ["main"]),
	bash("gh auth token", "block"),
	bash("gh auth status", "allow"),
	bash("gh auth status --show-token", "block"),
	bash("security find-generic-password -s x -w", "block"),
	bash("security find-internet-password -s x", "block"),
	bash("security list-keychains", "allow"),
	bash("echo $(gh auth token)", "block"),
	bash("gh pr view 12", "allow"),
	bash("gh pr list --state open", "allow"),
	bash("gh pr status", "allow"),
	bash("gh pr diff 12", "allow"),
	bash("gh pr checks 12 --watch", "allow"),
	bash("gh issue view 3 --comments", "allow"),
	bash("gh issue list -L 5", "allow"),
	bash("gh run list --branch main --limit 1 --json databaseId,conclusion", "allow"),
	bash("gh run view 123 --log-failed", "allow"),
	bash("gh run watch 123", "allow"),
	bash("gh run download 123", "allow"),
	bash("gh repo view --json defaultBranchRef --jq .defaultBranchRef.name", "allow"),
	bash("gh release view v1.0.0", "allow"),
	bash("gh release list", "allow"),
	bash("gh release download v1.0.0", "allow"),
	bash("gh workflow list", "allow"),
	bash("gh variable get NAME", "allow"),
	bash("gh secret list", "allow"),
	bash('gh search code "foo bar"', "allow"),
	bash("gh status", "allow"),
	bash("gh --version", "allow"),
	bash("gh help pr", "allow"),
	bash("gh api repos/o/r/pulls/1", "allow"),
	bash("gh api repos/o/r --jq .name", "allow"),
	bash("gh api -X GET search/issues -f q=x", "allow"),
	bash("gh api --method=get repos/o/r", "allow"),
	bash("gh api -XGET repos/o/r -F per_page=5", "allow"),
	bash("gh pr merge --rebase --delete-branch", CHILD_ONLY),
	bash("gh pr merge 12 --admin", CHILD_ONLY),
	bash("gh pr create --title x --body y", CHILD_ONLY),
	bash("gh pr close 12", CHILD_ONLY),
	bash("gh pr comment 12 --body x", CHILD_ONLY),
	bash("gh pr review 12 --approve", CHILD_ONLY),
	bash("gh pr edit 12 --title x", CHILD_ONLY),
	bash("gh pr ready 12", CHILD_ONLY),
	bash("gh pr checkout 12", CHILD_ONLY),
	bash("gh issue create --title x", CHILD_ONLY),
	bash("gh issue close 3", CHILD_ONLY),
	bash("gh issue comment 3 -b x", CHILD_ONLY),
	bash("gh release create v1.0.0", CHILD_ONLY),
	bash("gh release delete v1.0.0", CHILD_ONLY),
	bash("gh release upload v1.0.0 f", CHILD_ONLY),
	bash("gh repo delete o/r --yes", CHILD_ONLY),
	bash("gh repo create x", CHILD_ONLY),
	bash("gh repo edit --visibility private", CHILD_ONLY),
	bash("gh repo clone o/r", CHILD_ONLY),
	bash("gh run rerun 123", CHILD_ONLY),
	bash("gh run cancel 123", CHILD_ONLY),
	bash("gh workflow run ci.yml", CHILD_ONLY),
	bash("gh secret set NAME", CHILD_ONLY),
	bash("gh variable set NAME", CHILD_ONLY),
	bash("gh cache delete --all", CHILD_ONLY),
	bash("gh label create x", CHILD_ONLY),
	bash("gh gist create f", CHILD_ONLY),
	bash("gh auth login", CHILD_ONLY),
	bash("gh auth logout", CHILD_ONLY),
	bash("gh auth refresh", CHILD_ONLY),
	bash("gh config set editor vim", CHILD_ONLY),
	bash("gh alias set x y", CHILD_ONLY),
	bash("gh extension install o/r", CHILD_ONLY),
	bash("gh co 12", CHILD_ONLY),
	bash("gh browse", CHILD_ONLY),
	bash("gh", CHILD_ONLY),
	bash("gh pr", CHILD_ONLY),
	bash("gh issue --title list create", CHILD_ONLY),
	bash("gh -R o/r pr merge 12", CHILD_ONLY),
	bash("gh --repo o/r pr view 12", CHILD_ONLY),
	bash("gh api -X POST repos/o/r/issues", CHILD_ONLY),
	bash("gh api --method DELETE repos/o/r", CHILD_ONLY),
	bash("gh api -XPATCH repos/o/r", CHILD_ONLY),
	bash("gh api repos/o/r/issues -f title=x", CHILD_ONLY),
	bash("gh api repos/o/r/issues -F body=@f", CHILD_ONLY),
	bash("gh api repos/o/r/issues --field title=x", CHILD_ONLY),
	bash("gh api repos/o/r/issues --raw-field=title=x", CHILD_ONLY),
	bash("gh api repos/o/r/issues --input f.json", CHILD_ONLY),
	bash("gh api graphql -f query='mutation{}'", CHILD_ONLY),
	bash('gh api -X "$method" repos/o/r', CHILD_ONLY),
	bash("gh api -X", CHILD_ONLY),
	bash("timeout 30 gh pr merge 12", CHILD_ONLY),
	bash("bash -c 'gh pr merge 12'", CHILD_ONLY),
	bash("git status && gh pr create --fill", CHILD_ONLY),
	bash(`cd ${SCRATCH} && gh pr merge 12`, "block", ["reviewer"], SCRATCH),
	bash("gh pr merge --rebase --delete-branch", "allow", ["main"]),
	bash('echo "$(age -d f)"', "block"),

	bash("rm -rf build", "allow"),
	bash("rm -fr build", "allow"),
	bash("rm -Rf build", "allow"),
	bash("rm -r build", "allow"),
	bash("rm --recursive build", "allow"),
	bash("rm -rf ./build", "allow"),
	bash("rm -rf build node_modules", "allow"),
	bash("rm -rf -- build", "allow"),
	bash("rm -f file.txt", "allow"),
	bash("rm -rf .git", RISKY),
	bash("rm -rf .", RISKY),
	bash("rm -rf ..", RISKY),
	bash("rm -rf ~/x", RISKY),
	bash("rm -rf /", RISKY),
	bash("rm -rf *", RISKY),
	bash("rm -rf -", RISKY),
	bash("rm -rf $DIR", RISKY),
	bash("cd .git && rm -rf objects", RISKY),
	bash("cd .config && rm -rf x", RISKY),
	bash("cd $X && rm -rf build", RISKY),
	bash("cd /etc && rm -rf x", RISKY),
	bash("find . -name '*.o' -delete", RISKY),
	bash("find / -delete", RISKY),
	bash("find -delete", RISKY),
	bash("find $D -delete", RISKY),
	bash("find . -name '*.o' -print", "allow"),
	bash("find . -name x -exec rm {} \\;", RISKY),
	bash("find . -name x -exec git push \\;", RISKY),
	bash("find . -name x -exec cat {} +", "allow"),
	bash("shred secret.txt", RISKY),
	bash("dd if=/dev/zero of=/dev/sda bs=1M", RISKY),
	bash("dd if=/dev/sda bs=1M count=1", "allow"),
	bash("mkfs.ext4 /dev/sdb1", RISKY),
	bash("chmod -R 755 dir", RISKY),
	bash("chmod 777 file", RISKY),
	bash("chown -R evan dir", RISKY),
	bash("chmod +x script.sh", "allow"),

	bash("sudo ls", RISKY),
	bash("doas ls", RISKY),
	bash("su -c 'ls'", RISKY),
	bash("pkexec ls", RISKY),
	bash("echo sudo", "allow"),
	bash("env FOO=1 sudo -u root ls", RISKY),
	bash("xargs -0 sudo rm", RISKY),
	bash("command sudo ls", RISKY),
	bash("command -v sudo", "allow"),
	bash("exec sudo ls", RISKY),
	bash("nohup sudo ls", RISKY),
	bash("time sudo ls", RISKY),
	bash("nice -n 5 sudo ls", RISKY),
	bash("ls | sudo tee /etc/x", RISKY),
	bash("ls; sudo ls", RISKY),
	bash("ls || sudo ls", RISKY),
	bash("ls & sudo ls", RISKY),
	bash("ls\nsudo ls", RISKY),
	bash("echo `sudo ls`", RISKY),
	bash("(sudo ls)", RISKY),
	bash("{ sudo ls; }", RISKY),
	bash('sh -c "sudo ls"', RISKY),
	bash("zsh -c 'sudo ls'", RISKY),
	bash("fish -c 'sudo ls'", RISKY),
	bash("bash -lc 'sudo ls'", RISKY),
	bash("ls 2>&1 | grep sudo", "allow"),
	bash("cat <<'EOF' > notes.md\nrun sudo ls and git push\nEOF\nls", "allow"),
	bash("cat <<EOF > notes.md\nnotes\nEOF\nsudo ls", RISKY),

	bash("git reset --hard HEAD~1", RISKY),
	bash("git reset --soft HEAD~1", "allow"),
	bash("git clean -fdx", RISKY),
	bash("git clean -nd", "allow"),
	bash("git checkout -- file.txt", RISKY),
	bash("git checkout .", RISKY),
	bash("git restore -SW f", RISKY),
	bash("git restore -S f", "allow"),
	bash("git stash drop", RISKY),
	bash("git stash clear", RISKY),
	bash("git stash list", "allow"),
	bash("git branch -D topic", RISKY),
	bash("git branch --delete --force topic", RISKY),
	bash("git branch -d topic", "allow"),
	bash("git push --dry-run", RISKY),
	bash("git push -u origin fix/topic", CHILD_ONLY),
	bash("git push origin fix/topic", CHILD_ONLY),
	bash("git push --set-upstream origin feature", CHILD_ONLY),
	bash("git push origin HEAD:fix/topic", CHILD_ONLY),
	bash("git push origin fix/topic:fix/topic", CHILD_ONLY),
	bash("git push origin refs/heads/fix/topic", CHILD_ONLY),
	bash("git -C /x push origin fix/topic", CHILD_ONLY),
	bash("git push --dry-run origin fix/topic", CHILD_ONLY),
	bash("git push origin -u fix/topic", CHILD_ONLY),
	bash("git push -o ci.skip origin fix/topic", CHILD_ONLY),
	bash("git push origin mainline", CHILD_ONLY),
	bash("git push origin main", RISKY),
	bash("git push origin master", RISKY),
	bash("git push origin HEAD:main", RISKY),
	bash("git push origin fix/topic:main", RISKY),
	bash("git push origin refs/heads/main", RISKY),
	bash("git push origin HEAD:refs/heads/main", RISKY),
	bash("git push origin fix/topic main", RISKY),
	bash("git push origin", RISKY),
	bash("git push origin HEAD", RISKY),
	bash("git push -u origin HEAD", RISKY),
	bash("git push origin @", RISKY),
	bash("git push --force origin fix/topic", RISKY),
	bash("git push -f origin fix/topic", RISKY),
	bash("git push -fu origin fix/topic", RISKY),
	bash("git push --force-with-lease origin fix/topic", RISKY),
	bash("git push --force-with-lease=fix/topic origin fix/topic", RISKY),
	bash("git push origin +fix/topic", RISKY),
	bash("git push origin :fix/topic", RISKY),
	bash("git push origin --delete fix/topic", RISKY),
	bash("git push -d origin fix/topic", RISKY),
	bash("git push --all origin", RISKY),
	bash("git push --mirror origin", RISKY),
	bash("git push --tags origin", RISKY),
	bash("git push --follow-tags origin fix/topic", RISKY),
	bash("git push origin tag v1.0.0", RISKY),
	bash("git push origin refs/tags/v1.0.0", RISKY),
	bash("git push origin HEAD:refs/for/main", CHILD_ONLY),
	bash("git push origin HEAD:refs/for/main%topic=x,wip", CHILD_ONLY),
	bash("git push origin fix/topic:refs/for/main", CHILD_ONLY),
	bash("git push origin HEAD:refs/for/fix/topic", CHILD_ONLY),
	bash("git push origin +HEAD:refs/for/main", RISKY),
	bash("git push --force origin HEAD:refs/for/main", RISKY),
	bash("git push origin HEAD:refs/for/", RISKY),
	bash("git push origin \"HEAD:refs/for/$branch\"", RISKY),
	bash("git push origin HEAD:refs/changes/90", RISKY),
	bash("git push origin HEAD:refs/meta/config", RISKY),
	bash("git push origin HEAD:refs/for/main fix/topic:main", RISKY),
	bash("git review", CHILD_ONLY),
	bash("git review main", CHILD_ONLY),
	bash("git review -t topic", CHILD_ONLY),
	bash("git review -R -y", CHILD_ONLY),
	bash("git review -s", CHILD_ONLY),
	bash("git review -d 90", CHILD_ONLY),
	bash("git review --download=90", CHILD_ONLY),
	bash("git review -x 90", CHILD_ONLY),
	bash("git review -X 90", CHILD_ONLY),
	bash("git review -N 90", CHILD_ONLY),
	bash("git review -m 90,1-2", CHILD_ONLY),
	bash("git -c core.pager=cat review", CHILD_ONLY),
	bash("git-review", CHILD_ONLY),
	bash("git-review -d 90", CHILD_ONLY),
	bash("git review -l", "allow"),
	bash("git review --list", "allow"),
	bash("git review -ll", "allow"),
	bash("git review --version", "allow"),
	bash("git review -h", "allow"),
	bash("git-review -l", "allow"),
	bash("git review -l -d 90", CHILD_ONLY),
	bash("git review -d 90 -l", CHILD_ONLY),
	bash("git review -tl", CHILD_ONLY),
	bash("git review -Rl", CHILD_ONLY),
	bash("git review -lll", "allow"),
	bash("git review --help", "allow"),
	bash("git push origin \"$branch\"", RISKY),
	bash("git push origin \"$(git branch --show-current)\"", RISKY),
	bash("git push origin \"refs/heads/$(git branch --show-current)\"", RISKY),
	bash("git push origin \"HEAD:refs/heads/$(git branch --show-current)\"", RISKY),
	bash(`cd ${SCRATCH} && git push origin fix/topic`, "block", ["reviewer"], SCRATCH),
	bash("git -c core.pager=cat push", RISKY),
	bash("git commit --amend --no-edit", RISKY),
	bash("git rebase main", RISKY),
	bash("git filter-branch --tree-filter x", RISKY),
	bash("git filter-repo --path x", RISKY),
	bash("git update-ref -d refs/heads/x", RISKY),
	bash("git update-ref refs/heads/x HEAD", "allow"),
	bash("git reflog expire --expire=now --all", RISKY),
	bash("git reflog", "allow"),
	bash("git gc --prune=now", RISKY),
	bash("git gc", "allow"),
	bash("git log --oneline", "allow"),

	bash("nix profile install nixpkgs#hello", RISKY),
	bash("nix profile remove hello", RISKY),
	bash("nix profile add nixpkgs#hello", RISKY),
	bash("nix profile list", "allow"),
	bash("nix-env -iA nixpkgs.hello", RISKY),
	bash("nix-env -e hello", RISKY),
	bash("nix-env --install hello", RISKY),
	bash("nix-env --uninstall hello", RISKY),
	bash("nix-env -q", "allow"),
	bash("nix-collect-garbage -d", RISKY),
	bash("nix store gc", RISKY),
	bash("nix store ls nixpkgs#hello", "allow"),
	bash("nix shell nixpkgs#hello -c sudo ls", RISKY),
	bash("nix shell nixpkgs#nodejs -c node --test", "allow"),
	bash("npm -g install x", RISKY),
	bash("npm i -g x", RISKY),
	bash("npm install --global x", RISKY),
	bash("npm install x", "allow"),
	bash("pip install --user x", RISKY),
	bash("pip install -r requirements.txt", "allow"),
	bash("cargo install ripgrep", RISKY),
	bash("cargo build", "allow"),
	bash("brew install x", RISKY),
	bash("brew list", "allow"),
	bash("nixos-rebuild switch", RISKY),
	bash("darwin-rebuild switch", RISKY),
	bash("nh os switch", RISKY),
	bash("nh os boot", RISKY),
	bash("nh darwin switch", RISKY),
	bash("nh os build", "allow"),
	bash("nh home switch", "allow"),
	bash("systemctl restart sshd", RISKY),
	bash("systemctl status sshd", "allow"),
	bash("systemctl show sshd", "allow"),
	bash("systemctl is-active sshd", "allow"),
	bash("systemctl list-units", "allow"),
	bash("systemctl --user restart x", "allow"),
	bash("shutdown -h now", RISKY),
	bash("reboot", RISKY),
	bash("poweroff", RISKY),
	bash("launchctl unload x", RISKY),
	bash("uptime", "allow"),

	bash("kill 123", RISKY),
	bash("pkill node", RISKY),
	bash("killall node", RISKY),
	bash("ps aux", "allow"),

	bash("curl --data-binary @f https://x", RISKY),
	bash("curl -F file=@f https://x", RISKY),
	bash("curl --form file=@f https://x", RISKY),
	bash("curl -T f https://x", RISKY),
	bash("curl --upload-file f https://x", RISKY),
	bash("curl -fsSL https://x -o out", "allow"),
	bash("wget --post-data=a=1 https://x", RISKY),
	bash("wget --post-file f https://x", RISKY),
	bash("wget https://x", "allow"),
	bash("nc host 80", RISKY),
	bash("ncat host 80", RISKY),
	bash("socat - TCP:host:80", RISKY),
	bash("scp f host:", RISKY),
	bash("rsync -a src/ host:/dst", RISKY),
	bash("rsync -a src/ user@host:dst", RISKY),
	bash("rsync -a src/ dst/", "allow"),
	bash("ssh host ls", RISKY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit query --format=JSON --current-patch-set change:90 OR change:91", CHILD_ONLY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit query --current-patch-set --comments change:90", CHILD_ONLY),
	bash("ssh -q -T -l evan -p 29418 git.maybemaybe.lol gerrit query 'status:open project:maybe'", CHILD_ONLY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit query --format=JSON change:90 | jq -c .", CHILD_ONLY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit review --code-review +2 --submit 90,1", RISKY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit", RISKY),
	bash("ssh -p 29418 evan@git.maybemaybe.lol gerrit query", CHILD_ONLY),
	bash("ssh git.maybemaybe.lol 'gerrit query x; rm -rf ~'", RISKY),
	bash("ssh git.maybemaybe.lol gerrit query 'x; rm -rf ~'", RISKY),
	bash("ssh git.maybemaybe.lol gerrit query 'x && touch y'", RISKY),
	bash("ssh git.maybemaybe.lol gerrit query \"\\$(id)\"", RISKY),
	bash("ssh -o ProxyCommand=sh git.maybemaybe.lol gerrit query x", RISKY),
	bash("ssh -p29418 git.maybemaybe.lol gerrit query x", RISKY),
	bash("ssh -qT git.maybemaybe.lol gerrit query x", RISKY),
	bash("ssh -p 29418x git.maybemaybe.lol gerrit query x", RISKY),
	bash("ssh -i ~/.ssh/other git.maybemaybe.lol gerrit query x", RISKY),
	bash("ssh ssh://git.maybemaybe.lol:29418 gerrit query x", RISKY),
	bash("ssh h gerrit query \"$(printf %s ';rm -rf ~')\"", RISKY),
	bash("ssh h gerrit query `printf ';rm'`", RISKY),
	bash("ssh h gerrit query $(echo x)", RISKY),
	bash("ssh h gerrit query \"$(echo x)\"", RISKY),
	bash("ssh -l -o h gerrit query x", RISKY),
	bash("ssh h gerrit query *", RISKY),
	bash("ssh h gerrit query change:9?", RISKY),
	bash("ssh h gerrit query [ab]", RISKY),
	bash("ssh h gerrit query \"$HOME\"", RISKY),
	bash("ssh git.maybemaybe.lol ls", RISKY),
	bash("ssh git.maybemaybe.lol", RISKY),
	bash("scp -O -p -P 29418 evan@git.maybemaybe.lol:hooks/commit-msg .git/hooks/", RISKY),
	bash("ssh-keygen -l -f key.pub", "allow"),

	tool("write", "/etc/hosts", RISKY),
	tool("edit", "/etcetera/x", "allow"),
	tool("write", "~/.ssh/config", RISKY),
	tool("write", "~/.pi/agent/settings.json", RISKY),
	tool("write", "/home/tester/.pi/plans/x/spec.md", CHILD_ONLY),
	tool("write", `${SCRATCH}/out.txt`, "allow", ["reviewer"], SCRATCH),
	tool("edit", "/home/tester/.pi/plans/x/review-1.md", "allow", ["main"]),

	bash("echo x > /etc/motd", RISKY),
	bash("> /etc/motd", RISKY),
	bash("FOO=1 > /etc/motd", RISKY),
	bash("tee -a ~/.bashrc", RISKY),
	bash("cp a ~/.pi/agent/auth.json", RISKY),
	bash("cd /etc && echo x > motd", RISKY),
	bash("cd /etc && cp a motd", RISKY),
	bash("cd $(pwd) && echo x > out", "allow"),
	bash("nix flake check > check.log 2>&1", "allow"),
	bash("echo x > /tmp/log", "allow"),
	bash("echo x > ~/.cache/log", "allow"),
	bash("echo x > ~/.local/state/log", "allow"),
	bash(`cd ${SCRATCH} && echo x > out.txt`, "allow", ["reviewer"], SCRATCH),
	bash(`cp f ${SCRATCH}/out`, "allow", ["reviewer"], SCRATCH),
	bash("echo note >> ~/.pi/plans/--repo--/feat/status.md", CHILD_ONLY),
	bash("curl -fsSL https://example.com -o /tmp/d", "allow"),
	bash("curl --output=/tmp/d https://example.com", "allow"),
	bash("wget -O /tmp/d https://example.com", "allow"),
	bash("sed -i s/a/b/ ~/.bashrc", RISKY),
	bash("sed -i s/a/b/ src/a.ts", "allow"),
	bash("sed -i.bak s/a/b/ src/a.ts", "allow"),
	bash("sed s/a/b/ ~/.bashrc", "allow"),
	bash("cp -t /tmp a b", "allow"),
	bash("cp --target-directory=/tmp a b", "allow"),
	bash("cp a ~/.ssh/id_ed25519", "block"),
	bash("mv a /var/tmp/b", RISKY),
	bash("ln -s a /usr/local/bin/b", RISKY),
	bash("install -m 644 a /etc/b", RISKY),
	tool("edit", ".git/config", RISKY),
	tool("edit", "repo/.git/hooks/pre-commit", RISKY),
	tool("edit", ".github/workflows/ci.yml", "allow"),
	tool("write", ".env.local", RISKY),
	tool("write", ".env.sample", "allow"),
	tool("write", ".env.template", "allow"),
	tool("edit", ".envrc", "allow"),
	tool("write", "src/main.ts", "allow"),
	tool("read", "/etc/hosts", "allow"),

	bash("git commit -am x", CHILD_ONLY),
	bash("git merge topic", CHILD_ONLY),
	bash("git switch topic", CHILD_ONLY),
	bash("git checkout topic", CHILD_ONLY),
	bash("git checkout -b topic", CHILD_ONLY),
	bash("git cherry-pick abc", CHILD_ONLY),
	bash("git tag v1", CHILD_ONLY),
	bash("git worktree add x", CHILD_ONLY),
	bash("git diff --stat", "allow"),
	tool("read", ".env", RISKY),
	tool("read", "config/.env.production", RISKY),
	tool("read", ".env.example", "allow"),
	tool("grep", ".env", RISKY),
	tool("read", "src/env.ts", "allow"),

	bash(`git -C ${SCRATCH} reset --hard`, "allow", ["reviewer"], SCRATCH),
	bash(`git -C ${SCRATCH} clean -fd`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git restore f`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git stash drop`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git apply x.patch`, "allow", ["reviewer"], SCRATCH),
	bash(`git -C ${SCRATCH} reset --hard`, "block", ["worker"], SCRATCH),
	bash(`git -C ${SCRATCH} reset --hard`, "block", ["reviewer"]),
	bash(`cd ${SCRATCH} && git push`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && sudo ls`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && git commit -am x`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && cat /run/agenix/x`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && rm -rf build`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && rm -rf out`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && rm -rf /`, "block", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && find . -delete`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && find -maxdepth 2 . -delete`, "allow", ["reviewer"], SCRATCH),
	bash(`cd ${SCRATCH} && find $FOO -delete`, "block", ["reviewer"], SCRATCH),

	tool("codemode", undefined, "allow"),
	bash("", "allow"),
];

function expectedFor(expected: Expected, role: Role): Action {
	if (typeof expected === "string") return expected;
	return role === "main" ? expected.main : expected.children;
}

for (const item of cases) {
	for (const role of item.roles ?? ROLES) {
		const label = item.tool === "bash" ? JSON.stringify(item.input.command) : `${item.tool} ${JSON.stringify(item.input.path)}`;
		const expected = expectedFor(item.expected, role);
		test(`classify_${role}_${label}_${expected}`, () => {
			const options: ClassifyOptions = { home: HOME, scratch: item.scratch, cwd: "/home/tester/project" };
			const decision = classify(item.tool, item.input, role, options);
			assert.equal(decision.action, expected, `reason: ${decision.reason ?? "none"}`);
			if (expected !== "allow") assert.ok(decision.reason, "a non-allow decision carries a reason");
		});
	}
}

test("classify_relativeGitPathWithoutCwd_blocksWrite", () => {
	const decision = classify("write", { path: ".git/config" }, "worker", { home: HOME });
	assert.equal(decision.action, "block");
});

test("classify_workerWithoutScratch_blocksScratchPathDelete", () => {
	const options: ClassifyOptions = { home: HOME, cwd: "/home/tester/project" };
	assert.equal(classify("bash", { command: `rm -rf ${SCRATCH}/out` }, "worker", options).action, "block");
	assert.equal(classify("bash", { command: `find ${SCRATCH} -delete` }, "worker", options).action, "block");
});

test("classify_absoluteInRepoDelete_allows", () => {
	const options: ClassifyOptions = { home: HOME, cwd: "/home/tester/project" };
	assert.equal(classify("bash", { command: "rm -rf /home/tester/project/build" }, "worker", options).action, "allow");
});

test("classify_rmRecursiveWithoutCwd_blocks", () => {
	assert.equal(classify("bash", { command: "rm -rf build" }, "worker", { home: HOME }).action, "block");
});

test("bashTimeout_childOmitted_defaults", () => {
	for (const role of ["worker", "reviewer", "oracle"] as const) {
		assert.equal(bashTimeout(role, undefined), DEFAULT_BASH_TIMEOUT_SECONDS);
		assert.equal(bashTimeout(role, null), DEFAULT_BASH_TIMEOUT_SECONDS);
		assert.equal(bashTimeout(role, 0), DEFAULT_BASH_TIMEOUT_SECONDS);
		assert.equal(bashTimeout(role, "60"), DEFAULT_BASH_TIMEOUT_SECONDS);
	}
	assert.equal(DEFAULT_BASH_TIMEOUT_SECONDS, 600);
});

test("bashTimeout_childRequested_clampsToMaximum", () => {
	for (const role of ["worker", "reviewer", "oracle"] as const) {
		assert.equal(bashTimeout(role, 60), undefined);
		assert.equal(bashTimeout(role, 1800), undefined);
		assert.equal(bashTimeout(role, 5000), MAX_BASH_TIMEOUT_SECONDS);
	}
	assert.equal(MAX_BASH_TIMEOUT_SECONDS, 1800);
});

test("bashTimeout_main_neverChanged", () => {
	assert.equal(bashTimeout("main", undefined), undefined);
	assert.equal(bashTimeout("main", 5000), undefined);
});

test("classify_reviewPushByWorker_reasonNamesReview", () => {
	const decision = classify("bash", { command: "git push origin HEAD:refs/for/main" }, "worker", { home: HOME });
	assert.equal(decision.action, "block");
	assert.equal(decision.reason, "git push sends a change for review");
});

test("classify_forcedReviewPushByMain_reasonNamesForceNotTags", () => {
	const decision = classify("bash", { command: "git push origin +HEAD:refs/for/main" }, "main", { home: HOME });
	assert.ok(decision.reason?.includes("git push --force overwrites remote history"));
	assert.ok(!decision.reason?.includes("tags"));
});

test("classify_reviewByWorker_reasonNamesReview", () => {
	const decision = classify("bash", { command: "git review" }, "worker", { home: HOME });
	assert.equal(decision.action, "block");
	assert.equal(decision.reason, "git review sends changes for review");
});

test("classify_reviewDownloadByWorker_reasonNamesBranches", () => {
	const decision = classify("bash", { command: "git review -d 90" }, "worker", { home: HOME });
	assert.equal(decision.action, "block");
	assert.equal(decision.reason, "git review changes branches");
});

test("classify_gerritQueryByWorker_reasonNamesQuery", () => {
	const command = "ssh -p 29418 evan@git.maybemaybe.lol gerrit query --format=JSON --current-patch-set change:90 OR change:91";
	const decision = classify("bash", { command }, "worker", { home: HOME });
	assert.equal(decision.action, "block");
	assert.equal(decision.reason, "ssh runs a Gerrit query");
});

test("classify_gerritReviewSubmitByMain_confirmsAsNetworkConnection", () => {
	const command = "ssh -p 29418 evan@git.maybemaybe.lol gerrit review --code-review +2 --submit 90,1";
	const decision = classify("bash", { command }, "main", { home: HOME });
	assert.equal(decision.action, "confirm");
	assert.equal(decision.reason, "ssh opens a network connection");
});
