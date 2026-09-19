defmodule BnestApp.Scheduler do
  @moduledoc false

  use GenServer

  alias BnestApp.PushNotifications
  alias BnestApp.Scheduler.Run
  alias BnestApp.Scheduler.Store

  @tick_ms 60_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @spec reconcile() :: :ok
  def reconcile, do: GenServer.call(__MODULE__, :reconcile)

  @spec ready?() :: boolean()
  def ready?,
    do: is_pid(Process.whereis(__MODULE__)) and is_pid(Process.whereis(BnestApp.Scheduler.Tasks))

  @doc """
  One-time release reconciliation (tech-doc 002: "the public Scheduler
  service reconciles both fresh and existing backup schedules to
  `daily_at_utc = 18:00` once... later operator changes remain valid and are
  not overwritten by ordinary startup"). CAS on `revision = 1`, mirroring
  `Scheduler.Store.update_daily/3`'s own optimistic-concurrency pattern: a
  schedule row is only ever at revision 1 when it has never been through an
  operator edit (every edit bumps revision), so this fires exactly once
  across any number of calls or restarts, on both a freshly-seeded row and a
  pre-existing one, and is a strict no-op once an operator has touched the
  schedule.
  """
  @spec converge_backup_time!(String.t(), String.t()) :: {:ok, map()}
  def converge_backup_time!(schedule_key, daily_at_utc)
      when is_binary(schedule_key) and is_binary(daily_at_utc) do
    Store.converge_daily_time_if_pristine!(schedule_key, daily_at_utc, DateTime.utc_now())
  end

  @impl GenServer
  def init(options) do
    state = %{
      clock: Keyword.get(options, :clock, &DateTime.utc_now/0),
      automatic?: Keyword.get(options, :automatic?, true)
    }

    send(self(), {:tick, :boot})
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:reconcile, _from, state) do
    dispatch(state.clock.(), dispatch_push?: true)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:tick, origin}, state) do
    dispatch(state.clock.(), dispatch_push?: origin != :boot)
    if state.automatic?, do: Process.send_after(self(), {:tick, :interval}, @tick_ms)
    {:noreply, state}
  end

  defp dispatch(now, opts) do
    now
    |> Store.claim_due()
    |> Enum.each(fn claim ->
      Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn -> Run.execute(claim, now) end)
    end)

    if Keyword.fetch!(opts, :dispatch_push?), do: dispatch_push_notifications()
  rescue
    _schema_not_ready -> :ok
  end

  # No File-Impact entry names a dedicated push-dispatch poller module, and
  # `bnest_schedules`/`claim_due/1` is a daily-cadence primitive, not suited
  # to Web Push's sub-minute (30s/2m/8m/32m) backoff. This reuses the
  # existing 60s tick and `Scheduler.Tasks` supervisor instead of adding a
  # new supervised process: every tick also drains whatever push deliveries
  # are currently due. Documented as a Phase 5 design decision in
  # learnings.md, not something tech-doc 004/007 spells out explicitly.
  #
  # Skipped specifically on the boot/restart-triggered first tick (see
  # `dispatch/2`'s `dispatch_push?` and `handle_info({:tick, origin}, ...)`):
  # this call self-heals `FamilyChatStore`'s own storage connection
  # independently of whatever path the caller who just restarted this
  # process was relying on, which is safe in production (both resolve to
  # the same configured path there) but not in a test suite, where each
  # domain intentionally uses its own isolated database and this process
  # restarting is itself sometimes the very thing under test. Deferring
  # push dispatch to the next regular tick (at most one `@tick_ms` later)
  # avoids that self-heal firing at the one moment another in-flight
  # operation cannot tolerate the shared connection being redirected.
  defp dispatch_push_notifications do
    Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
      PushNotifications.dispatch_all_due!()
    end)
  rescue
    _schema_not_ready -> :ok
  end
end
