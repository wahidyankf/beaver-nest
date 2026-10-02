defmodule BnestApp.Test.InMemory.ScheduleStore do
  @moduledoc """
  An Agent-backed `BnestApp.Scheduler.Ports.ScheduleStore`. It keeps the port's semantics
  without SQL: the due, ordering and fencing rules the port documents, with each claim,
  recovery and failure decided by `BnestApp.Scheduler.Domain.Policy`, as the SQLite store
  decides them.

  `start/0` gives a test its own store. The unit layer also configures this module as the
  Scheduler's `:schedule_store`; its `new/0` then serves the store a test started with
  `install/0`, which the test supervisor stops before the next test. Schedules come to exist
  from release seeds, which no port callback writes, so the test seam `put_schedule/2`
  stores one as is; `runs/1` reads back every run, oldest claim first.
  """

  @behaviour BnestApp.Scheduler.Ports.ScheduleStore

  alias BnestApp.Scheduler.Domain.Policy

  @schedule_times [:expires_at, :expired_at, :next_run_at, :inserted_at, :updated_at]

  @doc "A fresh store with no schedule, linked to the calling test."
  def start do
    {:ok, pid} = Agent.start_link(&empty/0)
    %{adapter: __MODULE__, pid: pid}
  end

  @doc """
  Starts a fresh store under the calling test's supervisor as the store `new/0` serves,
  replacing one this test installed before, and returns its handle.
  """
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [&empty/0, [name: __MODULE__]]}
    })

    new()
  end

  # Configured as the unit layer's `:schedule_store`, so the Scheduler facade and every
  # task it runs reach the store the current test installed. Without one it fails loudly
  # rather than serve a store nobody seeded or reads.
  @impl true
  def new do
    case GenServer.whereis(__MODULE__) do
      nil ->
        raise ArgumentError,
              "no in-memory schedule store is installed; call #{inspect(__MODULE__)}.install/0 " <>
                "in the test before reaching BnestApp.Scheduler"

      pid ->
        %{adapter: __MODULE__, pid: pid}
    end
  end

  @doc "Stores `schedule` as is, replacing the schedule with its key; its runs stay."
  def put_schedule(%{pid: pid}, schedule) do
    schedule = Enum.reduce(@schedule_times, schedule, &Map.update!(&2, &1, fn t -> second(t) end))

    Agent.update(pid, fn state -> put_in(state, [:schedules, schedule.schedule_key], schedule) end)
  end

  @doc """
  Stores a pristine (revision 1), enabled, never-expiring daily schedule of `handler_key` in
  `context`, due at the latest slot of its daily time before `now`, the way the release
  seeds and `BnestApp.Test.Seeds.Schedules` put one; `fields` replaces any of its fields.
  The daily time defaults to 19:00 UTC.
  """
  def put_daily_schedule(store, key, handler_key, context, %DateTime{} = now, fields \\ %{}) do
    daily_at_utc = Map.get(fields, :daily_at_utc, "19:00")

    schedule =
      Map.merge(
        %{
          schedule_key: key,
          handler_key: handler_key,
          schedule_context: context,
          cadence: "daily",
          daily_at_utc: daily_at_utc,
          enabled: true,
          expiration_kind: "never",
          expires_at: nil,
          max_occurrences: nil,
          claimed_occurrences: 0,
          expired_at: nil,
          next_run_at: Policy.latest_slot(daily_at_utc, now),
          revision: 1,
          inserted_at: now,
          updated_at: now
        },
        fields
      )

    put_schedule(store, schedule)
  end

  @doc "Every run the store holds, oldest claim first."
  def runs(%{pid: pid}), do: Agent.get(pid, &Enum.reverse(&1.runs))

  @impl true
  def claim_due(%{pid: pid}, now) do
    now = second(now)

    Agent.get_and_update(pid, fn state ->
      {scheduled, state} =
        state.schedules
        |> Map.values()
        |> Enum.filter(&due?(&1, now))
        |> Enum.sort_by(&{DateTime.to_unix(&1.next_run_at), &1.schedule_key})
        |> Enum.flat_map_reduce(state, &claim_schedule(&1, now, &2))

      {recovered, state} = recover_runs(state, now)
      {scheduled ++ recovered, state}
    end)
  end

  @impl true
  def claim_setup(%{pid: pid}, schedule_key, claim_key, now) do
    now = second(now)

    pid
    |> Agent.get_and_update(fn state ->
      case {state.schedules[schedule_key], find_run(state, schedule_key, claim_key)} do
        {nil, _run} ->
          {:unknown_schedule, state}

        {_schedule, %{} = run} ->
          {run, state}

        {schedule, nil} ->
          run =
            new_run(schedule, %{
              claim_key: claim_key,
              claim_kind: "setup",
              scheduled_for: nil,
              occurrence_number: nil,
              lease_expires_at: Policy.lease_until(now),
              started_at: now
            })

          {run, add_run(state, run)}
      end
    end)
    |> case do
      :unknown_schedule -> raise "unknown schedule"
      run -> run
    end
  end

  @impl true
  def fail_attempt(store, run_id, attempt, category, now) do
    now = second(now)

    update_running(store, run_id, attempt, fn run ->
      case Policy.after_failure(run.attempt, now) do
        {:retryable, next_attempt, next_attempt_at} ->
          retry = %{
            run
            | state: "retryable",
              attempt: next_attempt,
              lease_expires_at: nil,
              next_attempt_at: next_attempt_at,
              failure_category: Atom.to_string(category),
              finished_at: now
          }

          {{:retryable, retry}, retry}

        :failed ->
          failed = finish(run, "failed", Atom.to_string(category), now)
          {{:failed, failed}, failed}
      end
    end)
  end

  @impl true
  def renew_lease(store, run_id, attempt, now) do
    update_running(store, run_id, attempt, fn run ->
      {:ok, %{run | lease_expires_at: Policy.lease_until(second(now))}}
    end)
  end

  @impl true
  def active_attempt?(%{pid: pid}, run_id, attempt, now) do
    case Agent.get(pid, &find_run(&1, run_id)) do
      %{state: "running", attempt: ^attempt, lease_expires_at: %DateTime{} = lease} ->
        DateTime.compare(lease, second(now)) == :gt

      _not_running ->
        false
    end
  end

  @impl true
  def complete(store, run_id, attempt, receipt, now) do
    update_running(store, run_id, attempt, fn run ->
      verified = %{
        finish(run, "verified", nil, second(now))
        | artifact_basename: receipt["artifactBasename"],
          artifact_sha256: receipt["artifactSha256"],
          artifact_bytes: receipt["artifactBytes"]
      }

      {:ok, verified}
    end)
  end

  @impl true
  def skip(store, run_id, attempt, category, now) do
    update_running(store, run_id, attempt, fn run ->
      {:ok, finish(run, "skipped", Atom.to_string(category), second(now))}
    end)
  end

  @impl true
  def get_schedule(%{pid: pid}, schedule_key), do: Agent.get(pid, & &1.schedules[schedule_key])

  @impl true
  def inventory(%{pid: pid}) do
    Agent.get(pid, fn state ->
      state.schedules
      |> Map.values()
      |> Enum.sort_by(&{&1.schedule_context, &1.schedule_key})
      |> Enum.map(fn schedule ->
        latest =
          state.runs
          |> Enum.filter(&(&1.schedule_key == schedule.schedule_key))
          |> Enum.max_by(&{DateTime.to_unix(&1.started_at), &1.run_id}, fn -> %{} end)

        Map.merge(schedule, %{
          last_run_state: latest[:state],
          last_failure_category: latest[:failure_category],
          last_finished_at: latest[:finished_at]
        })
      end)
    end)
  end

  @impl true
  def update_daily(%{pid: pid}, schedule_key, daily_at_utc, enabled, revision, now) do
    now = second(now)

    Agent.get_and_update(pid, fn state ->
      case state.schedules[schedule_key] do
        %{revision: ^revision} = schedule ->
          updated = %{
            schedule
            | daily_at_utc: daily_at_utc,
              enabled: enabled,
              next_run_at: Policy.next_slot(daily_at_utc, now),
              revision: revision + 1,
              updated_at: now
          }

          {{:ok, updated}, put_in(state.schedules[schedule_key], updated)}

        _missing_or_changed ->
          {{:error, :conflict}, state}
      end
    end)
  end

  @impl true
  def converge_daily_time_if_pristine!(%{pid: pid}, schedule_key, daily_at_utc, now) do
    now = second(now)

    pid
    |> Agent.get_and_update(fn state ->
      case state.schedules[schedule_key] do
        %{revision: 1} = schedule ->
          converged = %{
            schedule
            | daily_at_utc: daily_at_utc,
              next_run_at: Policy.next_slot(daily_at_utc, now),
              revision: 2,
              updated_at: now
          }

          {converged, put_in(state.schedules[schedule_key], converged)}

        other ->
          {other, state}
      end
    end)
    |> case do
      nil -> raise "unknown schedule"
      schedule -> {:ok, schedule}
    end
  end

  @impl true
  def activate_if_pristine!(%{pid: pid}, schedule_key, now) do
    Agent.update(pid, fn state ->
      case state.schedules[schedule_key] do
        %{revision: 1} = schedule ->
          activated = %{schedule | enabled: true, revision: 2, updated_at: second(now)}
          put_in(state.schedules[schedule_key], activated)

        _missing_or_edited ->
          state
      end
    end)
  end

  defp empty, do: %{schedules: %{}, runs: []}

  defp due?(schedule, now),
    do:
      schedule.enabled and is_nil(schedule.expired_at) and
        DateTime.compare(schedule.next_run_at, now) != :gt

  defp claim_schedule(schedule, now, state) do
    case Policy.claim(schedule, now) do
      :expire ->
        expired = %{schedule | expired_at: now, updated_at: now}
        {[], put_in(state.schedules[schedule.schedule_key], expired)}

      {:claim, claim} ->
        if find_run(state, schedule.schedule_key, claim.claim_key) do
          {[], state}
        else
          run =
            new_run(schedule, %{
              claim_key: claim.claim_key,
              claim_kind: "scheduled",
              scheduled_for: claim.scheduled_for,
              occurrence_number: claim.occurrence_number,
              lease_expires_at: claim.lease_expires_at,
              started_at: now
            })

          claimed = %{
            schedule
            | claimed_occurrences: claim.occurrence_number,
              expired_at: claim.expired_at,
              next_run_at: claim.next_run_at,
              updated_at: now
          }

          {[run], state |> add_run(run) |> put_in([:schedules, schedule.schedule_key], claimed)}
        end
    end
  end

  defp recover_runs(state, now) do
    state.runs
    |> Enum.filter(&recoverable?(&1, now))
    |> Enum.sort_by(&{DateTime.to_unix(&1.started_at), &1.run_id})
    |> Enum.flat_map_reduce(state, fn run, state ->
      case Policy.recovery(run) do
        :attempt_limit ->
          {[], replace_run(state, finish(run, "failed", "attempt_limit", now))}

        {:run, attempt} ->
          again = %{
            run
            | state: "running",
              attempt: attempt,
              lease_expires_at: Policy.lease_until(now),
              next_attempt_at: nil,
              failure_category: nil,
              started_at: now,
              finished_at: nil
          }

          {[again], replace_run(state, again)}
      end
    end)
  end

  defp recoverable?(%{state: "retryable", next_attempt_at: %DateTime{} = at}, now),
    do: DateTime.compare(at, now) != :gt

  defp recoverable?(%{state: "running", lease_expires_at: %DateTime{} = lease}, now),
    do: DateTime.compare(lease, now) != :gt

  defp recoverable?(_run, _now), do: false

  # Applies `fun` to the run when it is running under `attempt`, else refuses as stale.
  defp update_running(%{pid: pid}, run_id, attempt, fun) do
    Agent.get_and_update(pid, fn state ->
      case find_run(state, run_id) do
        %{state: "running", attempt: ^attempt} = run ->
          {reply, updated} = fun.(run)
          {reply, replace_run(state, updated)}

        _stale ->
          {{:error, :stale_attempt}, state}
      end
    end)
  end

  defp finish(run, state, failure_category, now),
    do: %{
      run
      | state: state,
        lease_expires_at: nil,
        next_attempt_at: nil,
        failure_category: failure_category,
        finished_at: now
    }

  defp new_run(schedule, fields) do
    Map.merge(
      %{
        schedule_key: schedule.schedule_key,
        run_id: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
        schedule_revision: schedule.revision,
        attempt: 1,
        state: "running",
        next_attempt_at: nil,
        artifact_basename: nil,
        artifact_sha256: nil,
        artifact_bytes: nil,
        failure_category: nil,
        finished_at: nil
      },
      fields
    )
  end

  defp add_run(state, run), do: %{state | runs: [run | state.runs]}

  defp replace_run(state, run),
    do: %{state | runs: Enum.map(state.runs, &if(&1.run_id == run.run_id, do: run, else: &1))}

  defp find_run(state, run_id), do: Enum.find(state.runs, &(&1.run_id == run_id))

  defp find_run(state, schedule_key, claim_key),
    do: Enum.find(state.runs, &(&1.schedule_key == schedule_key and &1.claim_key == claim_key))

  defp second(nil), do: nil
  defp second(%DateTime{} = time), do: DateTime.truncate(time, :second)
end
