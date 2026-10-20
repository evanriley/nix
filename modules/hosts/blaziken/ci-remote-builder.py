import base64
import binascii
import ipaddress
import os
import re
import signal
import sys
import traceback
import urllib.parse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from types import FrameType
from typing import TextIO

import ci_spot_poller as spot

NAME_PREFIX = "maybe-ci-remote-"
LABEL = "maybe-ci-remote"
TAG = "ci-remote-builder"
NAMESPACE = "ci-remote-builder"
USER = "builder"
SYSTEM_TYPE = "x86_64-linux"
FEATURES = "big-parallel"
LEASE_PATTERN = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
)
HOST_KEY_PATTERN = re.compile(r"ssh-ed25519 ([A-Za-z0-9+/]{68})( [!-~]+)?")
ED25519_PREFIX = b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20"
ED25519_LENGTH = len(ED25519_PREFIX) + 32
SSH_KEY_PATTERN = re.compile(r"/[!-~]+")
USAGE = "usage: ci-remote-builder lease|release <buildkite-job-id>"

RUN_DURATION = 2 * 3600
LEASE_BUDGET = 5 * 60
RELEASE_BUDGET = 90
POLL_INTERVAL = 5.0


class LeaseError(Exception):
    pass


class Interrupted(Exception):
    pass


@dataclass(frozen=True, slots=True)
class LeaseConfig:
    system_file: Path
    startup_script: str
    ssh_key: str


def required(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "")
    if not value:
        raise spot.ConfigError(
            f"{name} is not set; expected a path. The ci-remote-builder "
            "wrapper on the main agent's PATH sets it"
        )
    return value


def lease_config(env: Mapping[str, str]) -> LeaseConfig:
    startup_path = Path(required(env, "CI_REMOTE_BUILDER_STARTUP_SCRIPT"))
    try:
        startup_script = startup_path.read_text()
    except (OSError, UnicodeDecodeError) as error:
        raise spot.ConfigError(
            f"reading the startup script {startup_path} failed: {error}; "
            "expected meta.ciRemoteBuilderStartupScript"
        ) from error
    ssh_key = required(env, "CI_REMOTE_BUILDER_SSH_KEY")
    if not SSH_KEY_PATTERN.fullmatch(ssh_key):
        raise spot.ConfigError(
            f"CI_REMOTE_BUILDER_SSH_KEY is {ssh_key!r}; expected an absolute "
            "path without whitespace, because it becomes a field of the "
            "builders line"
        )
    return LeaseConfig(
        system_file=Path(required(env, "CI_REMOTE_BUILDER_SYSTEM_FILE")),
        startup_script=startup_script,
        ssh_key=ssh_key,
    )


def instance_name(lease_id: str) -> str | None:
    if not LEASE_PATTERN.fullmatch(lease_id):
        return None
    name = NAME_PREFIX + lease_id
    if len(name) > 63 or not spot.NAME_PATTERN.fullmatch(name):
        return None
    return name


def host_key_line(value: object) -> str:
    if not isinstance(value, str):
        raise LeaseError(
            f"{NAMESPACE}/host-key is missing although {NAMESPACE}/ready is "
            "set; expected the startup script to publish the host key first"
        )
    match = HOST_KEY_PATTERN.fullmatch(value)
    data = match.group(1) if match is not None else ""
    try:
        blob = base64.b64decode(data, validate=True)
    except binascii.Error:
        blob = b""
    if len(blob) != ED25519_LENGTH or not blob.startswith(ED25519_PREFIX):
        raise LeaseError(
            f"{NAMESPACE}/host-key is {value[:200]!r}; expected one line "
            "'ssh-ed25519 <base64 key>' with an optional comment without "
            "spaces. Check /etc/ssh/ssh_host_ed25519_key.pub on the image"
        )
    return f"ssh-ed25519 {data}"


def external_ip(instance: Mapping[str, object], name: str) -> str:
    raw: object = None
    interfaces = instance.get("networkInterfaces")
    if isinstance(interfaces, list) and interfaces:
        first = interfaces[0]
        configs = first.get("accessConfigs") if isinstance(first, dict) else []
        if isinstance(configs, list) and configs:
            config = configs[0]
            raw = config.get("natIP") if isinstance(config, dict) else None
    try:
        address = ipaddress.IPv4Address(raw) if isinstance(raw, str) else None
    except ValueError:
        address = None
    if address is None or str(address) != raw:
        raise LeaseError(
            f"{name} has external address {raw!r}; expected an IPv4 address "
            "in networkInterfaces[0].accessConfigs[0].natIP, because "
            "blaziken reaches the builder over it"
        )
    return str(address)


class RemoteBuilders:
    def __init__(
        self,
        client: spot.GcpClient,
        clock: spot.Clock,
        log: spot.Log,
        zones: Sequence[str],
    ) -> None:
        self._client = client
        self._clock = clock
        self._log = log
        self._zones = tuple(zones)

    def lease(
        self,
        account: spot.ServiceAccount,
        name: str,
        metadata: Mapping[str, str],
        ssh_key: str,
    ) -> str:
        deadline = self._clock.monotonic() + LEASE_BUDGET
        try:
            zone, launched = self._launch(account, name, metadata, deadline)
            return self._await_ready(
                account, name, zone, launched, ssh_key, deadline
            )
        except Exception as error:
            if isinstance(error, (LeaseError, spot.ApiError, Interrupted)):
                reason = str(error)
            else:
                reason = "unexpected error:\n" + traceback.format_exc()
            self._log(f"leasing {name} failed: {reason}")
            try:
                self.release(account, name)
            except (LeaseError, spot.ApiError) as cleanup:
                raise LeaseError(
                    f"leasing {name} failed and deleting it failed too: "
                    f"{cleanup}"
                ) from error
            raise LeaseError(
                f"leasing {name} failed; deleted any instance it created"
            ) from error

    def release(self, account: spot.ServiceAccount, name: str) -> None:
        deadline = self._clock.monotonic() + RELEASE_BUDGET
        pending = self._zones
        deleted: list[str] = []
        while True:
            failures: dict[str, str] = {}
            for zone in pending:
                url = (
                    f"{spot.COMPUTE}/projects/{account.project}/zones/{zone}/"
                    f"instances/{name}"
                )
                try:
                    self._client.request(account, "DELETE", url)
                except spot.NotFound:
                    continue
                except spot.ApiError as error:
                    failures[zone] = str(error)
                    continue
                deleted.append(zone)
                self._log(f"deleting {name} in {zone}")
            if not failures:
                if not deleted:
                    self._log(f"{name} does not exist; nothing to delete")
                return
            problems = "; ".join(
                f"{zone}: {error}" for zone, error in failures.items()
            )
            if self._clock.monotonic() + POLL_INTERVAL > deadline:
                commands = "; ".join(
                    f"gcloud compute instances delete {name} --zone={zone}"
                    for zone in failures
                )
                raise LeaseError(
                    f"deleting {name} kept failing for {RELEASE_BUDGET} s "
                    f"({problems}); expected DELETE to succeed or answer "
                    f"404. Delete it by hand: {commands}"
                )
            self._log(
                f"deleting {name} failed ({problems}); retrying in "
                f"{POLL_INTERVAL:.0f} s until it is accepted or gone"
            )
            pending = tuple(failures)
            self._clock.sleep(POLL_INTERVAL)

    def _launch(
        self,
        account: spot.ServiceAccount,
        name: str,
        metadata: Mapping[str, str],
        deadline: float,
    ) -> tuple[str, bool]:
        for shape in spot.SHAPES:
            for zone in self._zones:
                if self._clock.monotonic() >= deadline:
                    raise LeaseError(
                        f"the {LEASE_BUDGET} s lease budget ran out while "
                        "launching"
                    )
                outcome = self._insert(
                    account, name, shape, zone, metadata, deadline
                )
                if outcome is spot.Outcome.QUOTA:
                    break
                if outcome is spot.Outcome.FAILED:
                    continue
                return zone, outcome is spot.Outcome.LAUNCHED
        raise LeaseError(
            f"every shape ({', '.join(spot.SHAPES)}) failed in every zone "
            f"({', '.join(self._zones)}); expected spot capacity in one of "
            "them. Retry the job later"
        )

    def _insert(
        self,
        account: spot.ServiceAccount,
        name: str,
        shape: str,
        zone: str,
        metadata: Mapping[str, str],
        deadline: float,
    ) -> spot.Outcome:
        body = spot.instance_body(
            account,
            name,
            shape,
            zone,
            metadata,
            label=LABEL,
            run_duration=RUN_DURATION,
            tags=(TAG,),
        )
        zone_url = f"{spot.COMPUTE}/projects/{account.project}/zones/{zone}"
        try:
            operation = self._client.request(
                account, "POST", f"{zone_url}/instances", body
            )
        except spot.Unreachable as error:
            self._log(
                f"inserting {name} ({shape} in {zone}) got no answer: "
                f"{error}; waiting for it in {zone}"
            )
            return spot.Outcome.UNDETERMINED
        except spot.ApiError as error:
            return self._insert_failed(shape, zone, str(error))
        while True:
            if operation.get("status") == "DONE":
                errors = spot.operation_errors(operation)
                if errors is not None:
                    return self._insert_failed(shape, zone, errors)
                self._log(f"launched {name} ({shape} in {zone})")
                return spot.Outcome.LAUNCHED
            remaining = deadline - self._clock.monotonic()
            operation_name = operation.get("name")
            if remaining <= 0 or not (
                isinstance(operation_name, str)
                and spot.OPERATION_PATTERN.fullmatch(operation_name)
            ):
                self._log(
                    f"{name} ({shape} in {zone}) is still starting; waiting "
                    f"for it in {zone}"
                )
                return spot.Outcome.UNDETERMINED
            try:
                operation = self._client.request(
                    account,
                    "POST",
                    f"{zone_url}/operations/{operation_name}/wait",
                    timeout=min(remaining, spot.WAIT_TIMEOUT),
                )
            except spot.ApiError as error:
                self._log(
                    f"waiting for {name} ({shape} in {zone}) failed: "
                    f"{error}; waiting for the instance instead"
                )
                return spot.Outcome.UNDETERMINED

    def _insert_failed(
        self, shape: str, zone: str, error: str
    ) -> spot.Outcome:
        if spot.QUOTA_PATTERN.search(error):
            self._log(
                f"inserting {shape} in {zone} failed: {error}; the quota "
                "covers the region, so trying the next shape"
            )
            return spot.Outcome.QUOTA
        self._log(
            f"inserting {shape} in {zone} failed: {error}; trying the next "
            "zone or shape"
        )
        return spot.Outcome.FAILED

    def _await_ready(
        self,
        account: spot.ServiceAccount,
        name: str,
        zone: str,
        launched: bool,
        ssh_key: str,
        deadline: float,
    ) -> str:
        url = (
            f"{spot.COMPUTE}/projects/{account.project}/zones/{zone}/"
            f"instances/{name}"
        )
        while True:
            instance: dict[str, object] | None = None
            try:
                instance = self._client.request(account, "GET", url)
            except spot.NotFound:
                if launched:
                    raise LeaseError(
                        f"{name} in {zone} disappeared before it was ready; "
                        "spot capacity was probably reclaimed. Retry the job"
                    ) from None
            except spot.ApiError as error:
                self._log(f"reading {name} failed: {error}; retrying")
            if instance is not None:
                launched = True
                status = instance.get("status")
                if status in spot.DEAD:
                    raise LeaseError(
                        f"{name} is {status} before it set {NAMESPACE}/ready; "
                        "its startup script powers it off when setup fails, "
                        "for example when ci-builder-system is not in the "
                        "cache"
                    )
                if status == "RUNNING":
                    attributes = self._guest_attributes(account, zone, name)
                    if "ready" in attributes:
                        host_key = host_key_line(attributes.get("host-key"))
                        address = external_ip(instance, name)
                        self._log(f"{name} is ready at {address}")
                        encoded = base64.b64encode(host_key.encode()).decode()
                        return (
                            f"ssh-ng://{USER}@{address} {SYSTEM_TYPE} "
                            f"{ssh_key} 1 1 {FEATURES} {FEATURES} {encoded}"
                        )
            if self._clock.monotonic() + POLL_INTERVAL > deadline:
                raise LeaseError(
                    f"{name} did not set {NAMESPACE}/ready within "
                    f"{LEASE_BUDGET} s; expected its startup script to "
                    "switch to ci-builder-system and start sshd by then"
                )
            self._clock.sleep(POLL_INTERVAL)

    def _guest_attributes(
        self, account: spot.ServiceAccount, zone: str, name: str
    ) -> dict[str, object]:
        url = (
            f"{spot.COMPUTE}/projects/{account.project}/zones/{zone}/"
            f"instances/{name}/getGuestAttributes?"
            + urllib.parse.urlencode({"queryPath": f"{NAMESPACE}/"})
        )
        try:
            data = self._client.request(account, "GET", url)
        except spot.NotFound:
            return {}
        except spot.ApiError as error:
            self._log(
                f"reading guest attributes of {name} failed: {error}; retrying"
            )
            return {}
        value = data.get("queryValue")
        items = value.get("items") if isinstance(value, dict) else None
        attributes: dict[str, object] = {}
        for item in items if isinstance(items, list) else []:
            if isinstance(item, dict) and item.get("namespace") == NAMESPACE:
                key = item.get("key")
                if isinstance(key, str):
                    attributes[key] = item.get("value")
        return attributes


def run(
    argv: Sequence[str],
    env: Mapping[str, str],
    transport: spot.Transport,
    clock: spot.Clock,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    log = spot.Log(stderr)
    if len(argv) != 2 or argv[0] not in ("lease", "release"):
        log(f"{USAGE}; got {len(argv)} arguments {list(argv)!r}"[:500])
        return 2
    command, lease_id = argv
    name = instance_name(lease_id)
    if name is None:
        log(
            f"the lease id is {lease_id[:100]!r}; expected a Buildkite job "
            "id (a lowercase UUID). Pass $BUILDKITE_JOB_ID"
        )
        return 2

    try:
        gcp_key = Path(required(env, "GCP_KEY_PATH"))
        config = lease_config(env) if command == "lease" else None
    except spot.ConfigError as error:
        log(str(error))
        return 1

    metadata: dict[str, str] = {}
    if config is not None:
        system, state = spot.read_system(
            config.system_file, "ci-remote-builder"
        )
        if system is None:
            log(f"{state}; not leasing a remote builder")
            return 1
        log(state)
        metadata = {
            "startup-script": config.startup_script,
            "ci-builder-system": system,
            **spot.INSTANCE_METADATA,
        }

    client = spot.GcpClient(transport, clock, log)
    try:
        account = client.load_account(gcp_key)
    except spot.CredentialsError as error:
        log(str(error))
        return 1

    builders = RemoteBuilders(
        client, clock, log, spot.DEFAULT_ZONES.split(",")
    )
    try:
        if config is None:
            builders.release(account, name)
            return 0
        line = builders.lease(account, name, metadata, config.ssh_key)
    except (LeaseError, spot.ApiError, Interrupted) as error:
        log(str(error))
        return 1
    print(line, file=stdout, flush=True)
    return 0


def interrupt(signum: int, frame: FrameType | None) -> None:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    raise Interrupted(f"received {signal.Signals(signum).name}")


def main() -> None:
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    sys.exit(
        run(
            sys.argv[1:],
            os.environ,
            spot.UrllibTransport(),
            spot.SystemClock(),
            sys.stdout,
            sys.stderr,
        )
    )


if __name__ == "__main__":
    main()
