owner=evanriley

usage() {
  echo "usage: new-project <name> <template> <description> [--mirror]" >&2
  exit 2
}

fail() {
  echo "$*" >&2
  exit 2
}

mirror=
args=()
for arg in "$@"; do
  case "$arg" in
    --mirror) mirror=1 ;;
    *) args+=("$arg") ;;
  esac
done
[ ${#args[@]} -eq 3 ] || usage
name=${args[0]}
template=${args[1]}
description=${args[2]}

root=$(git rev-parse --show-toplevel 2>/dev/null) \
  || fail "Not inside a git repository; expected the maybe monorepo. Run from inside ~/maybe."
[ -f "$root/projects.json" ] \
  || fail "No projects.json in $root; expected the maybe monorepo root. Run from inside ~/maybe."
cd "$root"

[[ $name =~ ^[a-z][a-z0-9]*$ ]] \
  || fail "Invalid name '$name'; expected lowercase letters and digits starting with a letter. Pick another name."
[ ! -e "$root/$name" ] \
  || fail "$root/$name already exists; expected a new project name. Pick another name."
if jq -e --arg name "$name" 'any(.[]; .name == $name)' projects.json >/dev/null; then
  fail "'$name' is already in projects.json; expected a new project name. Pick another name."
fi

templates=$(nix eval --json "$root/nix#templates" --apply builtins.attrNames)
available=$(jq -r 'join(", ")' <<<"$templates")
jq -e --arg template "$template" 'index($template) != null' <<<"$templates" >/dev/null \
  || fail "Unknown template '$template'; expected one of: $available. Pick one of them."

[ -n "${description//[[:space:]]/}" ] \
  || fail "Empty description; expected one line describing the project. Pass it as the third argument."
case "$description" in
  *$'\n'* | *$'\r'*) fail "Description spans several lines; expected one line. Shorten it." ;;
  *"|"*) fail "Description contains '|'; it would break the README table. Remove it." ;;
esac

[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || fail "Working tree has uncommitted changes; expected a clean tree. Commit or stash them."

key_file="nix/secrets/blaziken/$name-mirror-key.age"
if [ -n "$mirror" ]; then
  [ ! -e "$key_file" ] \
    || fail "$key_file already exists; expected no key for a new project. Remove it or pick another name."
  gh auth status >/dev/null 2>&1 \
    || fail "gh is not authenticated; --mirror creates a GitHub repository. Run: gh auth login"
  if gh repo view "$owner/$name" >/dev/null 2>&1; then
    fail "GitHub repository $owner/$name already exists; expected none. Pick another name or drop --mirror."
  fi
fi

started=
repo_created=
tmp=

rollback() {
  echo "Failed; rolling back." >&2
  cd "$root"
  rm -rf "${root:?}/${name:?}"
  git reset -q -- "$name" projects.json AGENTS.md README.md || true
  if [ -n "$mirror" ]; then
    rm -f "${root:?}/${key_file:?}"
    git reset -q -- "$key_file" || true
  fi
  git checkout -q -- projects.json AGENTS.md README.md || true
  if [ -n "$repo_created" ]; then
    echo "GitHub repository $owner/$name was created and is left in place. Delete it with:" >&2
    echo "  gh repo delete $owner/$name --yes" >&2
  fi
}

cleanup() {
  local status=$?
  [ -z "$tmp" ] || rm -rf "$tmp"
  if [ "$status" -ne 0 ] && [ -n "$started" ]; then
    rollback
    exit 1
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

insert_before() {
  local file=$1 pattern=$2 line=$3 tmpfile
  tmpfile=$(mktemp)
  if ! LINE=$line awk -v pattern="$pattern" '
    !done && $0 ~ pattern { print ENVIRON["LINE"]; done = 1 }
    { print }
    END { exit !done }
  ' "$file" >"$tmpfile"; then
    rm -f "$tmpfile"
    echo "No line matching $pattern in $file; expected the monorepo layout." >&2
    return 1
  fi
  cat "$tmpfile" >"$file"
  rm -f "$tmpfile"
}

add_layout_row() {
  local file=$1 dir=$2 text=$3
  local lines=() cells1=() cells2=() rows=() line i dash1 dash2
  local start=-1 end insert_at=-1 width1=0 width2=0
  mapfile -t lines <"$file"
  for i in "${!lines[@]}"; do
    if [ "${lines[$i]}" = "## Layout" ]; then
      start=$((i + 2))
      break
    fi
  done
  if [ "$start" -lt 0 ]; then
    echo "No '## Layout' section in $file." >&2
    return 1
  fi
  end=$start
  while [ "${lines[$end]:0:1}" = "|" ]; do
    end=$((end + 1))
  done
  for ((i = start; i < end; i++)); do
    line=${lines[$i]}
    line=${line#| }
    line=${line% |}
    cells1+=("${line%% | *}")
    cells2+=("${line#* | }")
    if [ "${line%% | *}" = "\`.buildkite/\`" ]; then
      insert_at=$((${#cells1[@]} - 1))
    fi
  done
  if [ "$insert_at" -lt 0 ]; then
    echo "No .buildkite/ row in the $file Layout table." >&2
    return 1
  fi
  cells1=("${cells1[@]:0:insert_at}" "\`$dir/\`" "${cells1[@]:insert_at}")
  cells2=("${cells2[@]:0:insert_at}" "$text" "${cells2[@]:insert_at}")
  for i in "${!cells1[@]}"; do
    if [ "$i" -ne 1 ]; then
      [ "${#cells1[$i]}" -le "$width1" ] || width1=${#cells1[$i]}
      [ "${#cells2[$i]}" -le "$width2" ] || width2=${#cells2[$i]}
    fi
  done
  dash1=$(printf '%*s' "$width1" '' | tr ' ' '-')
  dash2=$(printf '%*s' "$width2" '' | tr ' ' '-')
  for i in "${!cells1[@]}"; do
    if [ "$i" -eq 1 ]; then
      rows+=("| $dash1 | $dash2 |")
    else
      rows+=("$(printf '| %-*s | %-*s |' "$width1" "${cells1[$i]}" "$width2" "${cells2[$i]}")")
    fi
  done
  {
    printf '%s\n' "${lines[@]:0:start}"
    printf '%s\n' "${rows[@]}"
    printf '%s\n' "${lines[@]:end}"
  } >"$file"
}

add_mirror_line() {
  local file=$1 line=$2
  local lines=() i start=-1 last=-1
  mapfile -t lines <"$file"
  for i in "${!lines[@]}"; do
    if [ "${lines[$i]}" = "## Mirrors" ]; then
      start=$i
      break
    fi
  done
  if [ "$start" -lt 0 ]; then
    echo "No '## Mirrors' section in $file." >&2
    return 1
  fi
  for ((i = start + 1; i < ${#lines[@]}; i++)); do
    case "${lines[$i]}" in
      "- "*) last=$i ;;
      "## "*) break ;;
    esac
  done
  if [ "$last" -lt 0 ]; then
    echo "No mirror bullets in $file." >&2
    return 1
  fi
  {
    printf '%s\n' "${lines[@]:0:last+1}"
    printf '%s\n' "$line"
    printf '%s\n' "${lines[@]:last+1}"
  } >"$file"
}

rename_flake() {
  sed -i \
    -e "s/\"app-source\"/\"$name-source\"/" \
    -e "s/\"app-fmt\"/\"$name-fmt\"/g" \
    -e "s/\"app-test\"/\"$name-test\"/" \
    -e "s/\"app: fmt\"/\"$name: fmt\"/" \
    -e "s/\"app: test\"/\"$name: test\"/" \
    -e "s#\"app/ci.sh #\"$name/ci.sh #" \
    flake.nix
}

scaffold() {
  mkdir "$name"
  cd "$name"
  init_log=$(nix flake init -t "$root/nix#$template" 2>&1) || {
    echo "$init_log" >&2
    return 1
  }
  chmod +x ci.sh
  rename_flake
  case "$template" in
    rust)
      sed -i "s/^name = \"app\"\$/name = \"$name\"/" Cargo.toml Cargo.lock
      ;;
    zig)
      sed -i "s/^\( *\)\.name = \"app\",\$/\1.name = \"$name\",/" build.zig
      sed -i "s/^\( *\)pname = \"app\";\$/\1pname = \"$name\";/" flake.nix
      ;;
    ocaml)
      sed -i "s/^ (name app))\$/ (name $name))/" dune-project
      sed -i "s/(public_name app))\$/(public_name $name))/" bin/dune
      sed -i "s/^\( *\)pname = \"app\";\$/\1pname = \"$name\";/" flake.nix
      ;;
    gleam)
      sed -i "s/^name = \"app\"\$/name = \"$name\"/" gleam.toml
      mv src/app.gleam "src/$name.gleam"
      mv test/app_test.gleam "test/${name}_test.gleam"
      ;;
    python)
      sed -i \
        -e "s/^name = \"app\"\$/name = \"$name\"/" \
        -e "s/^app = \"app:main\"\$/$name = \"$name:main\"/" \
        pyproject.toml
      sed -i "s/^name = \"app\"\$/name = \"$name\"/" uv.lock
      mv src/app "src/$name"
      sed -i -e "s/\"app-env\"/\"$name-env\"/" -e "s/\"app-dev-env\"/\"$name-dev-env\"/" flake.nix
      ;;
    clojure)
      mv src/app "src/$name"
      sed -i "s/^(ns app\\.core\$/(ns $name.core/" "src/$name/core.clj"
      sed -i \
        -e "s#name = \"app/app\";#name = \"$name/$name\";#" \
        -e "s/main-ns = \"app\\.core\";/main-ns = \"$name.core\";/" \
        flake.nix
      ;;
    *)
      echo "No rename rules for template '$template'; expected one of: $available. Add a case to new-project." >&2
      return 1
      ;;
  esac
  cd "$root"
  git add "$name"
  (cd "$name" && nix flake lock)
  git add "$name"
}

register() {
  local entry="  { \"name\": \"$name\" },"
  if [ -n "$mirror" ]; then
    entry="  { \"name\": \"$name\", \"mirror\": \"git@github.com:$owner/$name.git\" },"
  fi
  insert_before projects.json '^  \\{ "name": "nix"' "$entry"
  jq -e . projects.json >/dev/null
  local summary=$description
  case "$summary" in *.) ;; *) summary+=. ;; esac
  insert_before AGENTS.md "^- \`\\\\.buildkite/\`" "- \`$name/\`: $summary"
  add_layout_row README.md "$name" "$description"
  git add projects.json AGENTS.md README.md
}

setup_mirror() {
  local recipients=() recipient_args=() recipient
  tmp=$(mktemp -d)
  ssh-keygen -q -t ed25519 -N '' -C "$name-mirror" -f "$tmp/key"
  mapfile -t recipients < <(
    nix eval --json -f "$root/nix/secrets/secrets.nix" \
      --apply "s: s.\"blaziken/$name-mirror-key.age\".publicKeys" | jq -r '.[]'
  )
  if [ ${#recipients[@]} -eq 0 ]; then
    echo "No recipients for blaziken/$name-mirror-key.age in nix/secrets/secrets.nix." >&2
    return 1
  fi
  for recipient in "${recipients[@]}"; do
    recipient_args+=(-r "$recipient")
  done
  age -e "${recipient_args[@]}" -o "$root/$key_file" "$tmp/key"
  git add "$key_file"
  add_mirror_line README.md "- \`$owner/$name\` from \`$name/\`, private."
  git add README.md
  gh repo create "$owner/$name" --private --disable-issues --disable-wiki --description "$description"
  repo_created=1
  gh repo deploy-key add "$tmp/key.pub" --allow-write --title buildkite-mirror -R "$owner/$name"
}

started=1
scaffold
register
if [ -n "$mirror" ]; then
  setup_mirror
fi

echo "Created $name/ from the $template template and staged it with projects.json, AGENTS.md and README.md."
if [ -n "$mirror" ]; then
  echo "Created $key_file and the private GitHub repository $owner/$name with a write deploy key."
fi
echo "Next:"
echo "  git commit"
echo "  git push origin HEAD:refs/for/main"
if [ -n "$mirror" ]; then
  echo "Deploy blaziken from this change before submitting it: cd nix && nix develop -c deploy .#blaziken"
fi
echo "Add a sibling input in nix/flake.nix only if nix/ should consume $name."
