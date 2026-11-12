// ADR 004, Decision 4: a failed first import of the engine's module is not kept by the browser's module map, so the
// next call asks for the module under a new address. The importer is tested with a fake import.
import { describe, expect, it } from "vitest";
import {
  createEngineImporter,
  makeThemeReader,
} from "../../../js/diagrams/diagram_browser.js";

const ENGINE_URL = "/assets/js/diagrams/engine.js";

function engineModule() {
  return {
    ENGINE_API: 1,
    loadEngine: async () => ({ renderDiagram: async () => ({ svg: "" }) }),
  };
}

describe("createEngineImporter", () => {
  it("imports the engine from its address and hands over its API", async () => {
    const requested: string[] = [];
    const importer = createEngineImporter({
      readUrl: () => ENGINE_URL,
      importModule: async (address) => {
        requested.push(address);
        return engineModule();
      },
    });

    const api = await importer();

    expect(requested).toEqual([ENGINE_URL]);
    expect(api).toEqual({ ENGINE_API: 1, renderDiagram: expect.any(Function) });
  });

  it("asks for a new address after a failed import, so the failure is not kept", async () => {
    const requested: string[] = [];
    const importer = createEngineImporter({
      readUrl: () => ENGINE_URL,
      importModule: async (address) => {
        requested.push(address);
        if (requested.length === 1)
          throw new Error("the engine could not be fetched");
        return engineModule();
      },
    });

    await expect(importer()).rejects.toThrow("the engine could not be fetched");
    await importer();

    expect(requested[0]).toBe(ENGINE_URL);
    expect(requested[1]).toBe(`${ENGINE_URL}?retry=1`);
  });

  it("refuses to draw when the engine address is missing", async () => {
    const importer = createEngineImporter({
      readUrl: () => undefined,
      importModule: async () => {
        throw new Error("no import is expected without an address");
      },
    });

    await expect(importer()).rejects.toThrow(
      "the diagram engine address is missing",
    );
  });
});

// The theme is read with computed styles, which force the browser to match the page's styles. A page with several
// diagrams asks once per diagram in one synchronous pass, so one batch reads the theme once.
describe("makeThemeReader", () => {
  it("reads the theme once for a synchronous batch of diagrams", () => {
    let reads = 0;
    const readTheme = makeThemeReader(() => {
      reads += 1;
      return { themeVariables: {}, themeSignature: `read-${reads}` };
    });

    const first = readTheme();
    const second = readTheme();

    expect(reads).toBe(1);
    expect(second).toBe(first);
  });

  it("reads the theme again in the next batch, so a theme change is seen", async () => {
    let reads = 0;
    const readTheme = makeThemeReader(() => {
      reads += 1;
      return { themeVariables: {}, themeSignature: `read-${reads}` };
    });

    readTheme();
    await Promise.resolve();
    const later = readTheme();

    expect(reads).toBe(2);
    expect(later.themeSignature).toBe("read-2");
  });
});
