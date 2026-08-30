defmodule BnestApp.Scheduler do
  @moduledoc false

  use GenServer

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

  @impl GenServer
  def init(options) do
    state = %{
      clock: Keyword.get(options, :clock, &DateTime.utc_now/0),
      automatic?: Keyword.get(options, :automatic?, true)
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:reconcile, _from, state) do
    dispatch(state.clock.())
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    dispatch(state.clock.())
    if state.automatic?, do: Process.send_after(self(), :tick, @tick_ms)
    {:noreply, state}
  end

  defp dispatch(now) do
    now
    |> Store.claim_due()
    |> Enum.each(fn claim ->
      Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn -> Run.execute(claim, now) end)
    end)
  rescue
    _schema_not_ready -> :ok
  end
end
