usage() {
  echo "usage: worktree <name> [<base>]" >&2
  exit 2
}

fail() {
  echo "$*" >&2
  exit 2
}

{ [ $# -eq 1 ] || [ $# -eq 2 ]; } || usage
name=$1
base=${2:-origin/main}

common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || fail "Not inside a git repository; expected the maybe monorepo. Run from inside ~/maybe or one of its worktrees."
main=$(dirname "$common_dir")
[ -f "$main/projects.json" ] \
  || fail "No projects.json in $main; expected the maybe monorepo root. Run from inside ~/maybe or one of its worktrees."

[[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] \
  || fail "Invalid name '$name'; expected lowercase letters, digits and '-' starting with a letter or digit. Pick another name."
path=$(dirname "$main")/maybe-$name
[ ! -e "$path" ] \
  || fail "$path already exists; expected a new worktree path. Pick another name or remove it with: git worktree remove $path"
if git -C "$main" show-ref --verify --quiet "refs/heads/$name"; then
  fail "Branch '$name' already exists; expected a new branch name. Pick another name or delete it with: git branch -D $name"
fi

git -C "$main" fetch -q origin main
git -C "$main" worktree add -b "$name" "$path" "$base"
(cd "$path" && nix develop "$path/nix" -c true)

echo "$path"
