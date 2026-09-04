defmodule BnestApp.Identity.FileStore do
  @moduledoc false

  alias BnestApp.DataRepository
  alias BnestApp.DataRepository.Backend
  alias BnestApp.DataRepository.Store

  @username_pattern ~r/\A[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?\z/u

  @spec normalize_username(term()) ::
          {:ok, {String.t(), String.t()}} | {:error, :invalid_username}
  def normalize_username(username) when is_binary(username) do
    display = String.trim(username)
    normalized = ascii_lower(display)

    if String.valid?(display) and String.length(display) in 1..32 and
         Regex.match?(@username_pattern, normalized) do
      {:ok, {display, normalized}}
    else
      {:error, :invalid_username}
    end
  end

  def normalize_username(_username), do: {:error, :invalid_username}

  def read_account(DataRepository, user_id), do: DataRepository.read(:account, user_id)
  def read_account(%{backend: _} = store, user_id), do: Backend.read(store, :account, user_id)
  def read_account(store, user_id), do: Store.read(store, :account, user_id)

  def read_username(DataRepository, username),
    do: DataRepository.read(:username_index, username)

  def read_username(%{backend: _} = store, username),
    do: Backend.read(store, :username_index, username)

  def read_username(store, username), do: Store.read(store, :username_index, username)
  def read_session(DataRepository, digest), do: DataRepository.read(:session, digest)
  def read_session(%{backend: _} = store, digest), do: Backend.read(store, :session, digest)
  def read_session(store, digest), do: Store.read(store, :session, digest)
  def read_bootstrap(DataRepository), do: DataRepository.read(:bootstrap, nil)
  def read_bootstrap(%{backend: _} = store), do: Backend.read(store, :bootstrap, nil)
  def read_bootstrap(store), do: Store.read(store, :bootstrap, nil)

  def put_account(DataRepository, account),
    do: DataRepository.put_new(:account, account["userId"], account)

  def put_account(%{backend: _} = store, account),
    do: Backend.put_new(store, :account, account["userId"], account)

  def put_account(store, account),
    do: Store.put_new(store, :account, account["userId"], account)

  def put_username(DataRepository, index),
    do: DataRepository.put_new(:username_index, index["normalizedUsername"], index)

  def put_username(%{backend: _} = store, index),
    do: Backend.put_new(store, :username_index, index["normalizedUsername"], index)

  def put_username(store, index),
    do: Store.put_new(store, :username_index, index["normalizedUsername"], index)

  def put_session(DataRepository, session),
    do: DataRepository.put_new(:session, session["tokenDigest"], session)

  def put_session(%{backend: _} = store, session),
    do: Backend.put_new(store, :session, session["tokenDigest"], session)

  def put_session(store, session),
    do: Store.put_new(store, :session, session["tokenDigest"], session)

  def replace_session(DataRepository, session),
    do: DataRepository.replace(:session, session["tokenDigest"], session)

  def replace_session(%{backend: _} = store, session),
    do: Backend.replace(store, :session, session["tokenDigest"], session)

  def replace_session(store, session),
    do: Store.replace(store, :session, session["tokenDigest"], session)

  def put_bootstrap(DataRepository, journal),
    do: DataRepository.put_new(:bootstrap, nil, journal)

  def put_bootstrap(%{backend: _} = store, journal),
    do: Backend.put_new(store, :bootstrap, nil, journal)

  def put_bootstrap(store, journal), do: Store.put_new(store, :bootstrap, nil, journal)

  def replace_bootstrap(DataRepository, journal),
    do: DataRepository.replace(:bootstrap, nil, journal)

  def replace_bootstrap(%{backend: _} = store, journal),
    do: Backend.replace(store, :bootstrap, nil, journal)

  def replace_bootstrap(store, journal), do: Store.replace(store, :bootstrap, nil, journal)

  def remove_account(DataRepository, account),
    do: DataRepository.remove_exact(:account, account["userId"], account)

  def remove_account(%{backend: _} = store, account),
    do: Backend.remove_exact(store, :account, account["userId"], account)

  def remove_account(store, account),
    do: Store.remove_exact(store, :account, account["userId"], account)

  def remove_username(DataRepository, index),
    do: DataRepository.remove_exact(:username_index, index["normalizedUsername"], index)

  def remove_username(%{backend: _} = store, index),
    do: Backend.remove_exact(store, :username_index, index["normalizedUsername"], index)

  def remove_username(store, index),
    do: Store.remove_exact(store, :username_index, index["normalizedUsername"], index)

  def remove_bootstrap(DataRepository, journal),
    do: DataRepository.remove_exact(:bootstrap, nil, journal)

  def remove_bootstrap(%{backend: _} = store, journal),
    do: Backend.remove_exact(store, :bootstrap, nil, journal)

  def remove_bootstrap(store, journal), do: Store.remove_exact(store, :bootstrap, nil, journal)

  @spec identity_files_empty?(Store.t() | module()) :: boolean()
  def identity_files_empty?(DataRepository), do: false

  def identity_files_empty?(%{backend: backend} = store),
    do: backend.identity_files_empty?(store)

  def identity_files_empty?(store) do
    no_json?(Path.join(store.root, "system/accounts")) and
      no_json?(Path.join(store.root, "system/usernames"))
  end

  defp no_json?(directory), do: Path.wildcard(Path.join(directory, "*.json")) == []

  defp ascii_lower(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.map(fn char -> if char in ?A..?Z, do: char + 32, else: char end)
    |> :binary.list_to_bin()
  end
end
