defmodule BnestApp.TestInstance.Requests do
  @moduledoc false

  # Which web requests are still running. A browser that closes while a request is in flight does not
  # cancel the server's work on it, so the work would run against the next state of the server: after a
  # drop it finds no instance and opens the profile's default database in the data-free run base, and
  # during a spawn it races the migration. The switch therefore waits for these requests to end before it
  # changes anything (ADR 001, section 1, quiescence).
  #
  # Phoenix reports each request through `[:phoenix, :endpoint, :start | :stop | :exception]` in the
  # request's own process, so that process is the key. The testing-control routes are not counted, because
  # the request that asks for a drop is one of them.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @table __MODULE__
  @handler_id "bnest-test-instance-requests"
  @control_prefix "/__bnest_testing/"
  @poll_ms 10

  @doc "Starts counting. Safe to call again; it does nothing once counting has started."
  @spec attach!() :: :ok
  def attach! do
    ensure_table!()

    case :telemetry.attach_many(
           @handler_id,
           [
             [:phoenix, :endpoint, :start],
             [:phoenix, :endpoint, :stop],
             [:phoenix, :endpoint, :exception]
           ],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "How many counted requests are running now."
  @spec in_flight() :: non_neg_integer()
  def in_flight do
    case :ets.whereis(@table) do
      :undefined -> 0
      _table -> @table |> :ets.select([{{:"$1"}, [], [:"$1"]}]) |> Enum.count(&Process.alive?/1)
    end
  end

  @doc "`:ok` once no counted request is running, or `{:error, :timeout}` after `timeout_ms`."
  @spec await_idle(non_neg_integer()) :: :ok | {:error, :timeout}
  def await_idle(timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_idle(deadline)
  end

  defp do_await_idle(deadline) do
    cond do
      in_flight() == 0 ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(@poll_ms)
        do_await_idle(deadline)
    end
  end

  @doc false
  def handle_event([:phoenix, :endpoint, :start], _measurements, %{conn: conn}, _config) do
    unless String.starts_with?(conn.request_path, @control_prefix),
      do: :ets.insert(@table, {self()})

    :ok
  end

  def handle_event([:phoenix, :endpoint, _stop_or_exception], _measurements, _metadata, _config) do
    :ets.delete(@table, self())
    :ok
  end

  # The table belongs to a process that outlives every request, so counting never loses its table.
  defp ensure_table! do
    if :ets.whereis(@table) == :undefined do
      parent = self()
      ref = make_ref()

      spawn(fn ->
        try do
          :ets.new(@table, [:named_table, :public, :set])
          send(parent, {ref, :created})
        rescue
          # Another caller created it first.
          ArgumentError -> send(parent, {ref, :created})
        end

        Process.sleep(:infinity)
      end)

      receive do
        {^ref, :created} -> :ok
      after
        5_000 -> raise "the request table was not created"
      end
    end

    :ok
  end
end
