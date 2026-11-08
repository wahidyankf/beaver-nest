// Runs every cleanup step, even after one fails, so a failed page close cannot keep the instance from being
// deleted. The steps run one after another, each once the previous one has settled. The failures are
// rethrown afterwards.
export async function settleAll(
  steps: ReadonlyArray<() => Promise<void>>,
): Promise<void> {
  const failures: unknown[] = [];
  await steps.reduce<Promise<void>>(
    (previous, step) =>
      previous.then(step).catch((error: unknown) => {
        failures.push(error);
      }),
    Promise.resolve(),
  );
  if (failures.length === 1) throw failures[0];
  if (failures.length > 1) {
    throw new AggregateError(failures, "several cleanup steps failed");
  }
}
