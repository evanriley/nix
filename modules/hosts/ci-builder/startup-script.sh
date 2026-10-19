#!/usr/bin/env bash
set -euo pipefail

runtime_dir=/run/ci-builder
token_file=$runtime_dir/agent-token
fetched_token_file=$runtime_dir/agent-token.fetched
agent_unit=buildkite-agent-ci-builder.service
system_profile=/nix/var/nix/profiles/system
system_pattern='^/nix/store/[0-9a-df-np-sv-z]{32}-nixos-system-[0-9A-Za-z+._?=-]+$'

metadata() {
  local path=$1
  shift
  if ! curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 30 \
    --retry 10 --retry-delay 2 --retry-connrefused \
    --header 'Metadata-Flavor: Google' \
    "$@" "http://169.254.169.254/computeMetadata/v1/instance/$path"; then
    echo "Metadata request for instance/$path failed; expected the metadata server to serve it. Check the instance metadata." >&2
    return 1
  fi
}

fail_closed() {
  local status=$?
  if ((status != 0)); then
    rm -f "$fetched_token_file" "$token_file"
    systemctl stop "$agent_unit"
  fi
}
trap fail_closed EXIT

system=$(metadata attributes/ci-builder-system)
if [[ ! $system =~ $system_pattern ]]; then
  printf 'ci-builder-system is %q; expected one /nix/store/<hash>-nixos-system-* path. Set it to a published ci-builder toplevel.\n' "$system" >&2
  exit 1
fi

(umask 0377 && metadata attributes/buildkite-agent-token --output "$fetched_token_file")
if [[ ! -s $fetched_token_file ]]; then
  echo "buildkite-agent-token is empty; expected a Buildkite agent token. Set it in the instance metadata." >&2
  exit 1
fi

nix-store --realise "$system"
switch_to_configuration=$system/bin/switch-to-configuration
if [[ ! -f $switch_to_configuration || ! -x $switch_to_configuration ]]; then
  echo "$system has no executable bin/switch-to-configuration; expected a NixOS toplevel. Set ci-builder-system to a published ci-builder toplevel." >&2
  exit 1
fi
nix-env --profile "$system_profile" --set "$system"
"$switch_to_configuration" switch

mv "$fetched_token_file" "$token_file"
systemctl start "$agent_unit"
if ! systemctl is-active --quiet "$agent_unit"; then
  echo "$agent_unit is not active after start; expected it to run with the token. Check: journalctl -u $agent_unit" >&2
  exit 1
fi

metadata guest-attributes/ci-builder/ready --request PUT --data 1
