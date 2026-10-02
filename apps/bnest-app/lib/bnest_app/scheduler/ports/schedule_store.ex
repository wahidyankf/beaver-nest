defmodule BnestApp.Scheduler.Ports.ScheduleStore do
  @moduledoc """
  The store of persisted schedules and the runs claimed from them: the Scheduler's ledger.
  Schedules come to exist through release seeds; this port claims their due slots, moves
  each claimed attempt through its lease, retries and result, and applies the operator's
  and the release's edits.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module.

  Semantics every implementation keeps:

    * A schedule is due when it is enabled, not expired, and its next run is at or before
      `now`. `claim_due/2` takes the due schedules in next-run, then key, order. For each it
      decides with `BnestApp.Scheduler.Domain.Policy.claim/2`: an eligible schedule gets one
      running claim of its latest slot (claim key `"slot:<ISO 8601 slot>"`, attempt 1,
      leased until `Policy.lease_until(now)`, started at `now`), counts the occurrence,
      expires at its final occurrence, and moves its next run to the next slot; a slot
      already claimed is not claimed again and the schedule does not move. An ineligible
      schedule expires at `now` with no claim.
    * Then `claim_due/2` recovers runs, oldest start first, then by run ID: a retryable run
      whose next attempt time is at or before `now`, and a running run whose lease expired at
      or before `now`. `Policy.recovery/1` decides: a running run already at the last attempt
      fails as `"attempt_limit"`; any other runs again, leased from `now` and started at
      `now`, under the same attempt if it was retryable and the next attempt if its lease
      expired. It returns the scheduled claims, then the recovered runs.
    * `claim_setup/4` claims a setup run under `claim_key` for the schedule, idempotently: a
      second call returns the first run. It raises for an unknown schedule.
    * `fail_attempt/5` refuses with `{:error, :stale_attempt}` unless the run is running
      under that attempt. Otherwise `Policy.after_failure/2` decides: the next attempt waits
      as retryable, or the run fails. Either way the lease is released, the category
      recorded and the attempt's finish stamped.
    * `renew_lease/4`, `complete/5` and `skip/5` act only on the running attempt, else
      refuse with `{:error, :stale_attempt}`. `active_attempt?/4` holds while the attempt
      runs under a lease that expires after `now`.
    * `inventory/1` lists every schedule by context, then key, each with the state, failure
      category and finish of its latest started run (nil before its first run).
    * `update_daily/6` applies an edit only at the expected revision, else
      `{:error, :conflict}`; `converge_daily_time_if_pristine!/4` and
      `activate_if_pristine!/3` only at revision 1. Each moves the revision on by one; the
      two daily-time edits also move the next run to the next slot of the new time.

  Every time is a UTC `DateTime`; stores keep it to the second.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type schedule :: %{
          schedule_key: String.t(),
          handler_key: String.t(),
          schedule_context: String.t(),
          cadence: String.t(),
          daily_at_utc: String.t(),
          enabled: boolean(),
          expiration_kind: String.t(),
          expires_at: DateTime.t() | nil,
          max_occurrences: pos_integer() | nil,
          claimed_occurrences: non_neg_integer(),
          expired_at: DateTime.t() | nil,
          next_run_at: DateTime.t(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
  @type run :: %{
          schedule_key: String.t(),
          claim_key: String.t(),
          claim_kind: String.t(),
          scheduled_for: DateTime.t() | nil,
          run_id: String.t(),
          schedule_revision: pos_integer(),
          occurrence_number: pos_integer() | nil,
          attempt: pos_integer(),
          state: String.t(),
          lease_expires_at: DateTime.t() | nil,
          next_attempt_at: DateTime.t() | nil,
          artifact_basename: String.t() | nil,
          artifact_sha256: String.t() | nil,
          artifact_bytes: non_neg_integer() | nil,
          failure_category: String.t() | nil,
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil
        }
  @type inventory_row :: map()
  @type stale :: {:error, :stale_attempt}

  @doc "A handle over the schedules the running application serves."
  @callback new() :: handle()

  @callback claim_due(handle(), now :: DateTime.t()) :: [run()]

  @callback claim_setup(
              handle(),
              schedule_key :: String.t(),
              claim_key :: String.t(),
              now :: DateTime.t()
            ) :: run()

  @callback fail_attempt(
              handle(),
              run_id :: String.t(),
              attempt :: pos_integer(),
              category :: atom(),
              now :: DateTime.t()
            ) :: {:retryable | :failed, run()} | stale()

  @callback renew_lease(handle(), run_id :: String.t(), pos_integer(), DateTime.t()) ::
              :ok | stale()

  @callback active_attempt?(handle(), run_id :: String.t(), pos_integer(), DateTime.t()) ::
              boolean()

  @callback complete(
              handle(),
              run_id :: String.t(),
              attempt :: pos_integer(),
              receipt :: map(),
              now :: DateTime.t()
            ) :: :ok | stale()

  @callback skip(
              handle(),
              run_id :: String.t(),
              attempt :: pos_integer(),
              category :: atom(),
              now :: DateTime.t()
            ) :: :ok | stale()

  @callback get_schedule(handle(), schedule_key :: String.t()) :: schedule() | nil

  @callback inventory(handle()) :: [inventory_row()]

  @callback update_daily(
              handle(),
              schedule_key :: String.t(),
              daily_at_utc :: String.t(),
              enabled :: boolean(),
              revision :: pos_integer(),
              now :: DateTime.t()
            ) :: {:ok, schedule()} | {:error, :conflict}

  @callback converge_daily_time_if_pristine!(
              handle(),
              schedule_key :: String.t(),
              daily_at_utc :: String.t(),
              now :: DateTime.t()
            ) :: {:ok, schedule()}

  @callback activate_if_pristine!(handle(), schedule_key :: String.t(), now :: DateTime.t()) ::
              :ok

  @spec claim_due(handle(), DateTime.t()) :: [run()]
  def claim_due(store, now), do: store.adapter.claim_due(store, now)

  @spec claim_setup(handle(), String.t(), String.t(), DateTime.t()) :: run()
  def claim_setup(store, schedule_key, claim_key, now),
    do: store.adapter.claim_setup(store, schedule_key, claim_key, now)

  @spec fail_attempt(handle(), String.t(), pos_integer(), atom(), DateTime.t()) ::
          {:retryable | :failed, run()} | stale()
  def fail_attempt(store, run_id, attempt, category, now),
    do: store.adapter.fail_attempt(store, run_id, attempt, category, now)

  @spec renew_lease(handle(), String.t(), pos_integer(), DateTime.t()) :: :ok | stale()
  def renew_lease(store, run_id, attempt, now),
    do: store.adapter.renew_lease(store, run_id, attempt, now)

  @spec active_attempt?(handle(), String.t(), pos_integer(), DateTime.t()) :: boolean()
  def active_attempt?(store, run_id, attempt, now),
    do: store.adapter.active_attempt?(store, run_id, attempt, now)

  @spec complete(handle(), String.t(), pos_integer(), map(), DateTime.t()) :: :ok | stale()
  def complete(store, run_id, attempt, receipt, now),
    do: store.adapter.complete(store, run_id, attempt, receipt, now)

  @spec skip(handle(), String.t(), pos_integer(), atom(), DateTime.t()) :: :ok | stale()
  def skip(store, run_id, attempt, category, now),
    do: store.adapter.skip(store, run_id, attempt, category, now)

  @spec get_schedule(handle(), String.t()) :: schedule() | nil
  def get_schedule(store, schedule_key), do: store.adapter.get_schedule(store, schedule_key)

  @spec inventory(handle()) :: [inventory_row()]
  def inventory(store), do: store.adapter.inventory(store)

  @spec update_daily(handle(), String.t(), String.t(), boolean(), pos_integer(), DateTime.t()) ::
          {:ok, schedule()} | {:error, :conflict}
  def update_daily(store, schedule_key, daily_at_utc, enabled, revision, now),
    do: store.adapter.update_daily(store, schedule_key, daily_at_utc, enabled, revision, now)

  @spec converge_daily_time_if_pristine!(handle(), String.t(), String.t(), DateTime.t()) ::
          {:ok, schedule()}
  def converge_daily_time_if_pristine!(store, schedule_key, daily_at_utc, now),
    do: store.adapter.converge_daily_time_if_pristine!(store, schedule_key, daily_at_utc, now)

  @spec activate_if_pristine!(handle(), String.t(), DateTime.t()) :: :ok
  def activate_if_pristine!(store, schedule_key, now),
    do: store.adapter.activate_if_pristine!(store, schedule_key, now)
end
