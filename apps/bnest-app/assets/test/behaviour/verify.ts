// Frontend Gherkin binding-completeness check and scenario runner for the
// `@fe-vitest-unit` scenarios of
// specs/apps/bnest/app-fe/behaviours/family_chat.feature.
//
// This is the Vitest analogue of `apps/bnest-app/test/behaviour/verify.exs`:
// it discovers the real canonical feature file (no generated/derivative
// copy), compiles it into Cucumber pickles with `@cucumber/gherkin` (the
// same engine `playwright-bdd` already uses elsewhere in this repo), and
// requires every step of every `@fe-vitest-unit` pickle to match exactly one
// registered binding from `family_chat.steps.ts` — zero undefined, zero
// ambiguous, zero unused. It then executes each pickle's steps in order
// against a shared context, so a scenario whose production code does not
// exist yet fails here for a genuine reason (RED), not a binding gap.
//
// Scope: only pickles tagged `@fe-vitest-unit`. The two "Canonical route"
// scenarios (and everything else in the app-be/app-fe corpus) remain owned
// by Elixir ExBdd (`test/behaviour/verify.exs`); `BnestApp.Behaviour.
// FeVitestUnitScope` prunes exactly this same tagged set from the Elixir
// side so the two verifiers partition the corpus without overlap or gaps.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  AstBuilder,
  GherkinClassicTokenMatcher,
  Parser,
  compile,
} from "@cucumber/gherkin";
import { IdGenerator } from "@cucumber/messages";
import type { Pickle } from "@cucumber/messages";
import {
  CucumberExpression,
  ParameterTypeRegistry,
} from "@cucumber/cucumber-expressions";
import { describe, expect, it } from "vitest";
import {
  familyChatSteps,
  type StepContext,
  type StepDefinition,
} from "./family_chat.steps.ts";

const FE_VITEST_UNIT_TAG = "fe-vitest-unit";

const here = path.dirname(fileURLToPath(import.meta.url));
const featurePath = path.resolve(
  here,
  "../../../../../specs/apps/bnest/app-fe/behaviours/family_chat.feature",
);

function parsePickles(source: string, uri: string): readonly Pickle[] {
  const newId = IdGenerator.incrementing();
  const builder = new AstBuilder(newId);
  const matcher = new GherkinClassicTokenMatcher();
  const parser = new Parser(builder, matcher);
  const gherkinDocument = parser.parse(source);
  gherkinDocument.uri = uri;
  return compile(gherkinDocument, uri, newId);
}

function hasFeVitestUnitTag(pickle: Pickle): boolean {
  return pickle.tags.some(
    (tag) => tag.name.replace(/^@/u, "") === FE_VITEST_UNIT_TAG,
  );
}

function loadOwnedPickles(): readonly Pickle[] {
  const source = readFileSync(featurePath, "utf8");
  return parsePickles(source, featurePath).filter(hasFeVitestUnitTag);
}

const registry = new ParameterTypeRegistry();
const steps = familyChatSteps();

interface CompiledStep {
  readonly definition: StepDefinition;
  readonly expression: CucumberExpression;
}

const compiledSteps: readonly CompiledStep[] = steps.map((definition) => ({
  definition,
  expression: new CucumberExpression(definition.expression, registry),
}));

function matchingSteps(text: string): CompiledStep[] {
  return compiledSteps.filter(
    (compiled) => compiled.expression.match(text) !== null,
  );
}

const pickles = loadOwnedPickles();

describe("family_chat.feature: frontend-owned (@fe-vitest-unit) binding coverage", () => {
  it("discovers at least one frontend-owned scenario", () => {
    expect(pickles.length).toBeGreaterThan(0);
  });

  for (const pickle of pickles) {
    it(`every step binds exactly once: ${pickle.name}`, () => {
      for (const pickleStep of pickle.steps) {
        const matches = matchingSteps(pickleStep.text);
        if (matches.length === 0) {
          throw new Error(
            `${featurePath}: scenario ${JSON.stringify(pickle.name)}, ` +
              `step ${JSON.stringify(pickleStep.text)} has no matching binding`,
          );
        }
        if (matches.length > 1) {
          throw new Error(
            `${featurePath}: scenario ${JSON.stringify(pickle.name)}, ` +
              `step ${JSON.stringify(pickleStep.text)} matches ${matches.length} bindings`,
          );
        }
      }
    });
  }

  it("has no unused step bindings", () => {
    const used = new Set<string>();
    for (const pickle of pickles) {
      for (const pickleStep of pickle.steps) {
        for (const compiled of matchingSteps(pickleStep.text)) {
          used.add(compiled.definition.expression);
        }
      }
    }
    const unused = compiledSteps
      .map((compiled) => compiled.definition.expression)
      .filter((expression) => !used.has(expression));
    expect(unused).toEqual([]);
  });
});

describe("family_chat.feature: frontend-owned (@fe-vitest-unit) scenario execution", () => {
  for (const pickle of pickles) {
    it(pickle.name, async () => {
      let context: StepContext = {};
      for (const pickleStep of pickle.steps) {
        const [match] = matchingSteps(pickleStep.text);
        if (match === undefined) {
          throw new Error(
            `no binding for step ${JSON.stringify(pickleStep.text)}`,
          );
        }
        const args = match.expression
          .match(pickleStep.text)!
          .map((argument) => String(argument.getValue(undefined)));
        context = await match.definition.handler(context, ...args);
      }
    });
  }
});
