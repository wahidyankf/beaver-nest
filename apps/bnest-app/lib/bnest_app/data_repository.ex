defmodule BnestApp.DataRepository do
  @moduledoc false

  use GenServer

  alias BnestApp.DataRepository.Store

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @spec store() :: Store.t()
  def store, do: GenServer.call(__MODULE__, :store)

  @spec read(atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(type, identity), do: Store.read(store(), type, identity)

  @spec write(atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(type, identity, expected_revision, candidate),
    do: Store.write(store(), type, identity, expected_revision, candidate)

  @spec put_new(atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(type, identity, candidate), do: Store.put_new(store(), type, identity, candidate)

  @spec replace(atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(type, identity, candidate), do: Store.replace(store(), type, identity, candidate)

  @spec remove_exact(atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(type, identity, expected),
    do: Store.remove_exact(store(), type, identity, expected)

  @impl GenServer
  def init(options), do: {:ok, options |> Keyword.fetch!(:root) |> Store.new!()}

  @impl GenServer
  def handle_call(:store, _from, store), do: {:reply, store, store}
end
