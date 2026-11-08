// The Playwright global teardown. It is a `.ts` file, so Playwright loads it and its `.mts` imports through its CommonJS
// path, the same path the worker uses. A `.mts` teardown is loaded with a native `import()`, and in that path the
// testing-control module is missing its named exports (`backendOrigin`), so the run fails after every scenario.
import globalTeardown from "./test-runtime.mts";

export default globalTeardown;
