defmodule BnestApp.Identity.FileStore do
  @moduledoc false

  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records

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

  def read_account(Records, user_id), do: Records.read(:account, user_id)

  def read_account(%{backend: _} = store, user_id),
    do: RecordBackend.read(store, :account, user_id)

  def read_username(Records, username),
    do: Records.read(:username_index, username)

  def read_username(%{backend: _} = store, username),
    do: RecordBackend.read(store, :username_index, username)

  def read_session(Records, digest), do: Records.read(:session, digest)
  def read_session(%{backend: _} = store, digest), do: RecordBackend.read(store, :session, digest)
  def read_bootstrap(Records), do: Records.read(:bootstrap, nil)
  def read_bootstrap(%{backend: _} = store), do: RecordBackend.read(store, :bootstrap, nil)

  def put_account(Records, account),
    do: Records.put_new(:account, account["userId"], account)

  def put_account(%{backend: _} = store, account),
    do: RecordBackend.put_new(store, :account, account["userId"], account)

  def replace_account(Records, account),
    do: Records.replace(:account, account["userId"], account)

  def replace_account(%{backend: _} = store, account),
    do: RecordBackend.replace(store, :account, account["userId"], account)

  def put_username(Records, index),
    do: Records.put_new(:username_index, index["normalizedUsername"], index)

  def put_username(%{backend: _} = store, index),
    do: RecordBackend.put_new(store, :username_index, index["normalizedUsername"], index)

  def put_session(Records, session),
    do: Records.put_new(:session, session["tokenDigest"], session)

  def put_session(%{backend: _} = store, session),
    do: RecordBackend.put_new(store, :session, session["tokenDigest"], session)

  def replace_session(Records, session),
    do: Records.replace(:session, session["tokenDigest"], session)

  def replace_session(%{backend: _} = store, session),
    do: RecordBackend.replace(store, :session, session["tokenDigest"], session)

  def put_bootstrap(Records, journal),
    do: Records.put_new(:bootstrap, nil, journal)

  def put_bootstrap(%{backend: _} = store, journal),
    do: RecordBackend.put_new(store, :bootstrap, nil, journal)

  def replace_bootstrap(Records, journal),
    do: Records.replace(:bootstrap, nil, journal)

  def replace_bootstrap(%{backend: _} = store, journal),
    do: RecordBackend.replace(store, :bootstrap, nil, journal)

  def remove_account(Records, account),
    do: Records.remove_exact(:account, account["userId"], account)

  def remove_account(%{backend: _} = store, account),
    do: RecordBackend.remove_exact(store, :account, account["userId"], account)

  def remove_username(Records, index),
    do: Records.remove_exact(:username_index, index["normalizedUsername"], index)

  def remove_username(%{backend: _} = store, index),
    do: RecordBackend.remove_exact(store, :username_index, index["normalizedUsername"], index)

  def remove_bootstrap(Records, journal),
    do: Records.remove_exact(:bootstrap, nil, journal)

  def remove_bootstrap(%{backend: _} = store, journal),
    do: RecordBackend.remove_exact(store, :bootstrap, nil, journal)

  @spec identity_files_empty?(RecordBackend.state() | module()) :: boolean()
  def identity_files_empty?(Records), do: false

  def identity_files_empty?(%{backend: backend} = store),
    do: backend.identity_files_empty?(store)

  defp ascii_lower(value) do
    value
    |> :binary.bin_to_list()
    |> Enum.map(fn char -> if char in ?A..?Z, do: char + 32, else: char end)
    |> :binary.list_to_bin()
  end
end
