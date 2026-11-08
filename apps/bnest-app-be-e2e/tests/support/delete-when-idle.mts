import { TestingControlError } from "./testing-control-error.mts";

// How long a delete waits for the scheduler to go quiet. The server refuses a delete with `instance_busy` while a
// scheduler task runs (ADR 001, section 1), and a task the scenario queued, such as the first verification after a
// backup folder is saved, can outlive the scenario by a moment. 120 attempts 250 ms apart wait 30 seconds at most.
export type BusyWait = {
  attempts: number;
  intervalMs: number;
  sleep?: (ms: number) => Promise<void>;
};

export const defaultBusyWait: BusyWait = { attempts: 120, intervalMs: 250 };

export type DeletingClient = { deleteInstance(instanceId: string): Promise<void> };

function pause(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

// Only `instance_busy` is waited for, up to the bounded attempts; the last refusal is rethrown. Every other failure,
// and every attempt, goes to the server's own check, so nothing here skips or weakens it.
export async function deleteWhenIdle(
  client: DeletingClient,
  instanceId: string,
  wait: BusyWait = defaultBusyWait,
  attempt = 1,
): Promise<void> {
  try {
    await client.deleteInstance(instanceId);
  } catch (error) {
    const busy = error instanceof TestingControlError && error.code === "instance_busy";
    if (!busy || attempt >= wait.attempts) throw error;
    await (wait.sleep ?? pause)(wait.intervalMs);
    await deleteWhenIdle(client, instanceId, wait, attempt + 1);
  }
}
