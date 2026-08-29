import { acquirePortLease, releasePortLease } from "./port-lease.mjs";
import { runGuardedCommand } from "../../../tools/resource-guard/guard.mjs";
import { defaultEvidenceRoot } from "../../../tools/resource-guard/metrics.mjs";

const port = Number(process.env.BNEST_DEV_PORT ?? "4020");
const lease = acquirePortLease(port, "development", 4020, 4029);

async function main() {
  try {
    process.exitCode = await runGuardedCommand({
      command: "mix",
      arguments_: ["phx.server"],
      environment: {
        ...process.env,
        BNEST_STABLE: process.env.BNEST_STABLE ?? "true",
        PORT: String(port),
      },
      evidenceRoot: defaultEvidenceRoot(),
      taskClass: "service",
    });
  } finally {
    releasePortLease(lease);
  }
}

main().catch((error) => {
  process.stderr.write(`Development server failed: ${error.message}\n`);
  process.exitCode = 1;
});
