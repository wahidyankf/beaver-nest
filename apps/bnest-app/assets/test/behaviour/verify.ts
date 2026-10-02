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
//
// A second corpus runs the same way: the `@vitest-unit` scenarios of
// specs/apps/bnest/app-be/behaviours/family_chat_operations.feature, bound by
// `family_chat_operations.steps.ts`. Only their unit layer lives here (see
// that file's header); Elixir ExBdd still binds and runs their integration
// layer, and `FeVitestUnitScope.prune_unit_layer/1` drops them from its unit
// layer.

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
} from "./family_chat.steps";
import {
  familyChatReplySteps,
  resetReplyScenario,
} from "./family_chat_reply.steps";
import { familyChatOperationsSteps } from "./family_chat_operations.steps";
import { closeBrowserRoom } from "./support/reply_room";

const here = path.dirname(fileURLToPath(import.meta.url));
const behaviours = path.resolve(here, "../../../../../specs/apps/bnest");

function parsePickles(source: string, uri: string): readonly Pickle[] {
  const newId = IdGenerator.incrementing();
  const builder = new AstBuilder(newId);
  const matcher = new GherkinClassicTokenMatcher();
  const parser = new Parser(builder, matcher);
  const gherkinDocument = parser.parse(source);
  gherkinDocument.uri = uri;
  return compile(gherkinDocument, uri, newId);
}

interface CompiledStep {
  readonly definition: StepDefinition;
  readonly expression: CucumberExpression;
}

interface Corpus {
  // The feature file name, as the suite titles show it.
  readonly feature: string;
  readonly featurePath: string;
  // The tag that hands a scenario to this harness, without its `@`.
  readonly tag: string;
  // Who owns the tagged scenarios, as the suite titles show it.
  readonly owner: string;
  readonly steps: readonly StepDefinition[];
  // Runs after every scenario, whether it passed or not.
  readonly afterScenario: () => void;
}

// Requires every step of every pickle tagged `corpus.tag` to match exactly one of
// `corpus.steps` (zero undefined, zero ambiguous, zero unused), then executes each
// pickle's steps in order against a shared context.
function verifyCorpus(corpus: Corpus): void {
  const registry = new ParameterTypeRegistry();
  const compiledSteps: readonly CompiledStep[] = corpus.steps.map(
    (definition) => ({
      definition,
      expression: new CucumberExpression(definition.expression, registry),
    }),
  );

  const matchingSteps = (text: string): CompiledStep[] =>
    compiledSteps.filter(
      (compiled) => compiled.expression.match(text) !== null,
    );

  const pickles = parsePickles(
    readFileSync(corpus.featurePath, "utf8"),
    corpus.featurePath,
  ).filter((pickle) =>
    pickle.tags.some((tag) => tag.name.replace(/^@/u, "") === corpus.tag),
  );

  const title = `${corpus.feature}: ${corpus.owner} (@${corpus.tag})`;

  describe(`${title} binding coverage`, () => {
    it(`discovers at least one ${corpus.owner} scenario`, () => {
      expect(pickles.length).toBeGreaterThan(0);
    });

    for (const pickle of pickles) {
      it(`every step binds exactly once: ${pickle.name}`, () => {
        for (const pickleStep of pickle.steps) {
          const matches = matchingSteps(pickleStep.text);
          if (matches.length === 0) {
            throw new Error(
              `${corpus.featurePath}: scenario ${JSON.stringify(pickle.name)}, ` +
                `step ${JSON.stringify(pickleStep.text)} has no matching binding`,
            );
          }
          if (matches.length > 1) {
            throw new Error(
              `${corpus.featurePath}: scenario ${JSON.stringify(pickle.name)}, ` +
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

  describe(`${title} scenario execution`, () => {
    for (const pickle of pickles) {
      it(pickle.name, async () => {
        let context: StepContext = {};
        try {
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
        } finally {
          corpus.afterScenario();
        }
      });
    }
  });
}

verifyCorpus({
  feature: "family_chat.feature",
  featurePath: path.join(behaviours, "app-fe/behaviours/family_chat.feature"),
  tag: "fe-vitest-unit",
  owner: "frontend-owned",
  // Two binding files, one corpus: `family_chat.steps.ts` drives the
  // document-free room, `family_chat_reply.steps.ts` the browser-shaped one.
  // They are merged here rather than cross-imported so the "binds exactly
  // once" and "no unused bindings" checks still see the whole set.
  steps: [...familyChatSteps(), ...familyChatReplySteps()],
  // A scenario that opened the browser-shaped room installed a `document` on
  // `globalThis`; leaving it there would silently flip every following
  // document-free scenario onto `initRoom`'s browser branch, so it comes
  // down whether the scenario passed or not.
  afterScenario: () => {
    closeBrowserRoom();
    resetReplyScenario();
  },
});

verifyCorpus({
  feature: "family_chat_operations.feature",
  featurePath: path.join(
    behaviours,
    "app-be/behaviours/family_chat_operations.feature",
  ),
  tag: "vitest-unit",
  owner: "deployment-tool",
  steps: familyChatOperationsSteps(),
  afterScenario: () => undefined,
});
