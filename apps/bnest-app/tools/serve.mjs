import { spawnSync } from "node:child_process";

import { acquirePortLease, releasePortLease } from "./port-lease.mjs";

const port = Number(process.env.BNEST_DEV_PORT ?? "4020");
const lease = acquirePortLease(port, "development", 4020, 4029);

try {
  const result = spawnSync("mix", ["phx.server"], {
    env: {
      ...process.env,
      BNEST_STABLE: process.env.BNEST_STABLE ?? "true",
      PORT: String(port),
    },
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  releasePortLease(lease);
}
