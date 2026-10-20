import base64
import io
import json
import signal
import urllib.parse
from pathlib import Path
from typing import Any

import pytest

import ci_remote_builder as remote
import ci_spot_poller as spot
from test_ci_spot_poller import (
    ACCESS_TOKEN,
    C3D,
    C4D,
    EMAIL,
    KEY_ID,
    PEM,
    PROJECT,
    ZONES,
    FakeClock,
    FakeCloud,
    reply,
)

LEASE_ID = "0193a5f2-7c4e-4b8a-9f3d-2e6c1b0a9d87"
NAME = f"maybe-ci-remote-{LEASE_ID}"
SYSTEM = "/nix/store/" + "b" * 32 + "-nixos-system-ci-remote-builder-26.11"
STARTUP_SCRIPT = "#!/usr/bin/env bash\necho remote builder\n"
SSH_KEY = "/run/agenix/ci-remote-builder-key"
NAT_IP = "34.66.12.34"
ED25519_PREFIX = b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x20"
HOST_KEY_DATA = base64.b64encode(ED25519_PREFIX + bytes(range(32))).decode()
OTHER_KEY_DATA = base64.b64encode(ED25519_PREFIX + bytes(32)).decode()
HOST_KEY = f"ssh-ed25519 {HOST_KEY_DATA}"
BUILDERS_LINE = (
    f"ssh-ng://builder@{NAT_IP} x86_64-linux {SSH_KEY} 1 1 big-parallel "
    "big-parallel " + base64.b64encode(HOST_KEY.encode()).decode()
)


class FakeRemoteCloud(FakeCloud):
    def __init__(self, clock: FakeClock) -> None:
        super().__init__(clock)
        self.calls: list[tuple[str, str]] = []
        self.boots: dict[str, float] = {}
        self.boot_after: float | None = 60.0
        self.boot_status = "RUNNING"
        self.vanish = False
        self.publish = True
        self.host_key: str | None = f"{HOST_KEY} root@maybe-ci-remote"
        self.nat_ip: object = NAT_IP
        self.delete_takes = 0.0
        self.delete_error = False
        self.removing: dict[str, float] = {}
        self.interrupt_on: str | None = None

    def add(self, name: str, **options: Any) -> None:
        super().add(name, **options)
        self.boots[name] = self.clock.mono

    def request(
        self,
        method: str,
        url: str,
        headers: dict[str, str],
        body: bytes | None,
        timeout: float,
    ) -> spot.Response:
        assert timeout > 0
        self.calls.append((method, url.split("?", 1)[0]))
        if self.interrupt_on is not None and self.interrupt_on in url:
            self.interrupt_on = None
            raise remote.Interrupted("received SIGTERM")
        if url == spot.TOKEN_URI:
            return super().request(method, url, headers, body, timeout)
        assert headers["Authorization"] == f"Bearer {ACCESS_TOKEN}"
        parts = urllib.parse.urlsplit(url)
        assert f"{parts.scheme}://{parts.netloc}" == (
            "https://compute.googleapis.com"
        )
        prefix = f"/compute/v1/projects/{PROJECT}/zones/"
        assert parts.path.startswith(prefix)
        zone, *path = parts.path.removeprefix(prefix).split("/")
        assert zone in ZONES
        query = urllib.parse.parse_qs(parts.query)
        match method, path:
            case "POST", ["instances"]:
                assert body is not None
                return self._insert(zone, json.loads(body))
            case "POST", ["operations", name, "wait"]:
                assert body == b""
                return self._wait(name)
            case "GET", ["instances", name]:
                return self._get(zone, name)
            case "GET", ["instances", name, "getGuestAttributes"]:
                assert query == {"queryPath": ["ci-remote-builder/"]}
                return self._attributes(zone, name)
            case "DELETE", ["instances", name]:
                return self._remove(zone, name)
        raise AssertionError(f"unexpected {method} {url}")

    def _find(self, zone: str, name: str) -> dict[str, object] | None:
        until = self.removing.get(name)
        if until is not None and self.clock.mono >= until:
            del self.removing[name]
            del self.instances[name]
        instance = self.instances.get(name)
        if instance is None or not str(instance["zone"]).endswith(f"/{zone}"):
            return None
        started = self.boots.get(name)
        if (
            instance["status"] == "PROVISIONING"
            and started is not None
            and self.boot_after is not None
            and self.clock.mono - started >= self.boot_after
        ):
            if self.vanish:
                del self.instances[name]
                return None
            instance["status"] = self.boot_status
        return instance

    def _get(self, zone: str, name: str) -> spot.Response:
        instance = self._find(zone, name)
        if instance is None:
            return reply(404, {"error": {"message": "not found"}})
        interface = {
            "accessConfigs": [{"type": "ONE_TO_ONE_NAT", "natIP": self.nat_ip}]
        }
        return reply(200, {**instance, "networkInterfaces": [interface]})

    def _attributes(self, zone: str, name: str) -> spot.Response:
        instance = self._find(zone, name)
        if (
            instance is None
            or instance["status"] != "RUNNING"
            or not self.publish
        ):
            return reply(404, {"error": {"message": "not found"}})
        items = [
            {"namespace": "ci-remote-builder", "key": "ready", "value": "1"}
        ]
        if self.host_key is not None:
            items.insert(
                0,
                {
                    "namespace": "ci-remote-builder",
                    "key": "host-key",
                    "value": self.host_key,
                },
            )
        return reply(
            200,
            {
                "queryPath": "ci-remote-builder/",
                "queryValue": {"items": items},
            },
        )

    def _remove(self, zone: str, name: str) -> spot.Response:
        if self.delete_error:
            return reply(503, {"error": {"message": "backend error"}})
        instance = self._find(zone, name)
        if instance is None:
            return reply(404, {"error": {"message": "not found"}})
        if name in self.removing:
            return reply(
                400,
                {
                    "error": {
                        "message": (
                            f"The resource 'projects/{PROJECT}/zones/{zone}/"
                            f"instances/{name}' is not ready"
                        )
                    }
                },
            )
        self.deleted.append(name)
        if self.delete_takes:
            self.removing[name] = self.clock.mono + self.delete_takes
            instance["status"] = "STOPPING"
        else:
            del self.instances[name]
        return reply(200, {"name": f"delete-{name}", "status": "RUNNING"})


class Harness:
    def __init__(self, tmp_path: Path, *, system: str | None = SYSTEM) -> None:
        self.clock = FakeClock()
        self.cloud = FakeRemoteCloud(self.clock)
        key = tmp_path / "gcp-ci-key"
        key.write_text(
            json.dumps(
                {
                    "type": "service_account",
                    "project_id": PROJECT,
                    "private_key_id": KEY_ID,
                    "private_key": PEM,
                    "client_email": EMAIL,
                    "token_uri": "https://oauth2.googleapis.com/token",
                }
            )
        )
        self.system = tmp_path / "ci-remote-builder-system"
        if system is not None:
            self.system.write_text(system)
        script = tmp_path / "startup-script.sh"
        script.write_text(STARTUP_SCRIPT)
        self.env = {
            "GCP_KEY_PATH": str(key),
            "CI_REMOTE_BUILDER_STARTUP_SCRIPT": str(script),
            "CI_REMOTE_BUILDER_SSH_KEY": SSH_KEY,
            "CI_REMOTE_BUILDER_SYSTEM_FILE": str(self.system),
        }
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()

    def run(self, *argv: str) -> int:
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        return remote.run(
            argv, self.env, self.cloud, self.clock, self.stdout, self.stderr
        )

    def requests(self, method: str) -> list[str]:
        return [url for verb, url in self.cloud.calls if verb == method]

    @property
    def log(self) -> str:
        return self.stderr.getvalue()


@pytest.fixture
def harness(tmp_path: Path) -> Harness:
    return Harness(tmp_path)


def instance_url(zone: str) -> str:
    return (
        f"https://compute.googleapis.com/compute/v1/projects/{PROJECT}/"
        f"zones/{zone}/instances/{NAME}"
    )


def test_lease_launch_sends_remote_builder_instance(harness: Harness) -> None:
    assert harness.run("lease", LEASE_ID) == 0

    [body] = harness.cloud.inserted
    assert body == {
        "name": NAME,
        "machineType": f"zones/us-central1-a/machineTypes/{C4D}",
        "labels": {"maybe-ci-remote": "true"},
        "tags": {"items": ["ci-remote-builder"]},
        "disks": [
            {
                "boot": True,
                "autoDelete": True,
                "initializeParams": {
                    "sourceImage": (
                        f"projects/{PROJECT}/global/images/family/ci-builder"
                    ),
                    "diskType": (
                        "zones/us-central1-a/diskTypes/hyperdisk-balanced"
                    ),
                    "diskSizeGb": "60",
                    "provisionedIops": "6000",
                    "provisionedThroughput": "400",
                },
            }
        ],
        "networkInterfaces": [
            {
                "subnetwork": (
                    f"projects/{PROJECT}/regions/us-central1/subnetworks/"
                    "maybe-ci-us-central1"
                ),
                "nicType": "GVNIC",
                "accessConfigs": [
                    {"type": "ONE_TO_ONE_NAT", "name": "External NAT"}
                ],
            }
        ],
        "scheduling": {
            "provisioningModel": "SPOT",
            "instanceTerminationAction": "DELETE",
            "maxRunDuration": {"seconds": "7200"},
            "automaticRestart": False,
            "onHostMaintenance": "TERMINATE",
        },
        "metadata": {
            "items": [
                {"key": "startup-script", "value": STARTUP_SCRIPT},
                {"key": "ci-builder-system", "value": SYSTEM},
                {"key": "enable-guest-attributes", "value": "TRUE"},
                {"key": "block-project-ssh-keys", "value": "TRUE"},
                {"key": "enable-oslogin", "value": "FALSE"},
                {"key": "serial-port-enable", "value": "FALSE"},
            ]
        },
    }


def test_lease_ready_builder_prints_builders_line(harness: Harness) -> None:
    started = harness.clock.mono

    assert harness.run("lease", LEASE_ID) == 0

    assert harness.stdout.getvalue() == BUILDERS_LINE + "\n"
    fields = BUILDERS_LINE.split(" ")
    assert len(fields) == 8
    assert base64.b64decode(fields[7], validate=True) == HOST_KEY.encode()
    assert harness.cloud.deleted == []
    assert f"{NAME} is ready at {NAT_IP}" in harness.log
    assert harness.clock.mono - started < 90


@pytest.mark.parametrize(
    "host_key",
    [HOST_KEY, f"{HOST_KEY} root@maybe-ci-remote", f"{HOST_KEY} a"],
)
def test_lease_host_key_with_or_without_comment_prints_bare_key(
    harness: Harness, host_key: str
) -> None:
    harness.cloud.host_key = host_key

    assert harness.run("lease", LEASE_ID) == 0

    assert harness.stdout.getvalue() == BUILDERS_LINE + "\n"


@pytest.mark.parametrize("mode", ["quota", "quota-http"])
def test_lease_quota_error_skips_the_shape_in_other_zones(
    harness: Harness, mode: str
) -> None:
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = mode

    assert harness.run("lease", LEASE_ID) == 0

    assert harness.cloud.attempts == [
        (C4D, "us-central1-a"),
        (C3D, "us-central1-a"),
    ]
    assert "the quota covers the region" in harness.log
    assert harness.stdout.getvalue() == BUILDERS_LINE + "\n"


def test_lease_capacity_error_tries_next_zone_then_shape(
    harness: Harness,
) -> None:
    for zone in ZONES:
        harness.cloud.insert_errors[(C4D, zone)] = "operation"
    harness.cloud.insert_errors[(C3D, "us-central1-a")] = "http"

    assert harness.run("lease", LEASE_ID) == 0

    assert harness.cloud.attempts == [(C4D, zone) for zone in ZONES] + [
        (C3D, "us-central1-a"),
        (C3D, "us-central1-b"),
    ]
    assert set(harness.requests("GET")) >= {instance_url("us-central1-b")}
    assert harness.stdout.getvalue() == BUILDERS_LINE + "\n"


def test_lease_no_capacity_anywhere_fails(harness: Harness) -> None:
    for shape in (C4D, C3D):
        for zone in ZONES:
            harness.cloud.insert_errors[(shape, zone)] = "operation"

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.cloud.attempts == [
        (shape, zone) for shape in (C4D, C3D) for zone in ZONES
    ]
    assert harness.stdout.getvalue() == ""
    assert harness.cloud.instances == {}
    assert "failed in every zone" in harness.log


def test_lease_unanswered_insert_waits_in_the_same_zone(
    harness: Harness,
) -> None:
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "unreachable"

    assert harness.run("lease", LEASE_ID) == 0

    assert harness.cloud.attempts == [(C4D, "us-central1-a")]
    assert harness.stdout.getvalue() == BUILDERS_LINE + "\n"


@pytest.mark.parametrize("stuck", ["provisioning", "running"])
def test_lease_never_ready_deletes_instance_and_fails_within_5_minutes(
    harness: Harness, stuck: str
) -> None:
    if stuck == "provisioning":
        harness.cloud.boot_after = None
    else:
        harness.cloud.publish = False
    started = harness.clock.mono

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.cloud.deleted == [NAME]
    assert harness.cloud.instances == {}
    assert harness.clock.mono - started <= 300
    assert "did not set ci-remote-builder/ready within 300 s" in harness.log


@pytest.mark.parametrize("status", ["TERMINATED", "STOPPING", "SUSPENDED"])
def test_lease_vm_dead_before_ready_deletes_instance_and_fails_fast(
    harness: Harness, status: str
) -> None:
    harness.cloud.boot_status = status
    started = harness.clock.mono

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.cloud.deleted == [NAME]
    assert harness.cloud.instances == {}
    assert harness.clock.mono - started < 90
    assert f"{NAME} is {status} before it set ci-remote-builder/ready" in (
        harness.log
    )


def test_lease_vm_vanishing_before_ready_fails_fast(harness: Harness) -> None:
    harness.cloud.vanish = True
    started = harness.clock.mono

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.clock.mono - started < 90
    assert "disappeared before it was ready" in harness.log


@pytest.mark.parametrize(
    "host_key",
    [
        None,
        "",
        HOST_KEY_DATA,
        f"ssh-rsa {HOST_KEY_DATA}",
        f"ssh-ed25519  {HOST_KEY_DATA}",
        f"ssh-ed25519\t{HOST_KEY_DATA}",
        f" {HOST_KEY}",
        f"{HOST_KEY} ",
        f"{HOST_KEY}\n",
        f"{HOST_KEY}\r",
        f"{HOST_KEY}\n{NAT_IP} ssh-ed25519 {OTHER_KEY_DATA}",
        f"{HOST_KEY} root@x\nevil",
        f"{HOST_KEY} two words",
        f"{HOST_KEY} café",
        f"{HOST_KEY}\x00",
        f"ssh-ed25519 {HOST_KEY_DATA[:-4]}",
        f"ssh-ed25519 {HOST_KEY_DATA}AAAA",
        f"ssh-ed25519 {HOST_KEY_DATA[:-1]}=",
        "ssh-ed25519 "
        + base64.b64encode(
            b"\x00\x00\x00\x0bssh-ed25519\x00\x00\x00\x21" + bytes(32)
        ).decode(),
        "ssh-ed25519 "
        + base64.b64encode(
            b"\x00\x00\x00\x0bssh-ed25518\x00\x00\x00\x20" + bytes(32)
        ).decode(),
    ],
)
def test_lease_malformed_host_key_deletes_instance_and_fails(
    harness: Harness, host_key: str | None
) -> None:
    harness.cloud.host_key = host_key

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.cloud.deleted == [NAME]
    assert "ci-remote-builder/host-key" in harness.log
    assert "\nevil" not in harness.log


@pytest.mark.parametrize(
    "nat_ip", [None, "", "34.66.12.034", "2600:1900::1", f"{NAT_IP} x", 7]
)
def test_lease_bad_external_address_deletes_instance_and_fails(
    harness: Harness, nat_ip: object
) -> None:
    harness.cloud.nat_ip = nat_ip

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.cloud.deleted == [NAME]
    assert "expected an IPv4 address" in harness.log


def test_lease_interrupted_deletes_instance_and_fails(
    harness: Harness,
) -> None:
    harness.cloud.interrupt_on = "getGuestAttributes"

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.cloud.deleted == [NAME]
    assert "received SIGTERM" in harness.log


def test_release_interrupted_exits_1(harness: Harness) -> None:
    harness.cloud.interrupt_on = NAME

    assert harness.run("release", LEASE_ID) == 1

    assert "received SIGTERM" in harness.log


def test_interrupt_ignores_further_signals_during_cleanup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    installed: list[tuple[int, object]] = []
    monkeypatch.setattr(
        remote.signal,
        "signal",
        lambda signum, handler: installed.append((signum, handler)),
    )

    with pytest.raises(remote.Interrupted, match="received SIGTERM"):
        remote.interrupt(signal.SIGTERM, None)

    assert installed == [
        (signal.SIGTERM, signal.SIG_IGN),
        (signal.SIGINT, signal.SIG_IGN),
    ]


def test_lease_failed_cleanup_reports_both_failures(harness: Harness) -> None:
    harness.cloud.publish = False
    harness.cloud.delete_error = True
    started = harness.clock.mono

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.stdout.getvalue() == ""
    assert harness.clock.mono - started <= 300 + remote.RELEASE_BUDGET
    assert "deleting it failed too" in harness.log
    assert (
        f"gcloud compute instances delete {NAME} --zone=us-central1-a"
        in harness.log
    )


@pytest.mark.parametrize(
    "content",
    [
        None,
        "",
        "garbage\n",
        f"{SYSTEM}\n{SYSTEM}\n",
        "/nix/store/" + "e" * 32 + "-nixos-system-x\n",
        f" {SYSTEM}\n",
    ],
)
def test_lease_bad_system_file_refuses_before_any_request(
    tmp_path: Path, content: str | None
) -> None:
    harness = Harness(tmp_path, system=content)

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.cloud.calls == []
    assert harness.stdout.getvalue() == ""
    assert "not leasing a remote builder" in harness.log
    assert "ci-remote-builder system" in harness.log


@pytest.mark.parametrize(
    "variable",
    [
        "GCP_KEY_PATH",
        "CI_REMOTE_BUILDER_STARTUP_SCRIPT",
        "CI_REMOTE_BUILDER_SSH_KEY",
        "CI_REMOTE_BUILDER_SYSTEM_FILE",
    ],
)
def test_lease_missing_setting_refuses_before_any_request(
    harness: Harness, variable: str
) -> None:
    del harness.env[variable]

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.cloud.calls == []
    assert f"{variable} is not set" in harness.log


@pytest.mark.parametrize(
    "ssh_key", ["run/agenix/key", "/run/agenix/a key", "/run/agenix/key\n"]
)
def test_lease_bad_ssh_key_path_refuses_before_any_request(
    harness: Harness, ssh_key: str
) -> None:
    harness.env["CI_REMOTE_BUILDER_SSH_KEY"] = ssh_key

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.cloud.calls == []
    assert "CI_REMOTE_BUILDER_SSH_KEY is" in harness.log


def test_lease_unreadable_gcp_key_refuses_before_any_request(
    harness: Harness,
) -> None:
    Path(harness.env["GCP_KEY_PATH"]).write_text("placeholder\n")

    assert harness.run("lease", LEASE_ID) == 1

    assert harness.cloud.calls == []
    assert "is not JSON" in harness.log


@pytest.mark.parametrize("command", ["lease", "release"])
@pytest.mark.parametrize(
    "lease_id",
    [
        "",
        LEASE_ID.upper(),
        LEASE_ID + "\n",
        LEASE_ID + "0",
        LEASE_ID[:-1],
        LEASE_ID.replace("-", ""),
        "../" + LEASE_ID[3:],
        "g" * 8 + LEASE_ID[8:],
        f"{LEASE_ID} --zone=us-central1-a",
    ],
)
def test_command_invalid_lease_id_refuses_before_any_request(
    harness: Harness, command: str, lease_id: str
) -> None:
    assert harness.run(command, lease_id) == 2

    assert harness.cloud.calls == []
    assert harness.stdout.getvalue() == ""
    assert "expected a Buildkite job id" in harness.log


@pytest.mark.parametrize(
    "argv",
    [(), ("lease",), ("renew", LEASE_ID), ("lease", LEASE_ID, "extra")],
)
def test_command_bad_usage_exits_2(
    harness: Harness, argv: tuple[str, ...]
) -> None:
    assert harness.run(*argv) == 2

    assert harness.cloud.calls == []
    assert "usage: ci-remote-builder" in harness.log


def test_release_leased_instance_deletes_it(harness: Harness) -> None:
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "operation"
    assert harness.run("lease", LEASE_ID) == 0
    harness.cloud.calls.clear()

    assert harness.run("release", LEASE_ID) == 0

    assert harness.cloud.deleted == [NAME]
    assert harness.cloud.instances == {}
    assert harness.requests("DELETE") == [instance_url(z) for z in ZONES]
    assert f"deleting {NAME} in us-central1-b" in harness.log
    assert harness.stdout.getvalue() == ""


def test_release_needs_only_the_gcp_key(harness: Harness) -> None:
    for variable in (
        "CI_REMOTE_BUILDER_STARTUP_SCRIPT",
        "CI_REMOTE_BUILDER_SSH_KEY",
        "CI_REMOTE_BUILDER_SYSTEM_FILE",
    ):
        del harness.env[variable]

    assert harness.run("release", LEASE_ID) == 0

    assert harness.requests("DELETE") == [instance_url(z) for z in ZONES]
    assert f"{NAME} does not exist; nothing to delete" in harness.log


def test_release_twice_succeeds(harness: Harness) -> None:
    assert harness.run("lease", LEASE_ID) == 0
    assert harness.run("release", LEASE_ID) == 0

    assert harness.run("release", LEASE_ID) == 0

    assert harness.cloud.deleted == [NAME]
    assert f"{NAME} does not exist; nothing to delete" in harness.log


def test_release_while_deleting_waits_until_gone(harness: Harness) -> None:
    harness.cloud.delete_takes = 40.0
    assert harness.run("lease", LEASE_ID) == 0
    assert harness.run("release", LEASE_ID) == 0
    started = harness.clock.mono

    assert harness.run("release", LEASE_ID) == 0

    assert harness.cloud.deleted == [NAME]
    assert harness.cloud.instances == {}
    assert 40 <= harness.clock.mono - started <= remote.RELEASE_BUDGET
    assert "is not ready" in harness.log
    assert "retrying in 5 s until it is accepted or gone" in harness.log


def test_release_persistent_error_fails_with_manual_command(
    harness: Harness,
) -> None:
    assert harness.run("lease", LEASE_ID) == 0
    harness.cloud.delete_error = True
    started = harness.clock.mono

    assert harness.run("release", LEASE_ID) == 1

    assert harness.clock.mono - started <= remote.RELEASE_BUDGET
    assert NAME in harness.cloud.instances
    for zone in ZONES:
        assert (
            f"gcloud compute instances delete {NAME} --zone={zone}"
            in harness.log
        )


def test_logs_never_contain_secrets(harness: Harness) -> None:
    harness.cloud.echo = f"{ACCESS_TOKEN} {PEM}"
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "http"

    assert harness.run("lease", LEASE_ID) == 0

    assert "Quota exceeded <redacted>" in harness.log
    assert ACCESS_TOKEN not in harness.log
    for line in PEM.splitlines()[1:-1]:
        assert line not in harness.log
