import assert from "node:assert/strict";
import test from "node:test";

import { validateFeatureSource } from "./behaviour-compliance.mts";

const validFeature = `Feature: Compliance example

  Scenario: Observable behaviour
    Given a precondition
    When an action occurs
    Then an outcome is observed`;

test("accepts a feature with an explicit When and Then", () => {
  assert.deepEqual(validateFeatureSource("example.feature", validFeature), []);
});

test("rejects a missing Feature declaration", () => {
  const source = validFeature.replace(
    "Feature: Compliance example",
    "Compliance example",
  );

  assert.ok(
    validateFeatureSource("example.feature", source).some((error) =>
      error.includes("missing Feature:"),
    ),
  );
});

test("rejects a feature without scenarios", () => {
  assert.ok(
    validateFeatureSource("example.feature", "Feature: Empty").some((error) =>
      error.includes("at least one scenario"),
    ),
  );
});

test("rejects a scenario without When", () => {
  const source = validFeature.replace("    When an action occurs\n", "");

  assert.ok(
    validateFeatureSource("example.feature", source).some((error) =>
      error.includes("requires a When"),
    ),
  );
});

test("rejects a scenario without Then", () => {
  const source = validFeature.replace("    Then an outcome is observed", "");

  assert.ok(
    validateFeatureSource("example.feature", source).some((error) =>
      error.includes("requires a Then"),
    ),
  );
});

test("does not treat doc-string content as scenario steps", () => {
  const source = `Feature: Doc strings

  Scenario: Keywords in content
    Given this content:
      """
      When this is not a step
      Then this is not a step
      """`;
  const errors = validateFeatureSource("example.feature", source);

  assert.ok(errors.some((error) => error.includes("requires a When")));
  assert.ok(errors.some((error) => error.includes("requires a Then")));
});
