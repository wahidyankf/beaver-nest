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

test("accepts a documented higher-layer exemption", () => {
  const source = validFeature.replace(
    "  Scenario: Observable behaviour",
    "  # Exemption(integration): browser geometry needs a layout engine; alternative-proof: example-e2e:test:e2e / Observable behaviour\n" +
      "  @integration-exempt\n" +
      "  Scenario: Observable behaviour",
  );

  assert.deepEqual(validateFeatureSource("example.feature", source), []);
});

test("rejects unit exemptions and legacy exemption names", () => {
  for (const tag of [
    "@unit-exempt",
    "@no-unit",
    "@no-integration",
    "@no-e2e",
  ]) {
    const source = validFeature.replace(
      "  Scenario: Observable behaviour",
      `  ${tag}\n  Scenario: Observable behaviour`,
    );
    assert.ok(
      validateFeatureSource("example.feature", source).some((error) =>
        error.includes("is forbidden"),
      ),
    );
  }
});

test("rejects undocumented, broad, and double exemptions", () => {
  const undocumented = validFeature.replace(
    "  Scenario: Observable behaviour",
    "  @integration-exempt\n  Scenario: Observable behaviour",
  );
  assert.ok(
    validateFeatureSource("example.feature", undocumented).some((error) =>
      error.includes("immediately preceding comment"),
    ),
  );

  const broad = validFeature.replace(
    "Feature: Compliance example",
    "@e2e-exempt\nFeature: Compliance example",
  );
  assert.ok(
    validateFeatureSource("example.feature", broad).some((error) =>
      error.includes("only annotate"),
    ),
  );

  const doubled = validFeature.replace(
    "  Scenario: Observable behaviour",
    "  # Exemption(integration): browser geometry needs a layout engine; alternative-proof: example-e2e:test:e2e / Observable behaviour\n" +
      "  @integration-exempt @e2e-exempt\n" +
      "  Scenario: Observable behaviour",
  );
  assert.ok(
    validateFeatureSource("example.feature", doubled).some((error) =>
      error.includes("cannot be both"),
    ),
  );
});

test("rejects exemptions for unfinished or flaky work", () => {
  const source = validFeature.replace(
    "  Scenario: Observable behaviour",
    "  # Exemption(e2e): too flaky and not yet implemented; alternative-proof: example:test:integration / Observable behaviour\n" +
      "  @e2e-exempt\n" +
      "  Scenario: Observable behaviour",
  );

  assert.ok(
    validateFeatureSource("example.feature", source).some((error) =>
      error.includes("cannot be justified"),
    ),
  );
});
