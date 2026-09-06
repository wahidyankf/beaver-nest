defmodule BnestApp.DataRepository do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.Storage.Lock

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec store(GenServer.server()) :: term()
  def store(server \\ __MODULE__), do: GenServer.call(server, :store)

  @spec read(atom(), term(), GenServer.server()) :: {:ok, map()} | {:error, atom()}
  def read(type, identity, server \\ __MODULE__) do
    with_backend(server, & &1.read(&2, type, identity))
  end

  @spec write(atom(), term(), non_neg_integer() | nil, map(), GenServer.server()) ::
          {:ok, map()} | {:error, atom()}
  def write(type, identity, expected_revision, candidate, server \\ __MODULE__) do
    with_backend(server, & &1.write(&2, type, identity, expected_revision, candidate))
  end

  @spec put_new(atom(), term(), map(), GenServer.server()) :: {:ok, map()} | {:error, atom()}
  def put_new(type, identity, candidate, server \\ __MODULE__) do
    with_backend(server, & &1.put_new(&2, type, identity, candidate))
  end

  @spec replace(atom(), term(), map(), GenServer.server()) :: {:ok, map()} | {:error, atom()}
  def replace(type, identity, candidate, server \\ __MODULE__) do
    with_backend(server, & &1.replace(&2, type, identity, candidate))
  end

  @spec remove_exact(atom(), term(), map(), GenServer.server()) :: :ok | {:error, atom()}
  def remove_exact(type, identity, expected, server \\ __MODULE__) do
    with_backend(server, & &1.remove_exact(&2, type, identity, expected))
  end

  # Every operation holds a shared storage lease for its whole duration, so a concurrent
  # exclusive holder cannot swap the backend mid-call. The lock and coordinator come from
  # process state purely so a test can supply doubles; production always gets the real ones.
  defp with_backend(server, fun) do
    context = GenServer.call(server, :context)

    context.lock.with_shared(fn ->
      {backend, state} = context.coordinator.active_backend(context.store)
      fun.(backend, state)
    end)
  end

  @impl GenServer
  def init(options) do
    {:ok,
     %{
       store: Keyword.fetch!(options, :store),
       lock: Keyword.get(options, :lock, Lock),
       coordinator: Keyword.get(options, :coordinator, StorageCoordinator)
     }}
  end

  @impl GenServer
  def handle_call(:store, _from, context), do: {:reply, context.store, context}
  def handle_call(:context, _from, context), do: {:reply, context, context}
end
