defmodule BnestApp.Scheduler.Run do
  @moduledoc false

  alias BnestApp.Scheduler.Registry
  alias BnestApp.Scheduler.Store

  @spec execute(map(), DateTime.t()) :: :ok
  def execute(claim, %DateTime{} = now) do
    renewer = start_lease_renewer(claim)
    schedule = Store.get_schedule(claim.schedule_key)

    result =
      with %{handler_key: handler_key} <- schedule,
           {:ok, %{handler: handler}} <- Registry.fetch(handler_key) do
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

    spawn(fn ->
      monitor = Process.monitor(parent)
      renew_loop(monitor, claim)
    end)
  end

  defp renew_loop(monitor, claim) do
    receive do
      :stop ->
        Process.demonitor(monitor, [:flush])
        :ok

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        :ok
    after
      60_000 ->
        case Store.renew_lease(claim.run_id, claim.attempt, DateTime.utc_now()) do
          :ok -> renew_loop(monitor, claim)
          {:error, :stale_attempt} -> :ok
        end
    end
  rescue
    _repository_unavailable -> :ok
  end

  defp record_failure(claim, category, now) do
    _result = Store.fail_attempt(claim.run_id, claim.attempt, category, now)
    :ok
  end
end
