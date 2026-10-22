import base64
import io
import json
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

import ci_spot_poller as poller

PROJECT = "maybe-test-project"
EMAIL = f"maybe-ci-spot@{PROJECT}.iam.gserviceaccount.com"
KEY_ID = "0123456789abcdef0123456789abcdef01234567"
AGENT_TOKEN = "bkua_agent-token-that-must-stay-secret"
ACCESS_TOKEN = "ya29.access-token-that-must-stay-secret"
SYSTEM = "/nix/store/" + "a" * 32 + "-nixos-system-ci-builder-26.05"
STARTUP_SCRIPT = "#!/usr/bin/env bash\necho start\n"
ZONES = ("us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f")
C4D = "c4d-highcpu-16"
C3D = "c3d-highcpu-30"
QUOTA_MESSAGE = (
    "Quota 'CPUS_PER_VM_FAMILY' exceeded.  Limit: 50.0 in region us-central1."
)
PACIFIC = timezone(timedelta(hours=-7))
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PEM = KEY.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()


class Stop(BaseException):
    pass


class FakeClock:
    def __init__(self) -> None:
        self.wall = 1_800_000_000.0
        self.mono = 5_000.0
        self.sleeps: list[float] = []
        self.stop_after: int | None = None

    def time(self) -> float:
        return self.wall

    def monotonic(self) -> float:
        return self.mono

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        if self.stop_after is not None and len(self.sleeps) >= self.stop_after:
            raise Stop
        self.advance(seconds)

    def advance(self, seconds: float) -> None:
        self.wall += seconds
        self.mono += seconds


def reply(status: int, body: object) -> poller.Response:
    return poller.Response(status, json.dumps(body).encode())


def unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class FakeCloud:
    def __init__(self, clock: FakeClock) -> None:
        self.clock = clock
        self.scheduled = 0
        self.idle = 0
        self.busy = 0
        self.metrics_failure: str | None = None
        self.instances: dict[str, dict[str, object]] = {}
        self.ready: set[str] = set()
        self.guest_errors: set[str] = set()
        self.insert_errors: dict[tuple[str, str], str] = {}
        self.hide_unanswered_inserts = False
        self.unreachables: list[str] = []
        self.page_size = 500
        self.echo = ""
        self.attempts: list[tuple[str, str]] = []
        self.inserted: list[dict[str, object]] = []
        self.deleted: list[str] = []
        self.token_requests = 0
        self.operations: dict[str, dict[str, object]] = {}

    def add(
        self,
        name: str,
        *,
        status: str = "RUNNING",
        age: float = 60.0,
        ready: bool = False,
        zone: str = "us-central1-a",
        labelled: bool = True,
    ) -> None:
        created = datetime.fromtimestamp(self.clock.wall - age, PACIFIC)
        self.instances[name] = {
            "name": name,
            "zone": (
                "https://www.googleapis.com/compute/v1/projects/"
                f"{PROJECT}/zones/{zone}"
            ),
            "status": status,
            "creationTimestamp": created.isoformat(timespec="milliseconds"),
            "labels": {"maybe-ci": "true"} if labelled else {"other": "x"},
        }
        if ready:
            self.ready.add(name)

    def request(
        self,
        method: str,
        url: str,
        headers: dict[str, str],
        body: bytes | None,
        timeout: float,
    ) -> poller.Response:
        assert timeout > 0
        if url == poller.METRICS_URL:
            return self._metrics(method, headers)
        if url == poller.TOKEN_URI:
            return self._token(method, headers, body)
        assert headers["Authorization"] == f"Bearer {ACCESS_TOKEN}"
        parts = urllib.parse.urlsplit(url)
        assert f"{parts.scheme}://{parts.netloc}" == (
            "https://compute.googleapis.com"
        )
        prefix = f"/compute/v1/projects/{PROJECT}/"
        assert parts.path.startswith(prefix)
        path = parts.path.removeprefix(prefix).split("/")
        query = urllib.parse.parse_qs(parts.query)
        match method, path:
            case "GET", ["aggregated", "instances"]:
                return self._list(query)
            case "GET", ["zones", zone, "instances", name, guest]:
                assert guest == "getGuestAttributes"
                assert query == {"queryPath": ["ci-builder/"]}
                return self._guest(name)
            case "POST", ["zones", zone, "instances"]:
                assert body is not None
                return self._insert(zone, json.loads(body))
            case "POST", ["zones", zone, "operations", name, "wait"]:
                assert body == b""
                return self._wait(name)
            case "DELETE", ["zones", zone, "instances", name]:
                return self._delete(name)
        raise AssertionError(f"unexpected {method} {url}")

    def _metrics(
        self, method: str, headers: dict[str, str]
    ) -> poller.Response:
        assert method == "GET"
        assert headers["Authorization"] == f"Token {AGENT_TOKEN}"
        if self.metrics_failure == "unreachable":
            raise poller.TransportError("timed out")
        if self.metrics_failure == "http":
            return reply(401, {"message": f"Invalid token {self.echo}"})
        return reply(
            200,
            {
                "agents": {
                    "idle": 9,
                    "busy": 9,
                    "queues": {
                        "spot-builders": {
                            "idle": self.idle,
                            "busy": self.busy,
                            "total": self.idle + self.busy,
                        },
                        "blaziken": {"idle": 2, "busy": 0, "total": 2},
                    },
                },
                "jobs": {
                    "scheduled": 9,
                    "queues": {
                        "spot-builders": {
                            "scheduled": self.scheduled,
                            "running": self.busy,
                            "waiting": 7,
                        },
                        "blaziken": {"scheduled": 4},
                    },
                },
                "organization": {"slug": "test"},
            },
        )

    def _token(
        self, method: str, headers: dict[str, str], body: bytes | None
    ) -> poller.Response:
        assert method == "POST"
        assert headers == {"Content-Type": "application/x-www-form-urlencoded"}
        assert body is not None
        form = urllib.parse.parse_qs(body.decode())
        assert form["grant_type"] == [poller.GRANT_TYPE]
        header, claims, signature = form["assertion"][0].split(".")
        KEY.public_key().verify(
            unb64(signature),
            f"{header}.{claims}".encode(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        assert json.loads(unb64(header)) == {
            "alg": "RS256",
            "typ": "JWT",
            "kid": KEY_ID,
        }
        issued = int(self.clock.wall)
        assert json.loads(unb64(claims)) == {
            "iss": EMAIL,
            "scope": "https://www.googleapis.com/auth/compute",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": issued,
            "exp": issued + 3600,
        }
        self.token_requests += 1
        return reply(
            200,
            {
                "access_token": ACCESS_TOKEN,
                "expires_in": 3599,
                "token_type": "Bearer",
            },
        )

    def _list(self, query: dict[str, list[str]]) -> poller.Response:
        assert query["filter"] == ['labels.maybe-ci = "true"']
        listed = list(self.instances.values())
        start = int(query.get("pageToken", ["0"])[0])
        end = start + self.page_size
        page = listed[start:end]
        items: dict[str, object] = {}
        for zone in ZONES:
            in_zone = [i for i in page if str(i["zone"]).endswith(zone)]
            if in_zone:
                items[f"zones/{zone}"] = {"instances": in_zone}
            else:
                items[f"zones/{zone}"] = {
                    "warning": {
                        "code": "NO_RESULTS_ON_PAGE",
                        "message": "There are no results for scope",
                    }
                }
        data: dict[str, object] = {"items": items}
        if start + self.page_size < len(listed):
            data["nextPageToken"] = str(start + self.page_size)
        if self.unreachables:
            data["unreachables"] = self.unreachables
        return reply(200, data)

    def _guest(self, name: str) -> poller.Response:
        if name in self.guest_errors:
            return reply(500, {"error": {"message": f"backend {self.echo}"}})
        if name not in self.instances or name not in self.ready:
            return reply(404, {"error": {"message": "not found"}})
        return reply(
            200,
            {
                "queryPath": "ci-builder/",
                "queryValue": {
                    "items": [
                        {
                            "namespace": "ci-builder",
                            "key": "ready",
                            "value": "1",
                        }
                    ]
                },
            },
        )

    def _insert(self, zone: str, body: dict[str, object]) -> poller.Response:
        shape = str(body["machineType"]).rsplit("/", 1)[-1]
        assert body["machineType"] == f"zones/{zone}/machineTypes/{shape}"
        self.attempts.append((shape, zone))
        self.inserted.append(body)
        name = str(body["name"])
        mode = self.insert_errors.get((shape, zone))
        if mode == "http":
            return reply(
                403,
                {"error": {"message": f"Quota exceeded {self.echo}"}},
            )
        if mode == "quota-http":
            return reply(
                403,
                {"error": {"message": QUOTA_MESSAGE}},
            )
        if mode == "unreachable":
            if not self.hide_unanswered_inserts:
                self.add(name, status="PROVISIONING", age=0, zone=zone)
            raise poller.TransportError("timed out")
        operation = f"operation-{len(self.operations)}"
        if mode == "quota":
            self.operations[operation] = {
                "name": operation,
                "status": "DONE",
                "error": {
                    "errors": [
                        {"code": "QUOTA_EXCEEDED", "message": QUOTA_MESSAGE}
                    ]
                },
            }
        elif mode == "operation":
            self.operations[operation] = {
                "name": operation,
                "status": "DONE",
                "error": {
                    "errors": [
                        {
                            "code": "ZONE_RESOURCE_POOL_EXHAUSTED",
                            "message": f"no {shape} in {zone}",
                        }
                    ]
                },
            }
        else:
            self.add(name, status="PROVISIONING", age=0, zone=zone)
            self.operations[operation] = {"name": operation, "status": "DONE"}
        return reply(200, {"name": operation, "status": "RUNNING"})

    def _wait(self, name: str) -> poller.Response:
        return reply(200, self.operations[name])

    def _delete(self, name: str) -> poller.Response:
        if name not in self.instances:
            return reply(404, {"error": {"message": "not found"}})
        del self.instances[name]
        self.ready.discard(name)
        self.deleted.append(name)
        return reply(200, {"name": f"delete-{name}", "status": "RUNNING"})

    def provision(self) -> None:
        for instance in self.instances.values():
            if instance["status"] == "PROVISIONING":
                instance["status"] = "RUNNING"


class Harness:
    def __init__(
        self,
        tmp_path: Path,
        *,
        system: str | None = SYSTEM,
        key: str | None = None,
        max_instances: int = 3,
        cache: tuple[str | None, str | None] | None = None,
    ) -> None:
        self.clock = FakeClock()
        self.cloud = FakeCloud(self.clock)
        token = tmp_path / "buildkite-token"
        token.write_text(AGENT_TOKEN + "\n")
        self.key = tmp_path / "gcp-ci-key"
        self.key.write_text(
            key
            if key is not None
            else json.dumps(
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
        self.system = tmp_path / "ci-builder-system"
        if system is not None:
            self.system.write_text(system)
        script = tmp_path / "startup-script.sh"
        script.write_text(STARTUP_SCRIPT)
        (tmp_path / "fallback").mkdir()
        self.request = tmp_path / "fallback" / "request"
        env = {
            "BUILDKITE_AGENT_TOKEN_PATH": str(token),
            "GCP_KEY_PATH": str(self.key),
            "CI_BUILDER_SYSTEM_FILE": str(self.system),
            "CI_BUILDER_STARTUP_SCRIPT": str(script),
            "CI_SPOT_FALLBACK_REQUEST": str(self.request),
            "CI_SPOT_MAX_INSTANCES": str(max_instances),
        }
        if cache is not None:
            for variable, name, value in zip(
                ("CI_CACHE_CREDENTIALS_PATH", "CI_CACHE_SIGNING_KEY_PATH"),
                ("ci-cache-writer", "ci-cache-signing-key"),
                cache,
                strict=True,
            ):
                path = tmp_path / name
                if value is not None:
                    path.write_text(value + "\n")
                env[variable] = str(path)
        self.config = poller.config_from_env(env)
        self.output = io.StringIO()
        self.poller = self.restart()

    def restart(self) -> poller.Poller:
        self.poller = poller.Poller(
            self.config, self.cloud, self.clock, poller.Log(self.output)
        )
        return self.poller

    def cycle(self) -> None:
        self.poller.cycle()
        self.clock.advance(30)

    def cycles(self, count: int) -> None:
        for _ in range(count):
            self.cycle()

    def take_request(self) -> bool:
        if not self.request.exists():
            return False
        self.request.unlink()
        return True

    @property
    def log(self) -> str:
        return self.output.getvalue()


@pytest.fixture
def harness(tmp_path: Path) -> Harness:
    return Harness(tmp_path)


def live(cloud: FakeCloud) -> list[str]:
    return [
        name
        for name, instance in cloud.instances.items()
        if instance["status"] not in poller.DEAD
    ]


def test_cycle_scheduled_jobs_launches_builders_for_unserved_jobs(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 4
    harness.cloud.idle = 1
    harness.cloud.add("maybe-ci-starting", age=120)

    harness.cycle()

    assert harness.cloud.attempts == [(C4D, "us-central1-a")] * 2
    assert len(live(harness.cloud)) == 3
    assert not harness.take_request()


def test_cycle_launch_sends_spot_builder_instance(harness: Harness) -> None:
    harness.cloud.scheduled = 1

    harness.cycle()

    [body] = harness.cloud.inserted
    name = body.pop("name")
    assert isinstance(name, str)
    assert name.startswith("maybe-ci-")
    assert len(name) == len("maybe-ci-") + 8
    assert body == {
        "machineType": f"zones/us-central1-a/machineTypes/{C4D}",
        "labels": {"maybe-ci": "true"},
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
            "maxRunDuration": {"seconds": "21600"},
            "automaticRestart": False,
            "onHostMaintenance": "TERMINATE",
        },
        "metadata": {
            "items": [
                {"key": "startup-script", "value": STARTUP_SCRIPT},
                {"key": "buildkite-agent-token", "value": AGENT_TOKEN},
                {"key": "ci-builder-system", "value": SYSTEM},
                {"key": "enable-guest-attributes", "value": "TRUE"},
                {"key": "block-project-ssh-keys", "value": "TRUE"},
                {"key": "enable-oslogin", "value": "FALSE"},
                {"key": "serial-port-enable", "value": "FALSE"},
            ]
        },
    }


def test_cycle_backlog_launches_up_to_instance_cap(harness: Harness) -> None:
    harness.cloud.scheduled = 10
    harness.cloud.busy = 1
    harness.cloud.add("maybe-ci-busy", age=600, ready=True)

    harness.cycle()
    assert len(harness.cloud.attempts) == 2
    assert len(live(harness.cloud)) == 3

    harness.cloud.provision()
    harness.cycles(3)
    harness.restart()
    harness.cycles(3)

    assert len(harness.cloud.attempts) == 2
    assert len(live(harness.cloud)) == 3


def test_cycle_paged_inventory_counts_every_page(harness: Harness) -> None:
    harness.cloud.page_size = 1
    harness.cloud.scheduled = 5
    for zone, name in zip(ZONES, ("a", "b", "c")):
        harness.cloud.add(f"maybe-ci-{name}", ready=True, zone=zone)

    harness.cycle()

    assert harness.cloud.attempts == []


def test_cycle_incomplete_inventory_launches_nothing(harness: Harness) -> None:
    harness.cloud.scheduled = 2
    harness.cloud.unreachables = ["zones/us-central1-b"]
    harness.cloud.add("maybe-ci-dead", status="TERMINATED")

    harness.cycle()

    assert harness.cloud.attempts == []
    assert harness.cloud.deleted == ["maybe-ci-dead"]
    assert "the instance list is incomplete" in harness.log


def test_cycle_unanswered_insert_counts_against_cap(tmp_path: Path) -> None:
    harness = Harness(tmp_path, max_instances=1)
    harness.cloud.scheduled = 3
    harness.cloud.hide_unanswered_inserts = True
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "unreachable"

    harness.cycles(5)

    assert harness.cloud.attempts == [(C4D, "us-central1-a")]
    assert not harness.take_request()


def test_cycle_insert_error_tries_next_zone(harness: Harness) -> None:
    harness.cloud.scheduled = 1
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "http"

    harness.cycle()

    assert harness.cloud.attempts == [
        (C4D, "us-central1-a"),
        (C4D, "us-central1-b"),
    ]
    assert len(live(harness.cloud)) == 1
    assert not harness.take_request()


def test_cycle_operation_error_tries_next_zone_then_shape(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 2
    for zone in ZONES:
        harness.cloud.insert_errors[(C4D, zone)] = "operation"

    harness.cycle()

    assert harness.cloud.attempts == [(C4D, zone) for zone in ZONES] + [
        (C3D, "us-central1-a"),
        (C3D, "us-central1-a"),
    ]
    assert len(live(harness.cloud)) == 2
    assert not harness.take_request()


@pytest.mark.parametrize("mode", ["quota", "quota-http"])
def test_cycle_quota_error_skips_the_shape_in_other_zones(
    harness: Harness, mode: str
) -> None:
    harness.cloud.scheduled = 2
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = mode

    harness.cycle()

    assert harness.cloud.attempts == [
        (C4D, "us-central1-a"),
        (C3D, "us-central1-a"),
        (C3D, "us-central1-a"),
    ]
    assert len(live(harness.cloud)) == 2
    assert "the quota covers the region" in harness.log
    assert not harness.take_request()


def test_cycle_every_launch_failing_requests_fallback(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 2
    for shape in (C4D, C3D):
        for index, zone in enumerate(ZONES):
            mode = "http" if index % 2 else "operation"
            harness.cloud.insert_errors[(shape, zone)] = mode

    harness.cycle()

    assert harness.cloud.attempts == [
        (shape, zone) for shape in (C4D, C3D) for zone in ZONES
    ]
    assert live(harness.cloud) == []
    assert harness.take_request()
    assert "every launch failed" in harness.log


def test_cycle_failed_launch_beside_live_builder_skips_fallback(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 3
    harness.cloud.busy = 1
    harness.cloud.add("maybe-ci-busy", ready=True)
    for shape in (C4D, C3D):
        for zone in ZONES:
            harness.cloud.insert_errors[(shape, zone)] = "http"

    harness.cycle()

    assert len(harness.cloud.attempts) == 8
    assert not harness.take_request()


def test_cycle_backlog_with_busy_ready_builders_skips_fallback(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 5
    harness.cloud.busy = 3
    for name in ("a", "b", "c"):
        harness.cloud.add(f"maybe-ci-{name}", ready=True)

    harness.cycles(20)

    assert harness.cloud.attempts == []
    assert not harness.take_request()
    assert "fallback" not in harness.log


def test_cycle_no_ready_builder_for_5_minutes_requests_fallback(
    tmp_path: Path,
) -> None:
    harness = Harness(tmp_path, max_instances=1)
    harness.cloud.scheduled = 1

    harness.cycle()
    harness.cloud.provision()
    assert len(harness.cloud.attempts) == 1
    harness.cycles(9)
    assert not harness.take_request()

    harness.cycle()
    assert harness.take_request()
    assert "no spot builder has been ready for 5 min" in harness.log
    harness.cycle()
    assert harness.take_request()

    [name] = live(harness.cloud)
    harness.cloud.ready.add(name)
    harness.cycle()
    assert not harness.take_request()
    assert "the fallback agent is no longer needed" in harness.log
    assert len(harness.cloud.attempts) == 1


def test_cycle_no_ready_timer_holds_through_metrics_errors(
    harness: Harness,
) -> None:
    harness.cloud.scheduled = 1
    harness.cloud.add("maybe-ci-starting", age=0)

    harness.cycles(4)
    harness.cloud.metrics_failure = "http"
    harness.cycles(4)
    harness.cloud.metrics_failure = None
    harness.cycles(2)
    assert not harness.take_request()

    harness.cycle()
    assert harness.take_request()
    assert harness.cloud.attempts == []


@pytest.mark.parametrize(
    "content",
    [
        None,
        "",
        "garbage\n",
        f"{SYSTEM}\n{SYSTEM}\n",
        "/nix/store/" + "e" * 32 + "-nixos-system-x\n",
        "/nix/store/short-nixos-system-ci-builder\n",
        f" {SYSTEM}\n",
    ],
)
def test_cycle_bad_system_file_launches_nothing_and_requests_fallback(
    tmp_path: Path, content: str | None
) -> None:
    harness = Harness(tmp_path, system=content)
    harness.cycle()
    assert not harness.take_request()

    harness.cloud.scheduled = 2
    harness.cycles(3)

    assert harness.cloud.attempts == []
    assert harness.take_request()
    assert harness.log.count("launching nothing until it is fixed") == 1
    assert "ci-builder-system is missing or invalid" in harness.log

    harness.system.write_text(SYSTEM + "\n")
    harness.cycle()
    assert len(harness.cloud.attempts) == 2


@pytest.mark.parametrize(
    "status",
    ["TERMINATED", "STOPPED", "SUSPENDED", "STOPPING", "SUSPENDING"],
)
def test_cycle_dead_instance_is_deleted(harness: Harness, status: str) -> None:
    harness.cloud.add("maybe-ci-dead", status=status, age=30)

    harness.cycle()

    assert harness.cloud.deleted == ["maybe-ci-dead"]


@pytest.mark.parametrize("status", ["STOPPING", "SUSPENDING"])
def test_cycle_shutting_down_instance_is_deleted_and_replaced(
    harness: Harness, status: str
) -> None:
    harness.cloud.scheduled = 1
    harness.cloud.busy = 2
    harness.cloud.add("maybe-ci-busy-1", age=600, ready=True)
    harness.cloud.add("maybe-ci-busy-2", age=600, ready=True)
    harness.cloud.add("maybe-ci-leaving", status=status, age=600)

    harness.cycle()

    assert harness.cloud.deleted == ["maybe-ci-leaving"]
    assert len(harness.cloud.attempts) == 1
    assert len(live(harness.cloud)) == 3


@pytest.mark.parametrize("status", ["RUNNING", "PROVISIONING", "STAGING"])
def test_cycle_not_ready_after_15_minutes_is_deleted(
    harness: Harness, status: str
) -> None:
    harness.cloud.add("maybe-ci-young", status=status, age=14 * 60)
    harness.cloud.add("maybe-ci-stuck", status=status, age=15 * 60 + 1)

    harness.cycle()

    assert harness.cloud.deleted == ["maybe-ci-stuck"]
    assert "has not set ci-builder/ready within 15 min" in harness.log


def test_cycle_ready_instance_is_kept(harness: Harness) -> None:
    harness.cloud.add("maybe-ci-ready", age=5 * 3600, ready=True)

    harness.cycles(3)

    assert harness.cloud.deleted == []


def test_cycle_unreadable_guest_attributes_keep_instance(
    harness: Harness,
) -> None:
    harness.cloud.add("maybe-ci-unknown", age=20 * 60)
    harness.cloud.guest_errors.add("maybe-ci-unknown")

    harness.cycle()

    assert harness.cloud.deleted == []
    assert "keeping it until they can be read" in harness.log


def test_cycle_instance_past_backstop_is_deleted(harness: Harness) -> None:
    harness.cloud.add("maybe-ci-ready", age=6 * 3600 + 15 * 60 + 1, ready=True)

    harness.cycle()

    assert harness.cloud.deleted == ["maybe-ci-ready"]
    assert "older than 6 h 15 min" in harness.log


def test_cycle_unlabelled_instances_are_ignored(harness: Harness) -> None:
    harness.cloud.scheduled = 3
    harness.cloud.add("other-dead", status="TERMINATED", labelled=False)
    harness.cloud.add("other-old", age=7 * 3600, labelled=False)

    harness.cycle()

    assert harness.cloud.deleted == []
    assert len(harness.cloud.attempts) == 3


def test_cycle_metrics_error_keeps_running(harness: Harness) -> None:
    harness.cloud.scheduled = 1
    harness.cloud.add("maybe-ci-dead", status="TERMINATED")
    harness.cloud.metrics_failure = "unreachable"

    harness.cycle()
    harness.cloud.metrics_failure = "http"
    harness.cycle()

    assert harness.cloud.attempts == []
    assert harness.cloud.deleted == ["maybe-ci-dead"]
    assert harness.log.count("reading Buildkite queue metrics failed") == 2

    harness.cloud.metrics_failure = None
    harness.cycle()

    assert len(harness.cloud.attempts) == 1
    assert "buildkite-metrics recovered" in harness.log


def test_run_unexpected_error_keeps_looping(
    harness: Harness, monkeypatch: pytest.MonkeyPatch
) -> None:
    def explode() -> None:
        raise RuntimeError(f"surprise {AGENT_TOKEN}")

    harness.poller.cycle()
    monkeypatch.setattr(harness.poller, "cycle", explode)
    harness.clock.stop_after = 3

    with pytest.raises(Stop):
        harness.poller.run()

    assert harness.log.count("the cycle failed unexpectedly") == 3
    assert harness.clock.sleeps == [30.0, 30.0, 30.0]
    assert AGENT_TOKEN not in harness.log


def test_cycle_placeholder_key_is_reported_once_then_falls_back(
    tmp_path: Path,
) -> None:
    harness = Harness(tmp_path, key="placeholder\n")
    harness.cloud.scheduled = 1

    harness.cycles(10)
    assert not harness.take_request()
    harness.cycle()

    assert harness.take_request()
    assert harness.log.count("is not JSON") == 1
    assert harness.cloud.attempts == []


def test_access_token_is_reused_until_it_expires(harness: Harness) -> None:
    harness.cloud.add("maybe-ci-ready", ready=True)

    harness.cycles(100)
    assert harness.cloud.token_requests == 1

    harness.cycles(20)
    assert harness.cloud.token_requests == 2


def test_logs_never_contain_secrets(harness: Harness) -> None:
    cloud = harness.cloud
    cloud.echo = f"{AGENT_TOKEN} {ACCESS_TOKEN} {PEM}"
    cloud.scheduled = 2
    cloud.add("maybe-ci-unknown", age=20 * 60)
    cloud.guest_errors.add("maybe-ci-unknown")
    cloud.insert_errors[(C4D, "us-central1-a")] = "http"

    harness.cycle()
    cloud.metrics_failure = "http"
    harness.cycle()

    tokens = [
        item["value"]
        for body in cloud.inserted
        for item in body["metadata"]["items"]
        if item["key"] == "buildkite-agent-token"
    ]
    assert tokens and set(tokens) == {AGENT_TOKEN}
    assert "Quota exceeded <redacted>" in harness.log
    assert AGENT_TOKEN not in harness.log
    assert ACCESS_TOKEN not in harness.log
    for line in PEM.splitlines()[1:-1]:
        assert line not in harness.log


CACHE_CREDENTIALS = (
    "[default]\naws_access_key_id = GOOGTEST\naws_secret_access_key = cache-secret"
)
CACHE_SIGNING_KEY = "maybe-ci-1:c2lnbmluZy1rZXk="


def cache_metadata(cloud: FakeCloud) -> list[dict[str, str]]:
    return [
        {
            item["key"]: item["value"]
            for item in body["metadata"]["items"]
            if item["key"].startswith("ci-cache-")
        }
        for body in cloud.inserted
    ]


def test_cycle_cache_secrets_are_sent_to_builders_and_never_logged(
    tmp_path: Path,
) -> None:
    harness = Harness(tmp_path, cache=(CACHE_CREDENTIALS, CACHE_SIGNING_KEY))
    harness.cloud.scheduled = 1
    harness.cloud.echo = f"{CACHE_CREDENTIALS} {CACHE_SIGNING_KEY}"
    harness.cloud.insert_errors[(C4D, "us-central1-a")] = "http"

    harness.cycle()

    sent = cache_metadata(harness.cloud)
    assert sent and all(
        metadata
        == {
            "ci-cache-credentials": CACHE_CREDENTIALS,
            "ci-cache-signing-key": CACHE_SIGNING_KEY,
        }
        for metadata in sent
    )
    assert "Quota exceeded <redacted>" in harness.log
    assert "cache-secret" not in harness.log
    assert "c2lnbmluZy1rZXk=" not in harness.log


def test_cycle_missing_cache_secret_launches_without_cache_and_reports_once(
    tmp_path: Path,
) -> None:
    harness = Harness(tmp_path, cache=(CACHE_CREDENTIALS, None))
    harness.cloud.scheduled = 2

    harness.cycles(2)

    assert harness.cloud.inserted
    assert all(not metadata for metadata in cache_metadata(harness.cloud))
    assert harness.log.count("do not upload to the CI cache") == 1
    assert "cache-secret" not in harness.log


def test_config_one_cache_path_is_rejected(tmp_path: Path) -> None:
    script = tmp_path / "startup-script.sh"
    script.write_text(STARTUP_SCRIPT)
    with pytest.raises(poller.ConfigError, match="CI_CACHE_SIGNING_KEY_PATH"):
        poller.config_from_env(
            {
                "BUILDKITE_AGENT_TOKEN_PATH": "/run/token",
                "GCP_KEY_PATH": "/run/key",
                "CI_BUILDER_SYSTEM_FILE": "/var/lib/system",
                "CI_BUILDER_STARTUP_SCRIPT": str(script),
                "CI_SPOT_FALLBACK_REQUEST": "/run/request",
                "CI_CACHE_CREDENTIALS_PATH": "/run/credentials",
            }
        )


def test_config_zone_outside_region_is_rejected(tmp_path: Path) -> None:
    script = tmp_path / "startup-script.sh"
    script.write_text(STARTUP_SCRIPT)
    with pytest.raises(poller.ConfigError, match="CI_SPOT_ZONES"):
        poller.config_from_env(
            {
                "BUILDKITE_AGENT_TOKEN_PATH": "/run/token",
                "GCP_KEY_PATH": "/run/key",
                "CI_BUILDER_SYSTEM_FILE": "/var/lib/system",
                "CI_BUILDER_STARTUP_SCRIPT": str(script),
                "CI_SPOT_FALLBACK_REQUEST": "/run/request",
                "CI_SPOT_ZONES": "us-central1-a,us-east1-b",
            }
        )
