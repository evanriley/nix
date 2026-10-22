declare module "@earendil-works/pi-agent-core" {
	export type AgentMessage = any;
	export type AgentToolResult<T = any> = any;
}
declare module "@earendil-works/pi-ai" {
	export type ImageContent = any;
	export type Message = any;
	export type TextContent = any;
	export type Usage = any;
}
declare module "@earendil-works/pi-coding-agent" {
	export type ExtensionAPI = any;
	export type ExtensionCommandContext = any;
	export type ExtensionContext = any;
	export type Theme = any;
	export const getAgentDir: any;
	export const getMarkdownTheme: any;
	export const keyHint: any;
}
declare module "@earendil-works/pi-tui" {
	export type Component = any;
	export const Container: any;
	export const Markdown: any;
	export const Spacer: any;
	export const Text: any;
	export const TruncatedText: any;
	export const sliceByColumn: any;
	export const truncateToWidth: any;
	export const visibleWidth: any;
}
declare module "typebox" {
	export const Type: any;
}
