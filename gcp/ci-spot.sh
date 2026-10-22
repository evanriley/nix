#!/usr/bin/env bash
set -euo pipefail

region=us-central1
network=maybe-ci
subnet=maybe-ci-us-central1
subnet_range=10.64.0.0/24
role=maybeCiSpot
account=maybe-ci-spot
cache_days=7
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
bucket=$project-maybe-ci-cache
role_name=projects/$project/roles/$role
flake_dir=$(cd "$(dirname "$0")/.." && pwd)
key_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcp-ci-key.json

exists() {
  "$@" >/dev/null 2>&1
}

retry_binding() {
  local attempt
  for attempt in $(seq 12); do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -eq 12 ]; then
      echo "Binding a role failed 12 times: $*; expected a new service account to become visible to IAM within 2 min. Re-run this script." >&2
      exit 1
    fi
    echo "Retrying the role binding in 10 s; a new service account takes a moment to reach IAM" >&2
    sleep 10
  done
}

create_service_account() {
  local name=$1 display_name=$2
  if ! exists gcloud iam service-accounts describe "$name@$project.iam.gserviceaccount.com" \
    --project="$project"; then
    gcloud iam service-accounts create "$name" --project="$project" \
      --display-name="$display_name"
  fi
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
if exists gcloud compute firewall-rules describe maybe-ci-allow-builder-ssh --project="$project"; then
  gcloud compute firewall-rules delete maybe-ci-allow-builder-ssh --project="$project" --quiet
fi

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
create_service_account "$account" "maybe CI spot builders"
retry_binding gcloud projects add-iam-policy-binding "$project" \
  --member="serviceAccount:$account_email" --role="$role_name" \
  --condition=None --format=none

echo "--- bucket gs://$bucket"
if ! exists gcloud storage buckets describe "gs://$bucket" --project="$project"; then
  gcloud storage buckets create "gs://$bucket" --project="$project" \
    --location="$region" --default-storage-class=STANDARD \
    --uniform-bucket-level-access --public-access-prevention \
    --soft-delete-duration=0
fi
lifecycle=$(mktemp)
trap 'rm -f "$lifecycle"' EXIT
printf '{"rule": [{"action": {"type": "Delete"}, "condition": {"age": %d, "matchesSuffix": [".narinfo"]}}, {"action": {"type": "Delete"}, "condition": {"age": %d, "matchesPrefix": ["nar/"]}}]}\n' \
  "$cache_days" "$cache_days" >"$lifecycle"
gcloud storage buckets update "gs://$bucket" --project="$project" \
  --public-access-prevention --clear-soft-delete --lifecycle-file="$lifecycle"
if ! exists gcloud storage objects describe "gs://$bucket/nix-cache-info" --project="$project"; then
  printf 'StoreDir: /nix/store\n' >"$lifecycle"
  gcloud storage cp --project="$project" --content-type=text/x-nix-cache-info \
    "$lifecycle" "gs://$bucket/nix-cache-info"
fi

echo "--- cache service accounts"
create_service_account maybe-ci-cache-writer "maybe CI cache writer"
create_service_account maybe-ci-cache-reader "maybe CI cache reader"
for binding in \
  maybe-ci-cache-writer:roles/storage.objectCreator \
  maybe-ci-cache-writer:roles/storage.objectViewer \
  maybe-ci-cache-reader:roles/storage.objectViewer; do
  retry_binding gcloud storage buckets add-iam-policy-binding "gs://$bucket" \
    --project="$project" --role="${binding#*:}" \
    --member="serviceAccount:${binding%%:*}@$project.iam.gserviceaccount.com" \
    --format=none
done

cat <<EOF

Done. Create a key, encrypt it for blaziken and destroy the plaintext:

  nix shell nixpkgs#google-cloud-sdk -c gcloud iam service-accounts keys create $key_file --iam-account=$account_email --project=$project
  cd $flake_dir/secrets
  nix develop $flake_dir -c agenix -e blaziken/gcp-ci-key.age < $key_file
  shred -u $key_file

For the CI cache in gs://$bucket (the store in
$flake_dir/modules/hosts/ci-builder/cache.nix names it), create an HMAC key for
each cache account:

  nix shell nixpkgs#google-cloud-sdk -c gcloud storage hmac create maybe-ci-cache-writer@$project.iam.gserviceaccount.com --project=$project
  nix shell nixpkgs#google-cloud-sdk -c gcloud storage hmac create maybe-ci-cache-reader@$project.iam.gserviceaccount.com --project=$project

Encrypt each key's access id and secret as an AWS credentials file into
secrets/blaziken/ci-cache-writer.age and ci-cache-reader.age:

  [default]
  aws_access_key_id = <accessId>
  aws_secret_access_key = <secret>

Then commit the .age files and deploy blaziken.
EOF
