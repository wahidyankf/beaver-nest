defmodule BnestApp.DataRepository do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.DataRepository.Store
  alias BnestApp.Storage.Lock

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @spec store() :: Store.t()
  def store, do: GenServer.call(__MODULE__, :store)

  @spec read(atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(type, identity) do
    Lock.with_shared(fn ->
      {backend, state} = backend()
      backend.read(state, type, identity)
    end)
  end

  @spec write(atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(type, identity, expected_revision, candidate) do
    Lock.with_shared(fn ->
      {backend, state} = backend()
      backend.write(state, type, identity, expected_revision, candidate)
    end)
  end

  @spec put_new(atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(type, identity, candidate) do
    Lock.with_shared(fn ->
      {backend, state} = backend()
      backend.put_new(state, type, identity, candidate)
    end)
  end

  @spec replace(atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(type, identity, candidate) do
    Lock.with_shared(fn ->
      {backend, state} = backend()
      backend.replace(state, type, identity, candidate)
    end)
  end

  @spec remove_exact(atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(type, identity, expected) do
    Lock.with_shared(fn ->
      {backend, state} = backend()
      backend.remove_exact(state, type, identity, expected)
    end)
  end

  defp backend, do: StorageCoordinator.active_backend(store())

  @impl GenServer
  def init(options), do: {:ok, options |> Keyword.fetch!(:root) |> Store.new!()}

  @impl GenServer
  def handle_call(:store, _from, store), do: {:reply, store, store}
end
