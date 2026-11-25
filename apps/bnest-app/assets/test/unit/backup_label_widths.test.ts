// Unit coverage for the Backup files label at every supported width: the
// grid columns that carry the label can shrink instead of pushing the page
// wider, long problem lines wrap instead of truncating, and every problem is
// a text line beside a shape marker, never a colour alone.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { declarationsFor, type Environment } from "../support/shipped_css";

const here = path.dirname(fileURLToPath(import.meta.url));
const SETTINGS_LIVE = path.resolve(
  here,
  "../../../lib/bnest_app_web/live/admin_schedule_settings_live.ex",
);

// The outline's viewport examples, width by height.
const VIEWPORTS: Array<[number, number]> = [
  [320, 568],
  [393, 851],
  [768, 1024],
  [1440, 900],
];

function environment(width: number, height: number): Environment {
  return { width, height, coarse: false };
}

/** Every track of a `grid-template-columns` value shrinks to zero or is a fixed length. */
function tracksShrink(columns: string): boolean {
  const expanded = columns.replace(
    /repeat\((\d+),\s*(.*)\)/u,
    (_match, count: string, inner: string) =>
      Array(Number(count)).fill(inner).join(" "),
  );
  const tracks = expanded.match(/(?:minmax\([^)]*\)|[^ ]+)/gu) ?? [];
  return (
    tracks.length > 0 &&
    tracks.every(
      (track) =>
        track === "1fr" ||
        /^\d/.test(track) ||
        /^minmax\(0,/.test(track.replace(/\s+/gu, "")),
    )
  );
}

const LABEL_SELECTORS = [
  ".integrity-label dd",
  ".integrity-label__problems",
  ".integrity-label__summary",
  ".schedule-row dd",
  ".schedule-row dl div",
];

// @scenario specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature: No horizontal scrolling and no hidden problem appears at any supported width
describe("backup label at every supported width", () => {
  it.each(VIEWPORTS)(
    "gives the label columns room to shrink at %dx%d",
    (width, height) => {
      const env = environment(width, height);
      const columns =
        declarationsFor(".schedule-row dl", env)["grid-template-columns"] ?? "";
      expect(columns, "the backup row has no grid columns").not.toBe("");
      expect(
        tracksShrink(columns),
        `the backup row columns ${columns} can push past the window`,
      ).toBe(true);
      expect(
        declarationsFor(".schedule-row dl div", env)["min-width"],
        "a backup row cell keeps an automatic minimum width",
      ).toBe("0");
      expect(
        declarationsFor(".integrity-label dd", env)["grid-template-columns"],
        "the label column is sized to its content",
      ).toMatch(/minmax\(0,\s*1fr\)/u);
    },
  );

  it.each(VIEWPORTS)(
    "wraps problem lines instead of truncating them at %dx%d",
    (width, height) => {
      const env = environment(width, height);
      expect(
        declarationsFor(".schedule-row dd", env)["overflow-wrap"],
        "a long problem line cannot break",
      ).toBe("anywhere");
      for (const selector of LABEL_SELECTORS) {
        const declared = declarationsFor(selector, env);
        expect(declared["white-space"], `${selector} forces one line`).not.toBe(
          "nowrap",
        );
        expect(
          declared["text-overflow"],
          `${selector} truncates its text`,
        ).not.toBe("ellipsis");
        for (const axis of ["overflow-x", "overflow-y"] as const) {
          expect(declared[axis], `${selector} clips its text`).not.toBe(
            "hidden",
          );
        }
      }
    },
  );

  it("states every problem as text beside a shape marker", () => {
    const markup = readFileSync(SETTINGS_LIVE, "utf8");
    expect(
      markup.includes("<li :for={problem <- @report.problems}>{problem}</li>"),
      "a problem is not rendered as its own text line",
    ).toBe(true);
    expect(
      markup.includes(
        '<span class="integrity-label__summary">{reader_summary(@report)}</span>',
      ),
      "the label has no text summary beside the marker",
    ).toBe(true);
    for (const state of [
      "checking",
      "all_present",
      "needs_attention",
      "could_not_check",
      "nothing_to_check",
    ]) {
      expect(
        markup.includes(`defp integrity_shape(%{state: :${state}}`),
        `no marker shape repeats the ${state} state in words' place`,
      ).toBe(true);
    }
  });

  it.each(VIEWPORTS)("never hides the label text at %dx%d", (width, height) => {
    const env = environment(width, height);
    for (const selector of [
      ".integrity-label__summary",
      ".integrity-label__problems",
      ".integrity-label__marker",
    ]) {
      const declared = declarationsFor(selector, env);
      expect(declared["display"], `${selector} is removed`).not.toBe("none");
      expect(declared["visibility"], `${selector} is hidden`).not.toBe(
        "hidden",
      );
    }
  });
});
