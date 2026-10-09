import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { ImageContent, TextContent } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "vision";
const PROMPT_VERSION = "1";
const DESCRIBERS = [
	{ provider: "coralbricks", modelId: "deepseek-v4.1-flash-fast" },
	{ provider: "openrouter", modelId: "deepseek/deepseek-v4.1-flash" },
] as const;
const MAX_PARALLEL_DESCRIPTIONS = 4;
const DESCRIBE_TIMEOUT_MS = 60_000;
const DESCRIBE_MAX_TOKENS = 8192;
const DESCRIBE_REASONING = "minimal";
const REPLACEMENT_HEADER = "[Image, described by DeepSeek V4.1 Flash because the current model cannot see images]";
const NON_VISION_NOTE = "[Current model does not support images. The image will be omitted from this request.]";
const DESCRIBE_PROMPT = [
	"Describe this image for a model that cannot see it and must reason about it from your text alone.",
	"1. Transcribe all visible text verbatim, preserving line breaks, code, numbers, and punctuation.",
	"2. Describe the layout and every UI element: windows, panels, buttons, menus, fields, icons, and their states.",
	"3. Note colors where they carry meaning, such as highlights, status indicators, and syntax colors.",
	"4. Report any errors, warnings, or diagnostics in full.",
	"5. For charts and plots, give the axes, units, scales, series, and the values you can read.",
	"6. Say what the image appears to be, such as a screenshot of a specific app, a diagram, a photo, or a document.",
	"Be thorough and precise. Do not speculate beyond what is visible, and say when something is unreadable.",
].join("\n");

type Description = { ok: true; text: string } | { ok: false; reason: string };
type MessageContent = (TextContent | ImageContent)[];

const memoryCache = new Map<string, string>();
const inFlight = new Map<string, Promise<Description>>();
const waiting: (() => void)[] = [];
let running = 0;

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function cacheDirectory(): string {
	return path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "pi", "vision");
}

function imageKey(image: ImageContent): string {
	return createHash("sha256").update(PROMPT_VERSION).update(image.mimeType).update(image.data).digest("hex");
}

async function readCachedDescription(key: string): Promise<string | undefined> {
	const remembered = memoryCache.get(key);
	if (remembered !== undefined) return remembered;
	try {
		const text = await fs.readFile(path.join(cacheDirectory(), `${key}.txt`), "utf8");
		memoryCache.set(key, text);
		return text;
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
		throw error;
	}
}

async function writeCachedDescription(key: string, text: string): Promise<void> {
	const directory = cacheDirectory();
	await fs.mkdir(directory, { recursive: true });
	const target = path.join(directory, `${key}.txt`);
	const temporary = `${target}.${process.pid}.${Date.now()}.tmp`;
	try {
		await fs.writeFile(temporary, text, "utf8");
		await fs.rename(temporary, target);
	} catch (error) {
		await fs.rm(temporary, { force: true });
		throw error;
	}
	memoryCache.set(key, text);
}

async function withDescriptionSlot<T>(work: () => Promise<T>): Promise<T> {
	if (running >= MAX_PARALLEL_DESCRIPTIONS) await new Promise<void>((resolve) => waiting.push(resolve));
	else running++;
	try {
		return await work();
	} finally {
		const next = waiting.shift();
		if (next) next();
		else running--;
	}
}

async function describeWith(
	ctx: ExtensionContext,
	describer: (typeof DESCRIBERS)[number],
	image: ImageContent,
	signal: AbortSignal | undefined,
): Promise<Description> {
	const name = `${describer.provider}/${describer.modelId}`;
	const model = ctx.modelRegistry.find(describer.provider, describer.modelId);
	if (!model) return { ok: false, reason: `${name} is not in the model registry` };
	const timeout = AbortSignal.timeout(DESCRIBE_TIMEOUT_MS);
	const response = await ctx.modelRegistry
		.streamSimple(
			model,
			{ messages: [{ role: "user", content: [{ type: "text", text: DESCRIBE_PROMPT }, image], timestamp: Date.now() }] },
			{
				reasoning: DESCRIBE_REASONING,
				maxTokens: DESCRIBE_MAX_TOKENS,
				signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
			},
		)
		.result();
	if (response.stopReason === "error" || response.stopReason === "aborted") {
		if (timeout.aborted) return { ok: false, reason: `${name} timed out after ${DESCRIBE_TIMEOUT_MS / 1000} s` };
		return { ok: false, reason: `${name} failed: ${response.errorMessage ?? response.stopReason}` };
	}
	const text = response.content
		.filter((part): part is TextContent => part.type === "text")
		.map((part) => part.text)
		.join("\n")
		.trim();
	if (!text) return { ok: false, reason: `${name} returned an empty description` };
	return { ok: true, text };
}

async function describeUncached(
	ctx: ExtensionContext,
	key: string,
	image: ImageContent,
	signal: AbortSignal | undefined,
): Promise<Description> {
	const reasons: string[] = [];
	for (const describer of DESCRIBERS) {
		if (signal?.aborted) return { ok: false, reason: "the request was aborted" };
		const description = await withDescriptionSlot(() => describeWith(ctx, describer, image, signal)).catch(
			(error: unknown): Description => ({
				ok: false,
				reason: `${describer.provider}/${describer.modelId} failed: ${errorMessage(error)}`,
			}),
		);
		if (description.ok) {
			await writeCachedDescription(key, description.text);
			return description;
		}
		reasons.push(description.reason);
	}
	return { ok: false, reason: reasons.join("; ") };
}

function describeImage(
	ctx: ExtensionContext,
	key: string,
	image: ImageContent,
	signal: AbortSignal | undefined,
): Promise<Description> {
	const pending = inFlight.get(key);
	if (pending) return pending;
	const started = describeUncached(ctx, key, image, signal)
		.catch((error: unknown): Description => ({ ok: false, reason: errorMessage(error) }))
		.finally(() => inFlight.delete(key));
	inFlight.set(key, started);
	return started;
}

function replacementText(description: Description): string {
	return description.ok
		? `${REPLACEMENT_HEADER}\n${description.text}`
		: `${REPLACEMENT_HEADER}\n(image could not be described: ${description.reason})`;
}

function imagesIn(message: AgentMessage): ImageContent[] {
	if (message.role !== "user" && message.role !== "toolResult") return [];
	if (!Array.isArray(message.content)) return [];
	return message.content.filter((part): part is ImageContent => part.type === "image");
}

function withoutNonVisionNote(part: TextContent): TextContent {
	if (!part.text.includes(NON_VISION_NOTE)) return part;
	return { ...part, text: part.text.replace(`\n${NON_VISION_NOTE}`, "").replace(NON_VISION_NOTE, "") };
}

function replaceImages(
	content: MessageContent,
	isToolResult: boolean,
	replacements: Map<ImageContent, string>,
): MessageContent {
	return content.map((part) => {
		if (part.type === "image") return { type: "text", text: replacements.get(part) ?? "" };
		return isToolResult ? withoutNonVisionNote(part) : part;
	});
}

async function resolveReplacements(ctx: ExtensionContext, images: ImageContent[]): Promise<Map<ImageContent, string>> {
	const keys = new Map(images.map((image) => [image, imageKey(image)]));
	const cached = new Map<string, string>();
	const uncached = new Map<string, ImageContent>();
	for (const [image, key] of keys) {
		if (cached.has(key) || uncached.has(key)) continue;
		const text = await readCachedDescription(key);
		if (text === undefined) uncached.set(key, image);
		else cached.set(key, replacementText({ ok: true, text }));
	}
	if (uncached.size > 0) {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, `describing ${uncached.size} image(s)…`);
		try {
			const signal = ctx.signal;
			const described = await Promise.all(
				[...uncached].map(async ([key, image]) => [key, await describeImage(ctx, key, image, signal)] as const),
			);
			for (const [key, description] of described) cached.set(key, replacementText(description));
		} finally {
			if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
		}
	}
	return new Map([...keys].map(([image, key]) => [image, cached.get(key) ?? ""]));
}

export default function (pi: ExtensionAPI) {
	pi.on("context", async (event, ctx) => {
		const model = ctx.model;
		if (!model || model.input.includes("image")) return undefined;
		const images = event.messages.flatMap(imagesIn);
		if (images.length === 0) return undefined;
		const replacements = await resolveReplacements(ctx, images);
		const messages = event.messages.map((message): AgentMessage => {
			if (imagesIn(message).length === 0) return message;
			if (message.role === "user" && Array.isArray(message.content)) {
				return { ...message, content: replaceImages(message.content, false, replacements) };
			}
			if (message.role === "toolResult") {
				return { ...message, content: replaceImages(message.content, true, replacements) };
			}
			return message;
		});
		return { messages };
	});
}
