import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { browserEnvironment } from "./browser-environment.mts";

const secret = "a".repeat(64);

test("gives browsers every variable except the test-control secret", () => {
  const environment = {
    BNEST_TEST_CONTROL_SECRET: secret,
    HOME: "/synthetic/e2e-runner",
    PATH: "/usr/bin",
    UNSET: undefined,
  };

  assert.deepEqual(browserEnvironment(environment), {
    HOME: "/synthetic/e2e-runner",
    PATH: "/usr/bin",
  });
});

test("leaves the process environment unchanged so the server and steps keep the secret", () => {
  const environment = { BNEST_TEST_CONTROL_SECRET: secret, PATH: "/usr/bin" };

  browserEnvironment(environment);

  assert.equal(environment.BNEST_TEST_CONTROL_SECRET, secret);
});

test("the project's Playwright config passes the filtered environment to the browser launch", () => {
  const config = readFileSync(
    new URL("../../playwright.config.mts", import.meta.url),
    "utf8",
  );

  assert.match(
    config,
    /import \{ browserEnvironment \} from "\.\/tests\/support\/browser-environment\.mts";/u,
  );
  assert.match(
    config,
    /launchOptions: \{ env: browserEnvironment\(process\.env\) \}/u,
  );
});
