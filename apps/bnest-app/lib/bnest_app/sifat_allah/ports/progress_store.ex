defmodule BnestApp.SifatAllah.Ports.ProgressStore do
  @moduledoc """
  The store of each learner's `sifat-allah-progress` record, keyed by the owner's `userId`.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module, so the facade dispatches through the
  functions below without knowing which store is active.

  Semantics every implementation keeps, as Storage's record backends do:

    * `read/2` returns `{:error, :missing}` for an absent record;
    * `write/4` is optimistic: it succeeds only when the stored revision equals the expected
      one (`nil` for an absent record), stores the record with the next revision (`0` for a
      new record), returns the stored record, and otherwise returns `{:error, :stale}`.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type record :: map()

  @doc "A handle over the records the running application serves."
  @callback new() :: handle()

  @callback read(handle(), owner_id :: String.t()) :: {:ok, record()} | {:error, atom()}

  @callback write(
              handle(),
              owner_id :: String.t(),
              expected_revision :: non_neg_integer() | nil,
              record()
            ) :: {:ok, record()} | {:error, atom()}

  @spec read(handle(), String.t()) :: {:ok, record()} | {:error, atom()}
  def read(store, owner_id), do: store.adapter.read(store, owner_id)

  @spec write(handle(), String.t(), non_neg_integer() | nil, record()) ::
          {:ok, record()} | {:error, atom()}
  def write(store, owner_id, expected_revision, record),
    do: store.adapter.write(store, owner_id, expected_revision, record)
end
