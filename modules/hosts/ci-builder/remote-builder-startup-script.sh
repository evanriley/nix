#!/usr/bin/env bash
set -euo pipefail

sshd_unit=sshd.service
host_key_file=/etc/ssh/ssh_host_ed25519_key.pub
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
    echo "Remote builder setup failed with status $status; powering off so the VM never reports ready. Read the error above." >&2
    systemctl --no-block poweroff
  fi
}
trap fail_closed EXIT

system=$(metadata attributes/ci-builder-system)
if [[ ! $system =~ $system_pattern ]]; then
  printf 'ci-builder-system is %q; expected one /nix/store/<hash>-nixos-system-* path. Set it to a published ci-remote-builder toplevel.\n' "$system" >&2
  exit 1
fi

nix-store --realise "$system"
switch_to_configuration=$system/bin/switch-to-configuration
if [[ ! -f $switch_to_configuration || ! -x $switch_to_configuration ]]; then
  echo "$system has no executable bin/switch-to-configuration; expected a NixOS toplevel. Set ci-builder-system to a published ci-remote-builder toplevel." >&2
  exit 1
fi
nix-env --profile "$system_profile" --set "$system"
"$switch_to_configuration" switch

if ! systemctl is-active --quiet "$sshd_unit"; then
  echo "$sshd_unit is not active after the switch; expected $system to run sshd. Check: journalctl -u $sshd_unit" >&2
  exit 1
fi
host_key=$(<"$host_key_file")
read -r host_key_type host_key_data _ <<<"$host_key"
served_host_key=$("$system/sw/bin/ssh-keyscan" -q -T 10 -t ed25519 127.0.0.1)
if [[ $served_host_key != "127.0.0.1 $host_key_type $host_key_data" ]]; then
  printf 'sshd serves %q; expected the key in %s. Check: journalctl -u %s\n' "$served_host_key" "$host_key_file" "$sshd_unit" >&2
  exit 1
fi

metadata guest-attributes/ci-remote-builder/host-key --request PUT --data-raw "$host_key"
metadata guest-attributes/ci-remote-builder/ready --request PUT --data 1
