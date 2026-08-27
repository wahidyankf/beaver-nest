import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const leaseRoot = join(tmpdir(), "bnest-port-leases");

export function acquirePortLease(port, owner, minimum, maximum) {
  if (!Number.isInteger(port) || port < minimum || port > maximum)
    throw new Error(`Port must be between ${minimum} and ${maximum}`);
  if (!/^[a-z0-9-]+$/u.test(owner))
    throw new Error("Port lease owner is invalid");

  mkdirSync(leaseRoot, { recursive: true, mode: 0o700 });
  const leasePath = join(leaseRoot, `${port}.lock`);

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      mkdirSync(leasePath, { mode: 0o700 });
      writeFileSync(
        join(leasePath, "owner.json"),
        `${JSON.stringify({ schemaVersion: 1, port, owner, pid: process.pid })}\n`,
        { encoding: "utf8", mode: 0o600 },
      );
      return { owner, path: leasePath, port };
    } catch (error) {
      if (error?.code !== "EEXIST" || attempt > 0) throw error;
      if (!staleLease(leasePath, port))
        throw new Error(`Port ${port} is already leased`);
      rmSync(leasePath, { recursive: true });
    }
  }

  throw new Error(`Port ${port} could not be leased`);
}

export function releasePortLease(lease) {
  const expectedPath = join(leaseRoot, `${lease.port}.lock`);
  if (lease.path !== expectedPath || !existsSync(expectedPath))
    throw new Error("Refusing to release an invalid port lease");
  const marker = JSON.parse(
    readFileSync(join(expectedPath, "owner.json"), "utf8"),
  );
  if (
    marker.pid !== process.pid ||
    marker.port !== lease.port ||
    marker.owner !== lease.owner
  )
    throw new Error(
      "Refusing to release a port lease owned by another process",
    );
  rmSync(expectedPath, { recursive: true });
}

function staleLease(leasePath, port) {
  try {
    const marker = JSON.parse(
      readFileSync(join(leasePath, "owner.json"), "utf8"),
    );
    if (
      marker.schemaVersion !== 1 ||
      marker.port !== port ||
      !Number.isInteger(marker.pid)
    )
      return false;
    try {
      process.kill(marker.pid, 0);
      return false;
    } catch (error) {
      return error?.code === "ESRCH";
    }
  } catch {
    return false;
  }
}
