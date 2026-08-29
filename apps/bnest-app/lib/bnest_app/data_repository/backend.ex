defmodule BnestApp.DataRepository.Backend do
  @moduledoc false

  @callback read(state :: term(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  @callback write(state :: term(), atom(), term(), non_neg_integer() | nil, map()) ::
              {:ok, map()} | {:error, atom()}
  @callback put_new(state :: term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback replace(state :: term(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback remove_exact(state :: term(), atom(), term(), map()) :: :ok | {:error, atom()}
end
