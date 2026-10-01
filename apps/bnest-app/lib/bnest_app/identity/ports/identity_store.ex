defmodule BnestApp.Identity.Ports.IdentityStore do
  @moduledoc """
  The store of Identity's records: accounts, the username index, browser sessions, and the
  one-time bootstrap journal.

  Every callback takes the store's handle first. The handle is a map whose `:adapter` key
  names the implementing module, so callers dispatch through the functions below without
  knowing which store is active.

  Semantics every implementation keeps:

    * a read of an absent record returns `{:error, :missing}`;
    * a `put_*` stores a new record and returns `{:ok, record}`, and refuses an existing
      one with `{:error, :exists}`;
    * a `replace_*` changes an existing record and returns `{:ok, record}`, and refuses an
      absent one with `{:error, :missing}`;
    * a `remove_*` removes the record only when it still equals the expected one, returns
      `{:error, :changed}` when it does not, and `:ok` when it is already absent;
    * `empty?/1` is true only when the store holds no account and no username index; a
      store that cannot tell answers `false`;
    * `lock_key/1` is equal for handles over the same records and differs between stores.

  Accounts are keyed by `userId`, username indexes by `normalizedUsername`, and sessions by
  `tokenDigest`. The bootstrap journal is a singleton.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type record :: map()
  @type result :: {:ok, record()} | {:error, atom()}

  @doc "A handle over `record_store`, the record store Storage reports as active."
  @callback new(record_store :: term()) :: handle()

  @callback read_account(handle(), String.t()) :: result()
  @callback read_username(handle(), String.t()) :: result()
  @callback read_session(handle(), String.t()) :: result()
  @callback read_bootstrap(handle()) :: result()

  @callback put_account(handle(), record()) :: result()
  @callback put_username(handle(), record()) :: result()
  @callback put_session(handle(), record()) :: result()
  @callback put_bootstrap(handle(), record()) :: result()

  @callback replace_account(handle(), record()) :: result()
  @callback replace_session(handle(), record()) :: result()
  @callback replace_bootstrap(handle(), record()) :: result()

  @callback remove_account(handle(), record()) :: :ok | {:error, atom()}
  @callback remove_username(handle(), record()) :: :ok | {:error, atom()}
  @callback remove_bootstrap(handle(), record()) :: :ok | {:error, atom()}

  @callback empty?(handle()) :: boolean()
  @callback lock_key(handle()) :: term()

  @spec read_account(handle(), String.t()) :: result()
  def read_account(store, user_id), do: store.adapter.read_account(store, user_id)

  @spec read_username(handle(), String.t()) :: result()
  def read_username(store, username), do: store.adapter.read_username(store, username)

  @spec read_session(handle(), String.t()) :: result()
  def read_session(store, digest), do: store.adapter.read_session(store, digest)

  @spec read_bootstrap(handle()) :: result()
  def read_bootstrap(store), do: store.adapter.read_bootstrap(store)

  @spec put_account(handle(), record()) :: result()
  def put_account(store, account), do: store.adapter.put_account(store, account)

  @spec put_username(handle(), record()) :: result()
  def put_username(store, index), do: store.adapter.put_username(store, index)

  @spec put_session(handle(), record()) :: result()
  def put_session(store, session), do: store.adapter.put_session(store, session)

  @spec put_bootstrap(handle(), record()) :: result()
  def put_bootstrap(store, journal), do: store.adapter.put_bootstrap(store, journal)

  @spec replace_account(handle(), record()) :: result()
  def replace_account(store, account), do: store.adapter.replace_account(store, account)

  @spec replace_session(handle(), record()) :: result()
  def replace_session(store, session), do: store.adapter.replace_session(store, session)

  @spec replace_bootstrap(handle(), record()) :: result()
  def replace_bootstrap(store, journal), do: store.adapter.replace_bootstrap(store, journal)

  @spec remove_account(handle(), record()) :: :ok | {:error, atom()}
  def remove_account(store, account), do: store.adapter.remove_account(store, account)

  @spec remove_username(handle(), record()) :: :ok | {:error, atom()}
  def remove_username(store, index), do: store.adapter.remove_username(store, index)

  @spec remove_bootstrap(handle(), record()) :: :ok | {:error, atom()}
  def remove_bootstrap(store, journal), do: store.adapter.remove_bootstrap(store, journal)

  @spec empty?(handle()) :: boolean()
  def empty?(store), do: store.adapter.empty?(store)

  @spec lock_key(handle()) :: term()
  def lock_key(store), do: store.adapter.lock_key(store)
end
