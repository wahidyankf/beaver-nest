defmodule BnestApp.Storage.Ports.RecordBackend do
  @moduledoc """
  A store of schema-valid records, keyed by record type and identity.

  Every callback takes the backend's own state first. The state is a map whose `:backend`
  key names the implementing module, so callers dispatch through the functions below without
  knowing which backend is active.

  Semantics every implementation keeps:

    * `read/3` returns `{:error, :missing}` for an absent record.
    * `put_new/4` refuses an existing record with `{:error, :exists}`.
    * `replace/4` refuses an absent record with `{:error, :missing}`.
    * `write/5` is optimistic: it succeeds only when the stored revision equals the expected
      one (`nil` for an absent record), stores the candidate with the next revision (`0` for a
      new record), and otherwise returns `{:error, :stale}`.
    * `remove_exact/4` removes the record only when it still equals the expected one, returns
      `{:error, :changed}` when it does not, and `:ok` when it is already absent.
  """

  @type state :: %{required(:backend) => module(), optional(atom()) => term()}

  @callback read(state(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  @callback write(state(), atom(), term(), non_neg_integer() | nil, map()) ::
              {:ok, map()} | {:error, atom()}
  @callback put_new(state(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback replace(state(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  @callback remove_exact(state(), atom(), term(), map()) :: :ok | {:error, atom()}
  @callback identity_files_empty?(state()) :: boolean()
  @optional_callbacks identity_files_empty?: 1

  @spec read(state(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(state, type, identity), do: state.backend.read(state, type, identity)

  @spec write(state(), atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(state, type, identity, revision, candidate),
    do: state.backend.write(state, type, identity, revision, candidate)

  @spec put_new(state(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(state, type, identity, candidate),
    do: state.backend.put_new(state, type, identity, candidate)

  @spec replace(state(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(state, type, identity, candidate),
    do: state.backend.replace(state, type, identity, candidate)

  @spec remove_exact(state(), atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(state, type, identity, expected),
    do: state.backend.remove_exact(state, type, identity, expected)

  @spec identity_files_empty?(state()) :: boolean()
  def identity_files_empty?(state), do: state.backend.identity_files_empty?(state)
end
