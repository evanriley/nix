import base64
import http.client
import json
import os
import re
import secrets
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Protocol, TextIO

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

METRICS_URL = "https://agent.buildkite.com/v3/metrics"
TOKEN_URI = "https://oauth2.googleapis.com/token"
COMPUTE = "https://compute.googleapis.com/compute/v1"
SCOPE = "https://www.googleapis.com/auth/compute"
GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer"
REGION = "us-central1"
SUBNETWORK = "maybe-ci-us-central1"
IMAGE_FAMILY = "ci-builder"
LABEL = "maybe-ci"
LABEL_FILTER = 'labels.maybe-ci = "true"'
SHAPES = ("c4d-highcpu-32", "c3d-highcpu-30")
DEFAULT_ZONES = "us-central1-a,us-central1-b,us-central1-c,us-central1-f"
DEAD = frozenset({"TERMINATED", "STOPPED", "SUSPENDED"})
SYSTEM_PATTERN = re.compile(
    r"/nix/store/[0-9a-df-np-sv-z]{32}-nixos-system-[0-9A-Za-z+._?=-]+"
)
PROJECT_PATTERN = re.compile(r"[a-z][a-z0-9-]{4,28}[a-z0-9]")
ZONE_PATTERN = re.compile(re.escape(REGION) + r"-[a-z]")
NAME_PATTERN = re.compile(r"[a-z]([-a-z0-9]{0,61}[a-z0-9])?")
OPERATION_PATTERN = re.compile(r"[-a-zA-Z0-9_]{1,128}")

INTERVAL = 30.0
REQUEST_TIMEOUT = 30.0
WAIT_TIMEOUT = 130.0
LAUNCH_BUDGET = 120.0
NOT_READY_GRACE = 15 * 60
MAX_AGE = 6 * 3600 + 15 * 60
RUN_DURATION = 6 * 3600
NO_READY_FALLBACK = 5 * 60
REDELETE_AFTER = 5 * 60
TOKEN_MARGIN = 300
MAX_PAGES = 20
LOG_LIMIT = 4000


class ConfigError(Exception):
    pass


class CredentialsError(Exception):
    pass


class ApiError(Exception):
    pass


class NotFound(ApiError):
    pass


class Unreachable(ApiError):
    pass


class TransportError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class Response:
    status: int
    body: bytes


class Transport(Protocol):
    def request(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> Response: ...


class Clock(Protocol):
    def time(self) -> float: ...

    def monotonic(self) -> float: ...

    def sleep(self, seconds: float) -> None: ...


class UrllibTransport:
    def request(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> Response:
        request = urllib.request.Request(
            url, data=body, headers=dict(headers), method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return Response(response.status, response.read())
        except urllib.error.HTTPError as error:
            try:
                return Response(error.code, error.read())
            except (OSError, http.client.HTTPException):
                return Response(error.code, b"")
        except (OSError, http.client.HTTPException) as error:
            raise TransportError(str(error) or type(error).__name__) from error


class SystemClock:
    def time(self) -> float:
        return time.time()

    def monotonic(self) -> float:
        return time.monotonic()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


class Log:
    def __init__(self, stream: TextIO) -> None:
        self._stream = stream
        self._secrets: dict[str, tuple[str, ...]] = {}

    def secret(self, role: str, *values: str) -> None:
        self._secrets[role] = tuple(value for value in values if value)

    def __call__(self, message: str) -> None:
        values = [value for group in self._secrets.values() for value in group]
        for value in sorted(values, key=len, reverse=True):
            message = message.replace(value, "<redacted>")
        if len(message) > LOG_LIMIT:
            message = message[:LOG_LIMIT] + " [truncated]"
        print(message, file=self._stream, flush=True)


@dataclass(frozen=True, slots=True)
class Config:
    agent_token_path: Path
    gcp_key_path: Path
    system_file: Path
    startup_script: str
    fallback_request: Path
    queue: str
    max_instances: int
    zones: tuple[str, ...]


def config_from_env(env: Mapping[str, str]) -> Config:
    def required(name: str) -> str:
        value = env.get(name, "")
        if not value:
            raise ConfigError(
                f"{name} is not set; expected a path. Set it in the "
                "ci-spot-poller unit's environment"
            )
        return value

    startup_path = Path(required("CI_BUILDER_STARTUP_SCRIPT"))
    try:
        startup_script = startup_path.read_text()
    except OSError as error:
        raise ConfigError(
            f"reading the startup script {startup_path} failed: "
            f"{error.strerror}; expected meta.ciBuilderStartupScript"
        ) from error

    raw_max = env.get("CI_SPOT_MAX_INSTANCES", "3")
    try:
        max_instances = int(raw_max)
    except ValueError:
        max_instances = -1
    if max_instances < 0:
        raise ConfigError(
            f"CI_SPOT_MAX_INSTANCES is {raw_max!r}; expected a "
            "non-negative integer"
        )

    raw_zones = env.get("CI_SPOT_ZONES", DEFAULT_ZONES)
    zones = tuple(zone.strip() for zone in raw_zones.split(",") if zone)
    if not zones or not all(ZONE_PATTERN.fullmatch(z) for z in zones):
        raise ConfigError(
            f"CI_SPOT_ZONES is {raw_zones!r}; expected comma-separated "
            f"{REGION} zones, because the subnetwork {SUBNETWORK} is "
            f"in {REGION}"
        )

    return Config(
        agent_token_path=Path(required("BUILDKITE_AGENT_TOKEN_PATH")),
        gcp_key_path=Path(required("GCP_KEY_PATH")),
        system_file=Path(required("CI_BUILDER_SYSTEM_FILE")),
        startup_script=startup_script,
        fallback_request=Path(required("CI_SPOT_FALLBACK_REQUEST")),
        queue=env.get("CI_SPOT_QUEUE", "spot-builders"),
        max_instances=max_instances,
        zones=zones,
    )


@dataclass(frozen=True, slots=True)
class ServiceAccount:
    project: str
    email: str
    key_id: str
    key: rsa.RSAPrivateKey


@dataclass(frozen=True, slots=True)
class AccessToken:
    key_id: str
    value: str
    expires: float


@dataclass(frozen=True, slots=True)
class Metrics:
    scheduled: int
    idle: int
    busy: int


@dataclass(frozen=True, slots=True)
class Instance:
    name: str
    zone: str
    status: str
    created: float


@dataclass(frozen=True, slots=True)
class Inventory:
    instances: tuple[Instance, ...]
    complete: bool


class Readiness(Enum):
    READY = "ready"
    NOT_READY = "not ready"
    UNKNOWN = "unknown"


class Outcome(Enum):
    LAUNCHED = "launched"
    FAILED = "failed"
    UNDETERMINED = "undetermined"


@dataclass(slots=True)
class Launches:
    attempts: int = 0
    failures: int = 0
    started: int = 0


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def sign_assertion(account: ServiceAccount, issued: int) -> str:
    header = {"alg": "RS256", "typ": "JWT", "kid": account.key_id}
    claims = {
        "iss": account.email,
        "scope": SCOPE,
        "aud": TOKEN_URI,
        "iat": issued,
        "exp": issued + 3600,
    }
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode())
        for part in (header, claims)
    )
    signature = account.key.sign(
        signing_input.encode(), padding.PKCS1v15(), hashes.SHA256()
    )
    return f"{signing_input}.{b64url(signature)}"


def parse_object(body: bytes, what: str) -> dict[str, object]:
    try:
        value = json.loads(body)
    except (ValueError, UnicodeDecodeError) as error:
        raise ApiError(f"{what} answered with invalid JSON") from error
    return expect_object(value, what)


def expect_object(value: object, what: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise ApiError(f"{what} answered without the expected JSON object")
    return value


def expect_str(value: object, what: str) -> str:
    if not isinstance(value, str) or not value:
        raise ApiError(f"{what} is missing or not a string")
    return value


def expect_count(value: object, what: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ApiError(f"{what} is {value!r}; expected a count")
    return value


def error_message(body: bytes) -> str:
    try:
        data = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return body.decode(errors="replace").strip() or "no body"
    if isinstance(data, dict):
        error = data.get("error")
        if isinstance(error, dict) and isinstance(error.get("message"), str):
            return error["message"]
        description = data.get("error_description")
        if isinstance(error, str):
            if isinstance(description, str):
                return f"{error}: {description}"
            return error
        if isinstance(data.get("message"), str):
            return data["message"]
    return "no error message"


def operation_errors(operation: dict[str, object]) -> str | None:
    error = operation.get("error")
    if not isinstance(error, dict):
        return None
    errors = error.get("errors")
    if not isinstance(errors, list) or not errors:
        return "the operation reported an error without details"
    parts = []
    for item in errors:
        if isinstance(item, dict):
            parts.append(f"{item.get('code')}: {item.get('message')}")
    return "; ".join(parts) or "the operation reported an error"


def read_system(path: Path) -> tuple[str | None, str]:
    try:
        raw = path.read_text()
    except FileNotFoundError:
        return None, (
            f"{path} does not exist; the main agent writes it when it "
            "publishes a ci-builder system from main. Run a main build"
        )
    except (OSError, UnicodeDecodeError) as error:
        return None, f"reading {path} failed: {error}"
    system = raw.removesuffix("\n")
    if not SYSTEM_PATTERN.fullmatch(system):
        return None, (
            f"{path} does not hold one /nix/store/<hash>-nixos-system-* "
            "path; publish a ci-builder system from main to rewrite it"
        )
    return system, f"{path} holds {system}"


def instance_body(
    account: ServiceAccount,
    name: str,
    shape: str,
    zone: str,
    metadata: Mapping[str, str],
) -> dict[str, object]:
    project = account.project
    return {
        "name": name,
        "machineType": f"zones/{zone}/machineTypes/{shape}",
        "labels": {LABEL: "true"},
        "disks": [
            {
                "boot": True,
                "autoDelete": True,
                "initializeParams": {
                    "sourceImage": (
                        f"projects/{project}/global/images/family/"
                        f"{IMAGE_FAMILY}"
                    ),
                    "diskType": f"zones/{zone}/diskTypes/hyperdisk-balanced",
                    "diskSizeGb": "60",
                    "provisionedIops": "6000",
                    "provisionedThroughput": "400",
                },
            }
        ],
        "networkInterfaces": [
            {
                "subnetwork": (
                    f"projects/{project}/regions/{REGION}/subnetworks/"
                    f"{SUBNETWORK}"
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
            "maxRunDuration": {"seconds": str(RUN_DURATION)},
            "automaticRestart": False,
            "onHostMaintenance": "TERMINATE",
        },
        "metadata": {
            "items": [
                {"key": key, "value": value} for key, value in metadata.items()
            ]
        },
    }


class Poller:
    def __init__(
        self,
        config: Config,
        transport: Transport,
        clock: Clock,
        log: Log,
    ) -> None:
        self._config = config
        self._transport = transport
        self._clock = clock
        self._log = log
        self._token: AccessToken | None = None
        self._problems: dict[str, str] = {}
        self._system_state: str | None = None
        self._ready: set[str] = set()
        self._launching: dict[str, float] = {}
        self._deleting: dict[str, float] = {}
        self._no_ready_since: float | None = None
        self._fallback: str = ""

    def run(self) -> None:
        config = self._config
        self._log(
            f"watching queue {config.queue}; at most "
            f"{config.max_instances} instances in {', '.join(config.zones)}"
        )
        while True:
            started = self._clock.monotonic()
            try:
                self.cycle()
            except Exception:
                self._log(
                    "the cycle failed unexpectedly; retrying in 30 s:\n"
                    + traceback.format_exc()
                )
            elapsed = self._clock.monotonic() - started
            self._clock.sleep(max(0.0, INTERVAL - elapsed))

    def cycle(self) -> None:
        token = self._agent_token()
        metrics = self._metrics(token) if token is not None else None
        system = self._system()
        account = self._account()
        inventory = self._inventory(account) if account else None

        live = 0
        ready = 0
        pending = 0
        if account is not None and inventory is not None:
            live, ready, pending = self._reconcile(account, inventory)

        launches = Launches()
        if (
            metrics is not None
            and account is not None
            and inventory is not None
            and inventory.complete
            and token is not None
            and system is not None
        ):
            wanted = max(0, metrics.scheduled - metrics.idle - pending)
            room = max(0, self._config.max_instances - live)
            count = min(wanted, room)
            if count:
                self._log(
                    f"{metrics.scheduled} scheduled, {metrics.idle} idle, "
                    f"{pending} starting, {live} live; launching {count}"
                )
                launches = self._launch(account, token, system, count)

        self._decide_fallback(metrics, system, live, ready, launches)

    def _report(self, source: str, problem: str | None) -> None:
        previous = self._problems.get(source)
        if problem is None:
            if previous is not None:
                del self._problems[source]
                self._log(f"{source} recovered")
            return
        if problem != previous:
            self._problems[source] = problem
            self._log(f"{problem}; retrying every 30 s")

    def _agent_token(self) -> str | None:
        path = self._config.agent_token_path
        try:
            token = path.read_text().strip()
        except (OSError, UnicodeDecodeError) as error:
            self._report(
                "buildkite-token",
                f"reading the Buildkite agent token {path} failed: {error}. "
                "Check the buildkite-token secret",
            )
            return None
        if not token:
            self._report(
                "buildkite-token",
                f"the Buildkite agent token {path} is empty. Check the "
                "buildkite-token secret",
            )
            return None
        self._log.secret("buildkite-agent-token", token)
        self._report("buildkite-token", None)
        return token

    def _metrics(self, token: str) -> Metrics | None:
        queue = self._config.queue
        try:
            response = self._send(
                "GET",
                METRICS_URL,
                {"Authorization": f"Token {token}"},
                None,
                REQUEST_TIMEOUT,
            )
            if response.status != 200:
                raise ApiError(
                    f"HTTP {response.status}: {error_message(response.body)}"
                )
            data = parse_object(response.body, "Buildkite metrics")
            jobs = self._queue(data, "jobs", queue)
            agents = self._queue(data, "agents", queue)
            metrics = Metrics(
                scheduled=expect_count(
                    jobs.get("scheduled", 0), "jobs.scheduled"
                ),
                idle=expect_count(agents.get("idle", 0), "agents.idle"),
                busy=expect_count(agents.get("busy", 0), "agents.busy"),
            )
        except ApiError as error:
            self._report(
                "buildkite-metrics",
                f"reading Buildkite queue metrics failed: {error}. Check the "
                "buildkite-token secret and agent.buildkite.com; nothing is "
                "launched until metrics return",
            )
            return None
        self._report("buildkite-metrics", None)
        return metrics

    @staticmethod
    def _queue(
        data: dict[str, object], section: str, queue: str
    ) -> dict[str, object]:
        part = expect_object(data.get(section), f"metrics {section}")
        queues = expect_object(
            part.get("queues", {}), f"metrics {section}.queues"
        )
        if queue not in queues:
            return {}
        return expect_object(queues[queue], f"metrics {section}.{queue}")

    def _system(self) -> str | None:
        system, state = read_system(self._config.system_file)
        if state != self._system_state:
            self._system_state = state
            if system is None:
                self._log(f"{state}; launching nothing until it is fixed")
            else:
                self._log(state)
        return system

    def _account(self) -> ServiceAccount | None:
        path = self._config.gcp_key_path
        try:
            account = self._load_account(path)
        except CredentialsError as error:
            self._token = None
            self._report("gcp-key", str(error))
            return None
        self._report("gcp-key", None)
        return account

    def _load_account(self, path: Path) -> ServiceAccount:
        advice = (
            "expected a service-account JSON key for maybe-ci-spot. "
            "Encrypt one into nix/secrets/blaziken/gcp-ci-key.age"
        )
        try:
            text = path.read_text()
        except (OSError, UnicodeDecodeError) as error:
            raise CredentialsError(
                f"reading the GCP key {path} failed: {error}; {advice}"
            ) from error
        try:
            data = json.loads(text)
        except ValueError:
            raise CredentialsError(
                f"the GCP key {path} is not JSON; {advice}"
            ) from None
        if not isinstance(data, dict):
            raise CredentialsError(f"the GCP key {path} is invalid; {advice}")
        fields = {}
        for field in ("project_id", "client_email", "private_key_id"):
            value = data.get(field)
            if not isinstance(value, str) or not value:
                raise CredentialsError(
                    f"the GCP key {path} has no {field}; {advice}"
                )
            fields[field] = value
        pem = data.get("private_key")
        if not isinstance(pem, str) or not pem:
            raise CredentialsError(
                f"the GCP key {path} has no private_key; {advice}"
            )
        self._log.secret(
            "gcp-private-key",
            pem,
            *(
                line
                for line in pem.splitlines()
                if len(line) >= 16 and not line.startswith("-----")
            ),
        )
        if not PROJECT_PATTERN.fullmatch(fields["project_id"]):
            raise CredentialsError(
                f"the GCP key {path} has an invalid project_id; {advice}"
            )
        try:
            key = serialization.load_pem_private_key(
                pem.encode(), password=None
            )
        except (ValueError, TypeError):
            raise CredentialsError(
                f"the private_key in the GCP key {path} does not load; "
                f"{advice}"
            ) from None
        if not isinstance(key, rsa.RSAPrivateKey):
            raise CredentialsError(
                f"the private_key in the GCP key {path} is not RSA; {advice}"
            )
        return ServiceAccount(
            project=fields["project_id"],
            email=fields["client_email"],
            key_id=fields["private_key_id"],
            key=key,
        )

    def _send(
        self,
        method: str,
        url: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> Response:
        try:
            return self._transport.request(method, url, headers, body, timeout)
        except TransportError as error:
            target = url.split("?", 1)[0]
            raise Unreachable(f"{method} {target}: {error}") from error

    def _access_token(self, account: ServiceAccount) -> str:
        now = self._clock.monotonic()
        cached = self._token
        if (
            cached is not None
            and cached.key_id == account.key_id
            and now < cached.expires
        ):
            return cached.value
        assertion = sign_assertion(account, int(self._clock.time()))
        self._log.secret("gcp-assertion", assertion)
        body = urllib.parse.urlencode(
            {"grant_type": GRANT_TYPE, "assertion": assertion}
        ).encode()
        response = self._send(
            "POST",
            TOKEN_URI,
            {"Content-Type": "application/x-www-form-urlencoded"},
            body,
            REQUEST_TIMEOUT,
        )
        if response.status != 200:
            raise ApiError(
                f"exchanging key {account.key_id} of {account.email} for an "
                f"access token returned HTTP {response.status}: "
                f"{error_message(response.body)}. Check that the key is "
                "active and blaziken's clock is right"
            )
        data = parse_object(response.body, "the GCP token endpoint")
        value = expect_str(data.get("access_token"), "access_token")
        lifetime = expect_count(data.get("expires_in"), "expires_in")
        self._log.secret("gcp-access-token", value)
        self._token = AccessToken(
            key_id=account.key_id,
            value=value,
            expires=now + max(0, lifetime - TOKEN_MARGIN),
        )
        return value

    def _gcp(
        self,
        account: ServiceAccount,
        method: str,
        url: str,
        body: object | None = None,
        timeout: float = REQUEST_TIMEOUT,
    ) -> dict[str, object]:
        headers = {"Authorization": f"Bearer {self._access_token(account)}"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        elif method == "POST":
            data = b""
        response = self._send(method, url, headers, data, timeout)
        target = url.split("?", 1)[0].removeprefix(COMPUTE)
        if response.status == 401:
            self._token = None
        if response.status == 404:
            raise NotFound(f"{method} {target}: not found")
        if not 200 <= response.status < 300:
            raise ApiError(
                f"{method} {target} returned HTTP {response.status}: "
                f"{error_message(response.body)}"
            )
        return parse_object(response.body, f"{method} {target}")

    def _inventory(self, account: ServiceAccount) -> Inventory | None:
        try:
            inventory = self._list(account)
        except ApiError as error:
            self._report(
                "gcp-inventory",
                f"listing {LABEL} instances failed: {error}. Check the "
                "gcp-ci-key secret and the maybeCiSpot role; nothing is "
                "launched or deleted until listing works",
            )
            return None
        self._report("gcp-inventory", None)
        return inventory

    def _list(self, account: ServiceAccount) -> Inventory:
        instances: list[Instance] = []
        problems: list[str] = []
        page = ""
        for _ in range(MAX_PAGES):
            query = {"filter": LABEL_FILTER, "maxResults": "500"}
            if page:
                query["pageToken"] = page
            data = self._gcp(
                account,
                "GET",
                f"{COMPUTE}/projects/{account.project}/aggregated/instances?"
                + urllib.parse.urlencode(query),
            )
            items = expect_object(data.get("items", {}), "items")
            for scope, entry in items.items():
                entry = expect_object(entry, f"items[{scope}]")
                warning = entry.get("warning")
                if isinstance(warning, dict):
                    code = warning.get("code")
                    if code != "NO_RESULTS_ON_PAGE":
                        problems.append(f"{scope}: {code}")
                raws = entry.get("instances", [])
                if not isinstance(raws, list):
                    raise ApiError(f"items[{scope}].instances is not a list")
                for raw in raws:
                    instance = self._parse_instance(raw)
                    if instance is not None:
                        instances.append(instance)
            unreachables = data.get("unreachables")
            if unreachables:
                problems.append(f"unreachable: {unreachables}")
            next_page = data.get("nextPageToken", "")
            if not isinstance(next_page, str):
                raise ApiError("nextPageToken is not a string")
            if not next_page:
                break
            page = next_page
        else:
            problems.append(f"more than {MAX_PAGES} pages")
        if problems:
            self._report(
                "gcp-inventory-partial",
                "the instance list is incomplete ("
                + "; ".join(problems)
                + "); deleting only listed instances and launching nothing",
            )
        else:
            self._report("gcp-inventory-partial", None)
        return Inventory(tuple(instances), not problems)

    @staticmethod
    def _parse_instance(raw: object) -> Instance | None:
        data = expect_object(raw, "instance")
        labels = data.get("labels") or {}
        if not isinstance(labels, dict) or labels.get(LABEL) != "true":
            return None
        name = expect_str(data.get("name"), "instance name")
        zone = expect_str(data.get("zone"), "instance zone").rsplit("/")[-1]
        if not NAME_PATTERN.fullmatch(name) or not NAME_PATTERN.fullmatch(
            zone
        ):
            raise ApiError(f"instance {name!r} in {zone!r} has a bad name")
        stamp = expect_str(data.get("creationTimestamp"), "creationTimestamp")
        try:
            created = datetime.fromisoformat(stamp).timestamp()
        except ValueError:
            raise ApiError(
                f"instance {name} has creationTimestamp {stamp!r}"
            ) from None
        return Instance(
            name=name,
            zone=zone,
            status=expect_str(data.get("status"), "instance status"),
            created=created,
        )

    def _readiness(
        self, account: ServiceAccount, instance: Instance
    ) -> Readiness:
        if instance.name in self._ready:
            return Readiness.READY
        if instance.status != "RUNNING":
            return Readiness.NOT_READY
        url = (
            f"{COMPUTE}/projects/{account.project}/zones/{instance.zone}/"
            f"instances/{instance.name}/getGuestAttributes?"
            + urllib.parse.urlencode({"queryPath": "ci-builder/"})
        )
        try:
            data = self._gcp(account, "GET", url)
        except NotFound:
            return Readiness.NOT_READY
        except ApiError as error:
            self._log(
                f"reading guest attributes of {instance.name} failed: "
                f"{error}; keeping it until they can be read"
            )
            return Readiness.UNKNOWN
        value = data.get("queryValue")
        items = value.get("items") if isinstance(value, dict) else None
        for item in items if isinstance(items, list) else []:
            if (
                isinstance(item, dict)
                and item.get("namespace") == "ci-builder"
                and item.get("key") == "ready"
            ):
                self._ready.add(instance.name)
                self._log(f"{instance.name} is ready")
                return Readiness.READY
        return Readiness.NOT_READY

    def _reconcile(
        self, account: ServiceAccount, inventory: Inventory
    ) -> tuple[int, int, int]:
        now = self._clock.time()
        listed = {instance.name for instance in inventory.instances}
        self._ready &= listed
        self._deleting = {
            name: at for name, at in self._deleting.items() if name in listed
        }
        self._launching = {
            name: at
            for name, at in self._launching.items()
            if name not in listed and now - at < NOT_READY_GRACE
        }

        live = len(self._launching)
        ready = 0
        pending = len(self._launching)
        for instance in inventory.instances:
            readiness = self._readiness(account, instance)
            reason = self._delete_reason(instance, readiness, now)
            if reason is not None:
                self._delete(account, instance, reason, now)
            if instance.status in DEAD:
                continue
            live += 1
            if instance.name in self._deleting:
                continue
            if readiness is Readiness.READY:
                if instance.status == "RUNNING":
                    ready += 1
            else:
                pending += 1
        return live, ready, pending

    @staticmethod
    def _delete_reason(
        instance: Instance, readiness: Readiness, now: float
    ) -> str | None:
        age = now - instance.created
        if instance.status in DEAD:
            return f"it is {instance.status}"
        if age > MAX_AGE:
            return "it is older than 6 h 15 min"
        if age > NOT_READY_GRACE and readiness is Readiness.NOT_READY:
            return "it has not set ci-builder/ready within 15 min"
        return None

    def _delete(
        self,
        account: ServiceAccount,
        instance: Instance,
        reason: str,
        now: float,
    ) -> None:
        requested = self._deleting.get(instance.name)
        if requested is not None and now - requested < REDELETE_AFTER:
            return
        url = (
            f"{COMPUTE}/projects/{account.project}/zones/{instance.zone}/"
            f"instances/{instance.name}"
        )
        self._log(f"deleting {instance.name} in {instance.zone}: {reason}")
        try:
            self._gcp(account, "DELETE", url)
        except NotFound:
            pass
        except ApiError as error:
            self._log(
                f"deleting {instance.name} failed: {error}; retrying next "
                "cycle"
            )
            return
        self._deleting[instance.name] = now

    def _launch(
        self,
        account: ServiceAccount,
        token: str,
        system: str,
        count: int,
    ) -> Launches:
        metadata = {
            "startup-script": self._config.startup_script,
            "buildkite-agent-token": token,
            "ci-builder-system": system,
            "enable-guest-attributes": "TRUE",
            "block-project-ssh-keys": "TRUE",
            "enable-oslogin": "FALSE",
            "serial-port-enable": "FALSE",
        }
        candidates = [
            (shape, zone) for shape in SHAPES for zone in self._config.zones
        ]
        failed: set[tuple[str, str]] = set()
        launches = Launches()
        deadline = self._clock.monotonic() + LAUNCH_BUDGET
        for _ in range(count):
            for shape, zone in candidates:
                if (shape, zone) in failed:
                    continue
                if self._clock.monotonic() >= deadline:
                    self._log(
                        f"the {LAUNCH_BUDGET:.0f} s launch budget ran out; "
                        "continuing next cycle"
                    )
                    return launches
                launches.attempts += 1
                outcome = self._insert(
                    account, shape, zone, metadata, deadline
                )
                if outcome is Outcome.FAILED:
                    launches.failures += 1
                    failed.add((shape, zone))
                    continue
                launches.started += 1
                break
            else:
                self._log(
                    "every shape and zone failed this cycle; retrying next "
                    "cycle"
                )
                return launches
        return launches

    def _insert(
        self,
        account: ServiceAccount,
        shape: str,
        zone: str,
        metadata: Mapping[str, str],
        deadline: float,
    ) -> Outcome:
        name = f"{LABEL}-{secrets.token_hex(4)}"
        body = instance_body(account, name, shape, zone, metadata)
        zone_url = f"{COMPUTE}/projects/{account.project}/zones/{zone}"
        try:
            operation = self._gcp(
                account, "POST", f"{zone_url}/instances", body
            )
        except Unreachable as error:
            self._launching[name] = self._clock.time()
            self._log(
                f"inserting {name} ({shape} in {zone}) got no answer: "
                f"{error}; it counts as starting until it is listed"
            )
            return Outcome.UNDETERMINED
        except ApiError as error:
            self._log(
                f"inserting {shape} in {zone} failed: {error}; trying the "
                "next zone or shape"
            )
            return Outcome.FAILED
        self._launching[name] = self._clock.time()
        while True:
            if operation.get("status") == "DONE":
                errors = operation_errors(operation)
                if errors is not None:
                    self._launching.pop(name, None)
                    self._log(
                        f"inserting {shape} in {zone} failed: {errors}; "
                        "trying the next zone or shape"
                    )
                    return Outcome.FAILED
                self._log(f"launched {name} ({shape} in {zone})")
                return Outcome.LAUNCHED
            remaining = deadline - self._clock.monotonic()
            operation_name = operation.get("name")
            if remaining <= 0 or not (
                isinstance(operation_name, str)
                and OPERATION_PATTERN.fullmatch(operation_name)
            ):
                self._log(
                    f"{name} ({shape} in {zone}) is still starting; it "
                    "counts as starting until it is listed"
                )
                return Outcome.UNDETERMINED
            try:
                operation = self._gcp(
                    account,
                    "POST",
                    f"{zone_url}/operations/{operation_name}/wait",
                    timeout=min(remaining, WAIT_TIMEOUT),
                )
            except ApiError as error:
                self._log(
                    f"waiting for {name} ({shape} in {zone}) failed: "
                    f"{error}; it counts as starting until it is listed"
                )
                return Outcome.UNDETERMINED

    def _decide_fallback(
        self,
        metrics: Metrics | None,
        system: str | None,
        live: int,
        ready: int,
        launches: Launches,
    ) -> None:
        if metrics is None:
            return
        now = self._clock.monotonic()
        if metrics.scheduled > 0 and ready == 0:
            if self._no_ready_since is None:
                self._no_ready_since = now
        else:
            self._no_ready_since = None

        reasons = []
        if metrics.scheduled > 0:
            if (
                launches.attempts
                and launches.failures == launches.attempts
                and live == 0
            ):
                reasons.append("every launch failed and none is live")
            if system is None:
                reasons.append("ci-builder-system is missing or invalid")
            since = self._no_ready_since
            if since is not None and now - since >= NO_READY_FALLBACK:
                reasons.append("no spot builder has been ready for 5 min")
        reason = "; ".join(reasons)

        if reason != self._fallback:
            if reason:
                self._log(f"starting the fallback agent: {reason}")
            else:
                self._log("the fallback agent is no longer needed")
            self._fallback = reason
        if not reason:
            return
        path = self._config.fallback_request
        try:
            path.write_text(f"{int(self._clock.time())}\n")
        except OSError as error:
            self._report(
                "fallback",
                f"writing {path} failed: {error}. Check that "
                "/run/ci-spot-fallback exists and belongs to "
                "buildkite-agent-main",
            )
            return
        self._report("fallback", None)


def main() -> None:
    try:
        config = config_from_env(os.environ)
    except ConfigError as error:
        print(error, file=sys.stderr, flush=True)
        sys.exit(1)
    Poller(config, UrllibTransport(), SystemClock(), Log(sys.stderr)).run()


if __name__ == "__main__":
    main()
