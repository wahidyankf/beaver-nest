defmodule BnestApp.Scheduler do
  @moduledoc """
  The Scheduler bounded context: persisted daily schedules, the runs claimed from them, and
  the one coordinator process that claims due work every minute and runs each claim's
  registered task.

  This module is the context's facade and that process. The admin schedules page, the
  release migrations, Family Chat's release convergence and the task adapters call only
  this module, its exported `Domain` (the time rules) and `Ports` (the task behaviour). Its
  configuration (`config :bnest_app, BnestApp.Scheduler`) names the `:schedule_store`
  adapter, the `:tasks` registered per handler key (see `TaskRegistry`), and the
  `:tick_handlers` run on every regular tick. The Scheduler therefore names no other
  context: the contexts with scheduled work reach it through their task adapters, and it
  reaches them only through configuration.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [],
    exports: [{Domain, []}, {Ports, []}]

  use GenServer

  alias BnestApp.Scheduler.Domain.Policy
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.Scheduler.Run
  alias BnestApp.Scheduler.TaskRegistry

  @tick_ms 60_000

  @doc """
  A configured value: `:schedule_store` (the adapter module), `:tasks` (the registered
  tasks by handler key) or `:tick_handlers` (`{module, function, arguments}` run each tick).
  """
  @spec configuration(atom()) :: term()
  def configuration(key),
    do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)

  @doc "A handle over the configured schedule store."
  @spec store() :: ScheduleStore.handle()
  def store, do: configuration(:schedule_store).new()

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
  `update_daily/3`'s own optimistic-concurrency pattern: a
  schedule row is only ever at revision 1 when it has never been through an
  operator edit (every edit bumps revision), so this fires exactly once
  across any number of calls or restarts, on both a freshly-seeded row and a
  pre-existing one, and is a strict no-op once an operator has touched the
  schedule.
  """
  @spec converge_backup_time!(String.t(), String.t()) :: {:ok, map()}
  def converge_backup_time!(schedule_key, daily_at_utc)
      when is_binary(schedule_key) and is_binary(daily_at_utc) do
    ScheduleStore.converge_daily_time_if_pristine!(
      store(),
      schedule_key,
      daily_at_utc,
      DateTime.utc_now()
    )
  end

  @doc """
  Enables a still-pristine (revision 1) schedule once, through the same CAS as
  `converge_backup_time!/2`; a no-op after any edit.
  """
  @spec activate_if_pristine!(String.t(), DateTime.t()) :: :ok
  def activate_if_pristine!(schedule_key, %DateTime{} = now),
    do: ScheduleStore.activate_if_pristine!(store(), schedule_key, now)

  @doc "Claims every due slot and recoverable run at `now`; see `Ports.ScheduleStore`."
  @spec claim_due(DateTime.t()) :: [ScheduleStore.run()]
  def claim_due(%DateTime{} = now), do: ScheduleStore.claim_due(store(), now)

  @doc "Claims, once per destination, the setup run that verifies a new backup destination."
  @spec claim_setup(String.t(), String.t(), DateTime.t()) ::
          {:ok, ScheduleStore.run()} | {:error, :invalid_destination_id}
  def claim_setup(schedule_key, destination_id, %DateTime{} = now)
      when is_binary(schedule_key) and is_binary(destination_id) do
    if Policy.valid_destination_id?(destination_id) do
      claim_key = Policy.setup_claim_key(destination_id)
      {:ok, ScheduleStore.claim_setup(store(), schedule_key, claim_key, now)}
    else
      {:error, :invalid_destination_id}
    end
  end

  @spec get_schedule(String.t()) :: ScheduleStore.schedule() | nil
  def get_schedule(schedule_key), do: ScheduleStore.get_schedule(store(), schedule_key)

  @doc "Every schedule with its latest run, grouped into the family and admin/system contexts."
  @spec admin_inventory() :: %{family: [map()], admin_system: [map()]}
  def admin_inventory do
    schedules = ScheduleStore.inventory(store())

    %{
      family: Enum.filter(schedules, &(&1.schedule_context == "family")),
      admin_system: Enum.filter(schedules, &(&1.schedule_context == "admin_system"))
    }
  end

  @spec family_inventory() :: [map()]
  def family_inventory,
    do: store() |> ScheduleStore.inventory() |> Enum.filter(&(&1.schedule_context == "family"))

  @doc """
  Applies an operator's daily edit (`"daily_time_wib"`, `"enabled"`, `"revision"`) to an
  editable schedule, at the revision the operator read.
  """
  @spec update_daily(String.t(), map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
  def update_daily(schedule_key, params, %DateTime{} = now) do
    store = store()

    with %{} = schedule <- ScheduleStore.get_schedule(store, schedule_key),
         {:ok, edit} <- Policy.daily_edit(schedule, params) do
      ScheduleStore.update_daily(
        store,
        schedule_key,
        edit.daily_at_utc,
        edit.enabled,
        edit.revision,
        now
      )
    else
      nil -> {:error, :unknown_schedule}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Records a claimed attempt as verified with the artifact its task's receipt names."
  @spec complete_run(String.t(), pos_integer(), map(), DateTime.t()) ::
          :ok | {:error, :stale_attempt}
  def complete_run(run_id, attempt, receipt, %DateTime{} = now),
    do: ScheduleStore.complete(store(), run_id, attempt, receipt, now)

  @doc "Records a claimed attempt as skipped under `category`."
  @spec skip_run(String.t(), pos_integer(), atom(), DateTime.t()) ::
          :ok | {:error, :stale_attempt}
  def skip_run(run_id, attempt, category, %DateTime{} = now),
    do: ScheduleStore.skip(store(), run_id, attempt, category, now)

  @doc "Whether the attempt still runs under a lease that outlasts `now`."
  @spec active_attempt?(String.t(), pos_integer(), DateTime.t()) :: boolean()
  def active_attempt?(run_id, attempt, %DateTime{} = now),
    do: ScheduleStore.active_attempt?(store(), run_id, attempt, now)

  @doc "The task module registered under a handler key."
  @spec registered_handler(String.t()) :: {:ok, module()} | :error
  def registered_handler(handler_key) do
    case TaskRegistry.fetch(handler_key) do
      {:ok, %{handler: handler}} -> {:ok, handler}
      :error -> :error
    end
  end

  @doc "The registered task entry for a handler key: its label, context and typed settings."
  @spec task_entry(String.t()) :: {:ok, map()} | :error
  def task_entry(handler_key), do: TaskRegistry.fetch(handler_key)

  @doc "Every registered task entry, by handler key."
  @spec task_entries() :: %{String.t() => map()}
  def task_entries, do: TaskRegistry.entries()

  @doc """
  Runs one claimed attempt at `now` through the task registered for its schedule, in the
  calling process, and records a failed attempt when the task fails.
  """
  @spec execute(map(), DateTime.t()) :: :ok
  def execute(claim, %DateTime{} = now), do: Run.execute(claim, now)

  @doc """
  Runs one claimed attempt now, in the background: under the Scheduler's task supervisor
  when it runs, else in an unsupervised task.
  """
  @spec run_now(map()) :: {:ok, pid()} | {:error, term()}
  def run_now(claim) do
    case Process.whereis(BnestApp.Scheduler.Tasks) do
      nil ->
        Task.start(fn -> execute(claim, DateTime.utc_now()) end)

      _pid ->
        Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
          execute(claim, DateTime.utc_now())
        end)
    end
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
    |> claim_due()
    |> Enum.each(fn claim ->
      Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn -> execute(claim, now) end)
    end)

    if Keyword.fetch!(opts, :dispatch_push?), do: run_tick_handlers()
  rescue
    _schema_not_ready -> :ok
  end

  # No File-Impact entry names a dedicated push-dispatch poller module, and
  # `bnest_schedules`/`claim_due/1` is a daily-cadence primitive, not suited
  # to Web Push's sub-minute (30s/2m/8m/32m) backoff. This reuses the
  # existing 60s tick and `Scheduler.Tasks` supervisor instead of adding a
  # new supervised process: every tick also runs the configured tick handlers,
  # which drain whatever push deliveries are currently due. Documented as a Phase 5
  # design decision in learnings.md, not something tech-doc 004/007 spells out explicitly.
  #
  # Skipped specifically on the boot/restart-triggered first tick (see
  # `dispatch/2`'s `dispatch_push?` and `handle_info({:tick, origin}, ...)`):
  # the push dispatch self-heals the Family Chat room store's storage connection
  # independently of whatever path the caller who just restarted this
  # process was relying on, which is safe in production (both resolve to
  # the same configured path there) but not in a test suite, where each
  # domain intentionally uses its own isolated database and this process
  # restarting is itself sometimes the very thing under test. Deferring
  # push dispatch to the next regular tick (at most one `@tick_ms` later)
  # avoids that self-heal firing at the one moment another in-flight
  # operation cannot tolerate the shared connection being redirected.
  defp run_tick_handlers do
    Enum.each(configuration(:tick_handlers), fn {module, function, arguments} ->
      Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
        apply(module, function, arguments)
      end)
    end)
  rescue
    _schema_not_ready -> :ok
  end
end
