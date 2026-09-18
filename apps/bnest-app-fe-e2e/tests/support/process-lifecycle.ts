import type { ChildProcess } from "node:child_process";
import { once } from "node:events";

const isRunning = (process: ChildProcess): boolean =>
  process.exitCode === null && process.signalCode === null;

const boundedWait = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });

export function terminateChildProcesses(
  processes: Iterable<ChildProcess>,
): void {
  for (const process of processes) {
    if (isRunning(process)) process.kill("SIGTERM");
  }
}

export async function stopChildProcesses(
  processes: Iterable<ChildProcess>,
): Promise<void> {
  const running = [...processes].filter((process) => isRunning(process));
  const exited = running.map((process) =>
    once(process, "exit").catch(() => null),
  );
  terminateChildProcesses(running);
  await Promise.race([Promise.all(exited), boundedWait(5_000)]);

  const stubborn = running.filter((process) => isRunning(process));
  const forcedExits = stubborn.map((process) =>
    once(process, "exit").catch(() => null),
  );
  for (const process of stubborn) process.kill("SIGKILL");
  await Promise.race([Promise.all(forcedExits), boundedWait(2_000)]);
  if (stubborn.some((process) => isRunning(process))) {
    throw new Error("task-owned candidate did not exit after SIGKILL");
  }
}
