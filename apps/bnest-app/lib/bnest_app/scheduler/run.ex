defmodule BnestApp.Scheduler.Run do
  @moduledoc false

  alias BnestApp.Scheduler
  alias BnestApp.Scheduler.Ports.ScheduleStore
  alias BnestApp.Scheduler.TaskRegistry

  @spec execute(map(), DateTime.t()) :: :ok
  def execute(claim, %DateTime{} = now) do
    renewer = start_lease_renewer(claim)
    schedule = ScheduleStore.get_schedule(Scheduler.store(), claim.schedule_key)

    result =
      with %{handler_key: handler_key} <- schedule,
           {:ok, %{handler: handler}} <- TaskRegistry.fetch(handler_key) do
        handler.execute(claim, now)
      else
        _unknown -> {:error, :unknown_handler}
      end

    finish(renewer, result, claim, now)
  rescue
    _error -> record_failure(claim, :handler_failed, now)
  end

  defp finish(renewer, result, claim, now) do
    send(renewer, :stop)

    case result do
      {:ok, _safe_result} -> :ok
      {:skipped, _category} -> :ok
      {:error, category} -> record_failure(claim, category, now)
    end
  end

  defp start_lease_renewer(claim) do
    parent = self()
    store = Scheduler.store()
    interval = Scheduler.configuration(:lease_renewal_interval_ms)

    spawn(fn ->
      monitor = Process.monitor(parent)
      renew_loop(monitor, store, claim, interval)
    end)
  end

  defp renew_loop(monitor, store, claim, interval) do
    receive do
      :stop ->
        Process.demonitor(monitor, [:flush])
        :ok

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        :ok
    after
      interval ->
        case ScheduleStore.renew_lease(store, claim.run_id, claim.attempt, DateTime.utc_now()) do
          :ok -> renew_loop(monitor, store, claim, interval)
          {:error, :stale_attempt} -> :ok
        end
    end
  rescue
    _repository_unavailable -> :ok
  end

  defp record_failure(claim, category, now) do
    _result =
      ScheduleStore.fail_attempt(Scheduler.store(), claim.run_id, claim.attempt, category, now)

    :ok
  rescue
    # Best-effort bookkeeping: the SQLite store already retries a transiently absent
    # repo (see `Adapters.SqliteScheduleStore`'s `with_repo_retry/1` comment) but does
    # not retry forever. If the repo is still unavailable, or this run's own
    # database has since been swapped out from under a task that outlived
    # its scenario/module, there is nothing left to record -- the claim
    # itself is moot. Mirrors `renew_loop/4`'s identical posture above.
    _repository_unavailable -> :ok
  catch
    :exit, _reason -> :ok
  end
end
