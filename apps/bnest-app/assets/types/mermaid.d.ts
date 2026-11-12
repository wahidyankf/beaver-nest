// Mermaid 12.3.0's own declarations start with `import type { RequiredDeep } from "type-fest"`, but the
// package does not list type-fest as a dependency. Under this project's tsconfig (no skipLibCheck) that
// import either fails or resolves to an old copy and reports errors, so tsconfig maps "mermaid" to this
// file instead (the same way it maps phoenix_html). It types only the part of the API the diagram engine
// uses (ADR 004, Decision 3). The runtime behaviour is covered by the engine's unit tests and the Chromium
// smoke check.

export interface MermaidConfig {
  startOnLoad?: boolean;
  securityLevel?: "strict" | "loose" | "antiscript" | "sandbox";
  logLevel?: "trace" | "debug" | "info" | "warn" | "error" | "fatal";
  suppressErrorRendering?: boolean;
  maxTextSize?: number;
  maxEdges?: number;
  htmlLabels?: boolean;
  flowchart?: { htmlLabels?: boolean };
  secure?: string[];
  layout?: string;
  theme?: string;
  themeVariables?: Record<string, string>;
  fontFamily?: string;
}

export interface Mermaid {
  initialize(config: MermaidConfig): void;
  parse(text: string): Promise<unknown>;
  render(id: string, text: string): Promise<{ svg: string }>;
}

declare const mermaid: Mermaid;
export default mermaid;
