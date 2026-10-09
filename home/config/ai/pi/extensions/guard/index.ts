import * as os from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { classify, type Role } from "./rules.ts";

function roleFromEnvironment(value: string | undefined): Role {
	return value === "worker" || value === "reviewer" ? value : "main";
}

function describeCall(toolName: string, input: Record<string, unknown>): string {
	if (typeof input.command === "string") return input.command;
	if (typeof input.path === "string") return `${toolName} ${input.path}`;
	return toolName;
}

export default function (pi: ExtensionAPI) {
	const role = roleFromEnvironment(process.env.PI_LOOP_ROLE);
	const scratch = process.env.PI_LOOP_SCRATCH || undefined;
	const home = os.homedir();

	pi.on("tool_call", async (event, ctx) => {
		const input = event.input as Record<string, unknown>;
		const decision = classify(event.toolName, input, role, { home, scratch, cwd: ctx.cwd });
		if (decision.action === "allow") return undefined;
		if (decision.action === "confirm" && role === "main" && ctx.hasUI) {
			const approved = await ctx.ui.confirm(
				`Allow ${event.toolName}?`,
				`${describeCall(event.toolName, input)}\n\n${decision.reason}`,
			);
			if (approved) return undefined;
			return { block: true, reason: `${event.toolName} call was not approved by the user: ${decision.reason}` };
		}
		const scope =
			decision.action === "confirm" ? " (it needs user approval and no UI is available)" : role === "main" ? "" : ` for the ${role}`;
		return {
			block: true,
			reason: `Blocked by the guard${scope}: ${decision.reason}. Do not work around this; report it instead.`,
		};
	});
}
