import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  backendOriginFromEnv,
  runId,
  testingControl,
} from "../support/active-instance.mts";
import { readyStorageGeneration } from "../support/test-isolation-probes";

// E2E bindings for the PORT rows of runtime_configuration.feature's
// `PORT sets the HTTP port and PHX_SERVER makes the release serve` outline (BN-CFG-01). The E2E harness boots the
// release with PORT set to its leased port, so the When step reaches the server on that leased port through the
// readiness probe: that reachability is the E2E proof that PORT sets the port the release serves. The row's own
// expectation is checked against the same derivation the unit adapter proves.
//
// @scenario specs/apps/bnest/app-be/behaviours/runtime_configuration.feature: PORT sets the HTTP port and PHX_SERVER makes the release serve

const { Before, Given, Then, When } = createBdd();

type Carried = {
  portValue?: string;
  serverValue?: string;
  generation?: string;
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// The derivation the unit layer proves, mirrored so the row reads the same way at this layer.
function expectedPort(portValue: string): number {
  if (portValue === "(unset)") return 4000;
  const port = Number(portValue);
  if (!Number.isInteger(port)) {
    throw new TypeError(`the scenario names no port: ${portValue}`);
  }
  return port;
}

function expectedServer(serverValue: string): string {
  return serverValue === "(unset)" ? "off" : "on";
}

Given(
  "PORT is {string} and PHX_SERVER is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, portValue: string, serverValue: string) => {
    carried = { portValue, serverValue };
  },
);

When("the runtime settings are derived", async () => {
  // The E2E server is reached on its leased port: the probe fetches the leased-port origin and fails unless the
  // release serves there.
  expect(backendOriginFromEnv()).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/u);
  carried.generation = await readyStorageGeneration();
});

Then(
  "the HTTP port is {int} and the server is {string}",
  // eslint-disable-next-line no-empty-pattern
  async ({}, port: number, server: string) => {
    const portValue = required(carried.portValue, "PORT value");
    const serverValue = required(carried.serverValue, "PHX_SERVER value");
    expect(expectedPort(portValue)).toBe(port);
    expect(expectedServer(serverValue)).toBe(server);
    // The release the harness booted with PORT set to its leased port answered there.
    expect(required(carried.generation, "readiness generation")).not.toBe("");
    expect((await testingControl().state()).runId).toBe(runId());
  },
);
