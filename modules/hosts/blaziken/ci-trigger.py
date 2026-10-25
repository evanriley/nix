import json
import os
import subprocess
import sys
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import NamedTuple

PORT = int(os.environ.get("PORT", "8470"))
API = os.environ.get(
    "BUILDKITE_API_URL",
    "https://api.buildkite.com/v2/organizations/"
    "riley-industries/pipelines/maybe/builds",
)
TOKEN_PATH = os.environ.get("BUILDKITE_REST_TOKEN_PATH")
GERRIT_SSH_KEY_PATH = os.environ.get("GERRIT_SSH_KEY_PATH")
GERRIT_KNOWN_HOSTS_PATH = os.environ.get("GERRIT_KNOWN_HOSTS_PATH")
GERRIT_SSH_DESTINATION = os.environ.get("GERRIT_SSH_DESTINATION")
GERRIT_TIMEOUT_SECONDS = 60
AUTOSUBMIT_QUERY = (
    "project:maybe branch:main status:open label:Autosubmit=+1 is:submittable"
)
sweep_lock = threading.Lock()


class SubmittableChange(NamedTuple):
    number: int
    patchset: int


def trigger(commit: str, branch: str, message: str, env: dict) -> str:
    body = {
        "commit": commit,
        "branch": branch,
        "message": message,
        "env": env,
    }
    with open(TOKEN_PATH) as f:
        token = f.read().strip()
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        build = json.load(resp)
    print(f"triggered build {build['number']} for {message}", flush=True)
    return build["web_url"]


def gerrit(
    *command: str,
    input: str | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "ssh",
            "-i",
            GERRIT_SSH_KEY_PATH,
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            f"UserKnownHostsFile={GERRIT_KNOWN_HOSTS_PATH}",
            "-o",
            "StrictHostKeyChecking=yes",
            "-p",
            "29418",
            GERRIT_SSH_DESTINATION,
            "gerrit",
            *command,
        ],
        input=input,
        capture_output=True,
        text=True,
        timeout=GERRIT_TIMEOUT_SECONDS,
        check=True,
    )


def parse_submittable(output: str) -> list[SubmittableChange]:
    changes = []
    for line in output.splitlines():
        row = json.loads(line)
        if not isinstance(row, dict) or row.get("type") == "stats":
            continue
        patch_set = row.get("currentPatchSet")
        if not isinstance(patch_set, dict):
            patch_set = {}
        number = row.get("number")
        patchset = patch_set.get("number")
        if not isinstance(number, int) or not isinstance(patchset, int):
            raise ValueError(f"expected a change with numbers, got {row!r}")
        changes.append(SubmittableChange(number, patchset))
    return sorted(changes)


def submit(change: SubmittableChange) -> None:
    target = f"{change.number},{change.patchset}"
    try:
        gerrit("review", "--project", "maybe", "--submit", target)
    except subprocess.CalledProcessError as error:
        print(
            f"submitting change {change.number} patchset {change.patchset}"
            f" failed with status {error.returncode}:"
            f" {error.stderr.strip()}",
            file=sys.stderr,
            flush=True,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(
            f"submitting change {change.number} patchset {change.patchset}"
            f" failed: {error!r}",
            file=sys.stderr,
            flush=True,
        )
    else:
        print(
            f"submitted change {change.number} patchset {change.patchset}",
            flush=True,
        )


def announce(number: int, patchset: int, build_url: str) -> None:
    review = {
        "message": f"CI: started ⏳ {build_url}",
        "reviewers": [{"reviewer": "buildkite"}],
        "notify": "NONE",
    }
    try:
        gerrit(
            "review",
            "--project",
            "maybe",
            "--json",
            f"{number},{patchset}",
            input=json.dumps(review),
        )
    except subprocess.CalledProcessError as error:
        print(
            f"announcing build for change {number} patchset {patchset}"
            f" failed with status {error.returncode}:"
            f" {error.stderr.strip()}",
            file=sys.stderr,
            flush=True,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(
            f"announcing build for change {number} patchset {patchset}"
            f" failed: {error!r}",
            file=sys.stderr,
            flush=True,
        )
    else:
        print(
            f"announced build for change {number} patchset {patchset}",
            flush=True,
        )


def sweep_autosubmit() -> None:
    with sweep_lock:
        try:
            result = gerrit(
                "query",
                "--format=JSON",
                "--current-patch-set",
                AUTOSUBMIT_QUERY,
            )
            changes = parse_submittable(result.stdout)
        except subprocess.CalledProcessError as error:
            print(
                f"querying Gerrit for Autosubmit changes failed with status"
                f" {error.returncode}: {error.stderr.strip()}",
                file=sys.stderr,
                flush=True,
            )
            return
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            print(
                f"querying Gerrit for Autosubmit changes failed: {error!r}",
                file=sys.stderr,
                flush=True,
            )
            return
        for change in changes:
            submit(change)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        if self.path != "/gerrit":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        try:
            event = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            event = None
        if not isinstance(event, dict):
            self.send_error(400, "Expected a JSON object body")
            return
        self.send_response(204)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.flush()
        try:
            self.dispatch(event)
        except Exception as exc:
            update = event.get("refUpdate") or {}
            patch_set = event.get("patchSet") or {}
            ref = update.get("refName") or patch_set.get("ref")
            print(
                f"failed to handle {event.get('type')} {ref}: {exc!r}",
                file=sys.stderr,
                flush=True,
            )

    def dispatch(self, event: dict) -> None:
        kind = event.get("type")
        if kind == "patchset-created":
            change = event.get("change", {})
            if change.get("project") != "maybe":
                return
            if change.get("branch") != "main":
                return
            number = change["number"]
            patchset = event["patchSet"]["number"]
            build_url = trigger(
                event["patchSet"]["revision"],
                f"cl/{number}",
                f"Gerrit change {number} patchset {patchset}",
                {
                    "GERRIT_PATCHSET": f"{number},{patchset}",
                    "BUILDKITE_FETCH_DIFF_BASE": "true",
                    "BUILDKITE_REFSPEC": event["patchSet"]["ref"],
                },
            )
            announce(number, patchset, build_url)
        elif kind == "comment-added":
            change = event.get("change", {})
            if change.get("project") != "maybe":
                return
            if change.get("branch") != "main":
                return
            sweep_autosubmit()
        elif kind == "ref-updated":
            update = event.get("refUpdate", {})
            if update.get("project") != "maybe":
                return
            # Patchset pushes also fire ref-updated on refs/changes/*;
            # patchset-created already covers those.
            if update.get("refName") != "refs/heads/main":
                return
            sha = update["newRev"]
            old = update.get("oldRev", "")
            env = {
                "BUILDKITE_FETCH_DIFF_BASE": "true",
                "GERRIT_MERGE": "1",
            }
            if old and set(old) != {"0"}:
                # After a merge, HEAD is origin/main, so the default diff
                # base would see no changes; diff against the previous tip.
                env["BUILDKITE_GIT_DIFF_BASE"] = old
            try:
                trigger(sha, "main", f"{sha[:12]} on main", env)
            finally:
                sweep_autosubmit()


def main() -> None:
    if (
        not GERRIT_SSH_KEY_PATH
        or not GERRIT_KNOWN_HOSTS_PATH
        or not GERRIT_SSH_DESTINATION
    ):
        sys.exit(
            "GERRIT_SSH_KEY_PATH, GERRIT_KNOWN_HOSTS_PATH and"
            " GERRIT_SSH_DESTINATION must be set; ci-trigger submits"
            " Autosubmit changes over Gerrit SSH. Set them in the"
            " ci-trigger service environment"
        )
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
