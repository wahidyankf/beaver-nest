// Unit coverage for the home page's header-to-hero separation: the header
// grid item keeps a positive gap above the hero grid item, both stay in the
// normal flow, and the decorative layers sit behind the content.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  declarationsFor,
  lengthPx,
  resolveVars,
  type Environment,
} from "../support/shipped_css";

const here = path.dirname(fileURLToPath(import.meta.url));
const HOME_TEMPLATE = path.resolve(
  here,
  "../../../lib/bnest_app_web/controllers/page_html/home.html.heex",
);

const WIDTHS: Array<[number, number, boolean]> = [
  [320, 568, true],
  [1440, 900, false],
];

function environment(
  width: number,
  height: number,
  coarse: boolean,
): Environment {
  return { width, height, coarse };
}

function template(): string {
  return readFileSync(HOME_TEMPLATE, "utf8");
}

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Home controls and content remain visually separated
describe("home header and hero separation", () => {
  it("renders the header before the hero", () => {
    const markup = template();
    const headerAt = markup.indexOf('class="home-header"');
    const heroAt = markup.indexOf('class="home-hero"');
    expect(headerAt, "the home template has no header").toBeGreaterThan(-1);
    expect(heroAt, "the home template has no hero").toBeGreaterThan(-1);
    expect(headerAt < heroAt, "the hero is rendered before the header").toBe(
      true,
    );
  });

  it.each(WIDTHS)(
    "keeps the header and the hero in the normal flow at %dx%d",
    (width, height, coarse) => {
      const env = environment(width, height, coarse);
      const shell = declarationsFor(".home-shell", env);
      expect(shell["display"], "the home shell is not a grid").toBe("grid");
      for (const selector of [".home-header", ".home-hero"]) {
        const declared = declarationsFor(selector, env);
        expect(
          declared["position"],
          `${selector} is taken out of the flow`,
        ).toBeUndefined();
        expect(
          declared["grid-area"],
          `${selector} is placed over another row`,
        ).toBeUndefined();
      }
    },
  );

  it.each(WIDTHS)(
    "keeps a positive gap between the header and the hero at %dx%d",
    (width, height, coarse) => {
      const env = environment(width, height, coarse);
      const gap = lengthPx(
        resolveVars(
          declarationsFor(".home-header", env)["margin-block-end"] ?? "",
        ),
        env,
      );
      expect(gap, "the header keeps no space below itself").toBeGreaterThan(0);
    },
  );

  it.each(WIDTHS)(
    "keeps the background decor behind the content",
    (width, height, coarse) => {
      const env = environment(width, height, coarse);
      for (const selector of [".home-grid", ".home-sun"]) {
        const declared = declarationsFor(selector, env);
        expect(declared["position"], `${selector} flows with the content`).toBe(
          "absolute",
        );
        expect(
          Number(declared["z-index"] ?? "0"),
          `${selector} can cover the controls`,
        ).toBeLessThan(0);
      }
    },
  );
});
