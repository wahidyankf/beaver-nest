# Batched Cycles in Planned Delivery

When a plan already delivers work in batches — one pull request or one delivery boundary at a time —
the cycle may run per batch instead of per scenario, so planned work does not pay a full red-green ceremony for every
scenario:

1. Write the batch's tests first, from its scenarios, before any production change in the batch.
2. Run one focused RED run for the batch. Every scenario's test must fail for its stated reason; group the reasons in
   one batch record, not one record per scenario. A test that passes is repaired before implementation starts.
3. Implement the batch, then run the identical selection to GREEN. Keep the selection frozen between RED and GREEN.
4. Refactor inside the batch with the selection green; a behaviour change noticed along the way joins the batch's tests
   or becomes its own cycle.
5. Run the full applicable regression and touched end-to-end flows only at the phase or push boundary.
6. Do not repeat an accepted RED whose tests and production code are unchanged.

A batch is one cohesive behaviour slice sharing a boundary and fixtures. Unrelated failures in one RED run mean the
batch is too large; split it. Small single-scenario changes and single bug fixes keep the per-scenario cycle. Only run
and evidence granularity change; tests are still written before the code.
