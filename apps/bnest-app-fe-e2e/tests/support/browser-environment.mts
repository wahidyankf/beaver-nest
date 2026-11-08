// The test-control secret must never reach a browser. Playwright starts browsers with `launchOptions.env`,
// and that defaults to the whole `process.env`, so the Playwright configs pass this filtered copy instead.
// The Phoenix webServer and the test steps still read the secret from `process.env`.
const testControlSecretName = "BNEST_TEST_CONTROL_SECRET";

export function browserEnvironment(
  environment: NodeJS.ProcessEnv,
): Record<string, string> {
  const browser: Record<string, string> = {};

  for (const [name, value] of Object.entries(environment)) {
    if (name !== testControlSecretName && value !== undefined) {
      browser[name] = value;
    }
  }

  return browser;
}
