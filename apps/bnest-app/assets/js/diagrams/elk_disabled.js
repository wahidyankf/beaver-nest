// ADR 004, Decision 4: esbuild aliases `elkjs/lib/elk.bundled.js` to this file. elkjs is EPL-2.0 or
// GPL-3.0-or-later, and this build never selects Mermaid's ELK layout, so no elkjs code ships. The
// export keeps the import binding valid and can be constructed, as Mermaid calls it with `new`; the call
// throws, so an ELK layout can never run here.
export default function ElkDisabled() {
  throw new Error("The ELK layout is not part of this build.");
}
