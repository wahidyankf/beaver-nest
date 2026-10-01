defmodule BnestApp.Identity.Adapters.RecordIdentityStore do
  @moduledoc """
  The `BnestApp.Identity.Ports.IdentityStore` over Storage's records. It wraps either the
  routed `BnestApp.Storage.Records` repository or one record backend's state, and keeps the
  record kinds and keys Identity has always used: `:account` by `userId`,
  `:username_index` by `normalizedUsername`, `:session` by `tokenDigest`, and the
  `:bootstrap` singleton.
  """

  @behaviour BnestApp.Identity.Ports.IdentityStore

  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records

  @type t :: %{adapter: module(), records: module() | RecordBackend.state()}

  @impl true
  @spec new(module() | RecordBackend.state()) :: t()
  def new(records), do: %{adapter: __MODULE__, records: records}

  @impl true
  def read_account(store, user_id), do: read(store, :account, user_id)

  @impl true
  def read_username(store, username), do: read(store, :username_index, username)

  @impl true
  def read_session(store, digest), do: read(store, :session, digest)

  @impl true
  def read_bootstrap(store), do: read(store, :bootstrap, nil)

  @impl true
  def put_account(store, account), do: put_new(store, :account, account["userId"], account)

  @impl true
  def put_username(store, index),
    do: put_new(store, :username_index, index["normalizedUsername"], index)

  @impl true
  def put_session(store, session),
    do: put_new(store, :session, session["tokenDigest"], session)

  @impl true
  def put_bootstrap(store, journal), do: put_new(store, :bootstrap, nil, journal)

  @impl true
  def replace_account(store, account),
    do: replace(store, :account, account["userId"], account)

  @impl true
  def replace_session(store, session),
    do: replace(store, :session, session["tokenDigest"], session)

  @impl true
  def replace_bootstrap(store, journal), do: replace(store, :bootstrap, nil, journal)

  @impl true
  def remove_account(store, account),
    do: remove_exact(store, :account, account["userId"], account)

  @impl true
  def remove_username(store, index),
    do: remove_exact(store, :username_index, index["normalizedUsername"], index)

  @impl true
  def remove_bootstrap(store, journal), do: remove_exact(store, :bootstrap, nil, journal)

  # The routed repository cannot enumerate its records, so it never claims to be empty.
  @impl true
  def empty?(%{records: Records}), do: false

  def empty?(%{records: %{backend: backend} = records}),
    do: backend.identity_files_empty?(records)

  @impl true
  def lock_key(%{records: Records}), do: :active_repository
  def lock_key(%{records: %{backend: backend, pid: pid}}), do: {backend, pid}
  def lock_key(%{records: %{root: root}}), do: root

  defp read(%{records: Records}, type, identity), do: Records.read(type, identity)
  defp read(%{records: records}, type, identity), do: RecordBackend.read(records, type, identity)

  defp put_new(%{records: Records}, type, identity, record),
    do: Records.put_new(type, identity, record)

  defp put_new(%{records: records}, type, identity, record),
    do: RecordBackend.put_new(records, type, identity, record)

  defp replace(%{records: Records}, type, identity, record),
    do: Records.replace(type, identity, record)

  defp replace(%{records: records}, type, identity, record),
    do: RecordBackend.replace(records, type, identity, record)

  defp remove_exact(%{records: Records}, type, identity, record),
    do: Records.remove_exact(type, identity, record)

  defp remove_exact(%{records: records}, type, identity, record),
    do: RecordBackend.remove_exact(records, type, identity, record)
end
