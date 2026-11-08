// A page can still have a request in flight when its scenario ends. Closing the page does not cancel the server's work
// on that request, so the work would run after the instance is deleted and open the profile's default database in the
// data-free run base. Waiting for the network to go idle first lets the server answer every request the page sent.
//
// A page that never goes idle is not a failure: a scenario may hold a request on purpose with a Playwright route, and
// that request never reaches the server. Such a wait ends at the timeout and the scenario goes on.

export type IdlePage = {
  isClosed(): boolean;
  waitForLoadState(
    state: "networkidle",
    options: { timeout: number },
  ): Promise<void>;
};

function isTimeout(error: unknown): boolean {
  return error instanceof Error && error.name === "TimeoutError";
}

// Every page is waited on before any other failure is rethrown, so none is still being waited on when the caller
// moves on.
export async function waitForPagesIdle(
  pages: readonly IdlePage[],
  timeoutMs: number,
): Promise<void> {
  const results = await Promise.allSettled(
    pages
      .filter((page) => !page.isClosed())
      .map((page) =>
        page.waitForLoadState("networkidle", { timeout: timeoutMs }),
      ),
  );
  const failed = results.find(
    (result): result is PromiseRejectedResult =>
      result.status === "rejected" && !isTimeout(result.reason),
  );
  if (failed !== undefined) throw failed.reason;
}
