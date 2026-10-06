import { spawn } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		const child = spawn("agent-notify", [], { stdio: ["pipe", "ignore", "ignore"] });
		child.on("error", () => {});
		child.stdin.on("error", () => {});
		child.stdin.end(JSON.stringify({ hook_event_name: "Stop", cwd: ctx.cwd, app: "pi" }));
	});
}
