import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8470"))
API = (
    "https://api.buildkite.com/v2/organizations/"
    "riley-industries/pipelines/maybe/builds"
)
TOKEN_PATH = os.environ.get("BUILDKITE_REST_TOKEN_PATH")


def trigger(commit: str, branch: str, message: str, env: dict) -> None:
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
    with urllib.request.urlopen(req, timeout=4) as resp:
        number = json.load(resp)["number"]
        print(f"triggered build {number} for {message}", flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        if self.path != "/gerrit":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        event = json.loads(self.rfile.read(length) or b"{}")
        try:
            self.dispatch(event)
        except Exception as exc:
            self.send_error(500, str(exc))
            return
        self.send_response(204)
        self.end_headers()

    def dispatch(self, event: dict) -> None:
        kind = event.get("type")
        if kind == "patchset-created":
            change = event.get("change", {})
            if change.get("project") != "maybe":
                return
            number = change["number"]
            patchset = event["patchSet"]["number"]
            trigger(
                event["patchSet"]["revision"],
                change.get("branch", "main"),
                f"Gerrit change {number} patchset {patchset}",
                {
                    "GERRIT_PATCHSET": f"{number},{patchset}",
                    "BUILDKITE_FETCH_DIFF_BASE": "true",
                },
            )
        elif kind == "ref-updated":
            update = event.get("refUpdate", {})
            if update.get("project") != "maybe":
                return
            # Patchset pushes also fire ref-updated on refs/changes/*;
            # patchset-created already covers those.
            ref = update.get("refName", "")
            if not ref.startswith("refs/heads/"):
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
            branch = ref.removeprefix("refs/heads/")
            trigger(sha, branch, f"{sha[:12]} on {branch}", env)


def main() -> None:
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
