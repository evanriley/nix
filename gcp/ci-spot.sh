#!/usr/bin/env bash
set -euo pipefail

region=us-central1
network=maybe-ci
subnet=maybe-ci-us-central1
subnet_range=10.64.0.0/24
role=maybeCiSpot
account=maybe-ci-spot
permissions=(
  compute.disks.create
  compute.images.useReadOnly
  compute.instances.create
  compute.instances.delete
  compute.instances.get
  compute.instances.getGuestAttributes
  compute.instances.list
  compute.instances.setLabels
  compute.instances.setMetadata
  compute.instances.setTags
  compute.subnetworks.use
  compute.subnetworks.useExternalIp
  compute.zoneOperations.get
)

project=$(gcloud config get-value project)
if [ -z "$project" ]; then
  echo "No gcloud project is set; expected the project that runs the spot builders. Run gcloud config set project <project>" >&2
  exit 1
fi
account_email=$account@$project.iam.gserviceaccount.com
role_name=projects/$project/roles/$role
flake_dir=$(cd "$(dirname "$0")/.." && pwd)
key_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcp-ci-key.json

exists() {
  "$@" >/dev/null 2>&1
}

echo "--- project $project"
gcloud services enable compute.googleapis.com --project="$project"

echo "--- network $network"
if ! exists gcloud compute networks describe "$network" --project="$project"; then
  gcloud compute networks create "$network" --project="$project" \
    --subnet-mode=custom
fi
if ! exists gcloud compute networks subnets describe "$subnet" \
  --project="$project" --region="$region"; then
  gcloud compute networks subnets create "$subnet" --project="$project" \
    --network="$network" --region="$region" --range="$subnet_range"
fi

echo "--- firewall"
firewall_rule() {
  local name=$1 direction=$2 action=$3 rules=$4 priority=$5
  shift 5
  if exists gcloud compute firewall-rules describe "$name" --project="$project"; then
    gcloud compute firewall-rules update "$name" --project="$project" \
      --rules="$rules" --priority="$priority" "$@"
  else
    gcloud compute firewall-rules create "$name" --project="$project" \
      --network="$network" --direction="$direction" --action="$action" \
      --rules="$rules" --priority="$priority" "$@"
  fi
}
firewall_rule maybe-ci-allow-web-egress EGRESS ALLOW tcp:80,tcp:443 1000 \
  --destination-ranges=0.0.0.0/0
firewall_rule maybe-ci-deny-egress EGRESS DENY all 65535 \
  --destination-ranges=0.0.0.0/0
firewall_rule maybe-ci-allow-builder-ssh INGRESS ALLOW tcp:22 1000 \
  --source-ranges=147.135.1.187/32 --target-tags=ci-remote-builder

echo "--- role $role"
role_flags=(
  --title="maybe CI spot builders"
  --description="Launch, inspect and delete maybe CI spot builders"
  --stage=GA
  --permissions="$(
    IFS=,
    echo "${permissions[*]}"
  )"
)
role_state=$(gcloud iam roles describe "$role" --project="$project" \
  --format='value(deleted)' 2>/dev/null) || role_state=missing
if [ "$role_state" = missing ]; then
  gcloud iam roles create "$role" --project="$project" --quiet "${role_flags[@]}"
else
  if [ "$role_state" = True ]; then
    gcloud iam roles undelete "$role" --project="$project"
  fi
  gcloud iam roles update "$role" --project="$project" --quiet "${role_flags[@]}"
fi

echo "--- service account $account"
if ! exists gcloud iam service-accounts describe "$account_email" \
  --project="$project"; then
  gcloud iam service-accounts create "$account" --project="$project" \
    --display-name="maybe CI spot builders"
fi
for attempt in $(seq 12); do
  if gcloud projects add-iam-policy-binding "$project" \
    --member="serviceAccount:$account_email" --role="$role_name" \
    --condition=None --format=none; then
    break
  fi
  if [ "$attempt" -eq 12 ]; then
    echo "Binding $role to $account_email failed 12 times; expected the new service account to become visible to IAM within 2 min. Re-run this script." >&2
    exit 1
  fi
  echo "Retrying the role binding in 10 s; a new service account takes a moment to reach IAM" >&2
  sleep 10
done

cat <<EOF

Done. Create a key, encrypt it for blaziken and destroy the plaintext:

  nix shell nixpkgs#google-cloud-sdk -c gcloud iam service-accounts keys create $key_file --iam-account=$account_email --project=$project
  cd $flake_dir/secrets
  nix develop $flake_dir -c agenix -e blaziken/gcp-ci-key.age < $key_file
  shred -u $key_file

Then commit nix/secrets/blaziken/gcp-ci-key.age and deploy blaziken.
EOF
