defmodule BnestApp.DataRepository.Backend do
  @moduledoc false

  @callback read(state :: term(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  @callback write(state :: term(), atom(), term(), non_neg_integer() | nil, map()) ::
              {:ok, map()} | {:error, atom()}
  @callback put_new(state :: term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback replace(state :: term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback remove_exact(state :: term(), atom(), term(), map()) :: :ok | {:error, atom()}
  @callback identity_files_empty?(state :: term()) :: boolean()
  @optional_callbacks identity_files_empty?: 1

  @spec read(term(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(state, type, identity), do: implementation(state).read(state, type, identity)

  @spec write(term(), atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(state, type, identity, revision, candidate),
    do: implementation(state).write(state, type, identity, revision, candidate)

  @spec put_new(term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(state, type, identity, candidate),
    do: implementation(state).put_new(state, type, identity, candidate)

  @spec replace(term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(state, type, identity, candidate),
    do: implementation(state).replace(state, type, identity, candidate)

  @spec remove_exact(term(), atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(state, type, identity, expected),
    do: implementation(state).remove_exact(state, type, identity, expected)

  defp implementation(%{backend: backend}) when is_atom(backend), do: backend
  defp implementation(_state), do: BnestApp.DataRepository.Store
end
