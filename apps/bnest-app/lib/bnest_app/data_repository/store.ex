defmodule BnestApp.DataRepository.Store do
  @moduledoc false

  alias BnestApp.DataRepository.Schema

  @id_pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/u
  @username_pattern ~r/\A[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?\z/u
  @sha_pattern ~r/\A[0-9a-f]{64}\z/u

  @type t :: %{root: String.t(), replace: (String.t(), String.t() -> :ok | {:error, term()})}

  @spec new!(String.t(), keyword()) :: t()
  def new!(root, options \\ []) do
    root = Path.expand(root)

    case validate_root(root) do
      :ok -> %{root: root, replace: Keyword.get(options, :replace, &File.rename/2)}
      {:error, reason} -> raise ArgumentError, "invalid runtime root: #{reason}"
    end
  end

  @spec resolve(t(), atom(), term()) :: {:ok, String.t()} | {:error, atom()}
  def resolve(store, type, identity) do
    with {:ok, relative} <- relative_path(type, identity),
         path <- Path.expand(relative, store.root),
         true <- inside?(path, store.root),
         false <- symlink_in_path?(path, store.root) do
      {:ok, path}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :path_escape}
      true -> {:error, :symlink}
    end
  end

  @spec read(t(), atom(), term()) :: {:ok, map()} | {:error, atom()}
  def read(store, type, identity) do
    with {:ok, path} <- resolve(store, type, identity),
         {:ok, bytes} <- File.read(path),
         {:ok, record} <- Jason.decode(bytes),
         {:ok, ^record} <- Schema.validate(record),
         true <- record_matches?(record, type, identity) do
      {:ok, record}
    else
      {:error, :enoent} -> {:error, :missing}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _invalid -> {:error, :invalid_schema}
    end
  end

  @spec write(t(), atom(), term(), non_neg_integer() | nil, map()) ::
          {:ok, map()} | {:error, atom()}
  def write(store, type, identity, expected_revision, candidate) do
    with {:ok, path} <- resolve(store, type, identity) do
      :global.trans({{__MODULE__, path}, self()}, fn ->
        write_locked(store, path, type, identity, expected_revision, candidate)
      end)
    end
  end

  @spec put_new(t(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def put_new(store, type, identity, candidate) do
    case resolve(store, type, identity) do
      {:ok, path} ->
        transact(path, fn -> put_new_locked(store, path, type, identity, candidate) end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec replace(t(), atom(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def replace(store, type, identity, candidate) do
    case resolve(store, type, identity) do
      {:ok, path} ->
        transact(path, fn -> replace_locked(store, path, type, identity, candidate) end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec remove_exact(t(), atom(), term(), map()) :: :ok | {:error, atom()}
  def remove_exact(store, type, identity, expected) do
    case resolve(store, type, identity) do
      {:ok, path} ->
        transact(path, fn -> remove_exact_locked(store, path, type, identity, expected) end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_new_locked(store, path, type, identity, candidate) do
    if File.exists?(path),
      do: {:error, :exists},
      else: write_exact(store, path, type, identity, candidate)
  end

  defp replace_locked(store, path, type, identity, candidate) do
    if File.exists?(path),
      do: write_exact(store, path, type, identity, candidate),
      else: {:error, :missing}
  end

  defp remove_exact_locked(store, path, type, identity, expected) do
    case read(store, type, identity) do
      {:ok, ^expected} -> normalize_remove(File.rm(path))
      {:ok, _other} -> {:error, :changed}
      {:error, :missing} -> :ok
      {:error, _reason} -> {:error, :invalid_schema}
    end
  end

  defp transact(path, operation), do: :global.trans({{__MODULE__, path}, self()}, operation)

  defp write_locked(store, path, type, identity, expected_revision, candidate) do
    existing = existing_record(path)

    with :ok <- revision_matches(existing, expected_revision),
         {:ok, prepared} <- prepare_candidate(candidate, existing, type, identity),
         {:ok, ^prepared} <- Schema.validate(prepared),
         :ok <- atomic_write(store, path, prepared),
         {:ok, ^prepared} <- read(store, type, identity) do
      {:ok, prepared}
    else
      {:error, :stale} -> {:error, :stale}
      {:error, :atomic_replace_failed} -> {:error, :atomic_replace_failed}
      {:error, _reason} -> {:error, :invalid_schema}
      _invalid -> {:error, :invalid_schema}
    end
  end

  defp write_exact(store, path, type, identity, candidate) do
    with {:ok, ^candidate} <- Schema.validate(candidate),
         true <- record_matches?(candidate, type, identity),
         :ok <- atomic_write(store, path, candidate),
         {:ok, ^candidate} <- read(store, type, identity) do
      {:ok, candidate}
    else
      {:error, :atomic_replace_failed} -> {:error, :atomic_replace_failed}
      _invalid -> {:error, :invalid_schema}
    end
  end

  defp prepare_candidate(candidate, existing, type, identity) when is_map(candidate) do
    revision = if existing, do: existing["revision"] + 1, else: 0
    prepared = Map.put(candidate, "revision", revision)

    if record_matches?(prepared, type, identity),
      do: {:ok, prepared},
      else: {:error, :owner_mismatch}
  end

  defp prepare_candidate(_candidate, _existing, _type, _identity),
    do: {:error, :invalid_candidate}

  defp existing_record(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, record} <- Jason.decode(bytes),
         {:ok, ^record} <- Schema.validate(record) do
      record
    else
      {:error, :enoent} -> nil
      _invalid -> :invalid
    end
  end

  defp revision_matches(nil, nil), do: :ok
  defp revision_matches(%{"revision" => revision}, revision), do: :ok
  defp revision_matches(_existing, _expected), do: {:error, :stale}

  defp atomic_write(store, destination, record) do
    File.mkdir_p!(Path.dirname(destination))
    temporary = destination <> ".tmp-" <> random_id()
    bytes = Jason.encode!(record)

    result =
      with :ok <- write_and_sync(temporary, bytes),
           {:ok, ^record} <- read_temporary(temporary),
           :ok <- store.replace.(temporary, destination) do
        :ok
      else
        _failure -> {:error, :atomic_replace_failed}
      end

    if File.exists?(temporary), do: File.rm(temporary)
    result
  end

  defp write_and_sync(path, bytes) do
    File.open(path, [:write, :binary, :exclusive], fn device ->
      with :ok <- IO.binwrite(device, bytes), do: :file.sync(device)
    end)
    |> case do
      {:ok, :ok} -> :ok
      _failure -> {:error, :write_failed}
    end
  end

  defp read_temporary(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, record} <- Jason.decode(bytes),
         {:ok, ^record} <- Schema.validate(record) do
      {:ok, record}
    end
  end

  defp relative_path(:chat, user_id), do: user_path(user_id, "chat/current.json")
  defp relative_path(:sifat_allah, user_id), do: user_path(user_id, "sifat-allah/progress.json")
  defp relative_path(:theme, user_id), do: user_path(user_id, "preferences/theme.json")
  defp relative_path(:account, user_id), do: id_path(user_id, "system/accounts", ".json")
  defp relative_path(:username_index, username), do: username_path(username)
  defp relative_path(:session, digest), do: digest_path(digest, "system/sessions")
  defp relative_path(:manifest, import_id), do: id_path(import_id, "system/manifests", ".json")

  defp relative_path(:browser_import, {user_id, import_id}) do
    with true <- id?(user_id),
         true <- id?(import_id),
         do: {:ok, "users/#{user_id}/imports/#{import_id}.json"},
         else: (_invalid -> {:error, :invalid_id})
  end

  defp relative_path(:bootstrap, nil), do: {:ok, "system/bootstrap.json"}
  defp relative_path(:schema_registry, nil), do: {:ok, "system/schema-registry.json"}
  defp relative_path(_type, _identity), do: {:error, :unsupported_record_type}

  defp user_path(user_id, suffix) do
    if id?(user_id), do: {:ok, "users/#{user_id}/#{suffix}"}, else: {:error, :invalid_id}
  end

  defp id_path(id, directory, suffix) do
    if id?(id), do: {:ok, "#{directory}/#{id}#{suffix}"}, else: {:error, :invalid_id}
  end

  defp username_path(username) do
    if is_binary(username) and Regex.match?(@username_pattern, username),
      do: {:ok, "system/usernames/#{username}.json"},
      else: {:error, :invalid_id}
  end

  defp digest_path(digest, directory) do
    if is_binary(digest) and Regex.match?(@sha_pattern, digest),
      do: {:ok, "#{directory}/#{digest}.json"},
      else: {:error, :invalid_id}
  end

  defp record_matches?(record, :chat, owner),
    do: record["recordType"] == "chat" and record["ownerId"] == owner

  defp record_matches?(record, :sifat_allah, owner),
    do: record["recordType"] == "sifat-allah-progress" and record["ownerId"] == owner

  defp record_matches?(record, :theme, owner),
    do: record["recordType"] == "theme-preference" and record["ownerId"] == owner

  defp record_matches?(record, :account, user_id),
    do: record["recordType"] == "account" and record["userId"] == user_id

  defp record_matches?(record, :username_index, username),
    do:
      record["recordType"] == "username-index" and
        record["normalizedUsername"] == username

  defp record_matches?(record, :session, digest),
    do: record["recordType"] == "browser-session" and record["tokenDigest"] == digest

  defp record_matches?(record, :bootstrap, nil), do: record["recordType"] == "bootstrap"

  defp record_matches?(record, :manifest, import_id),
    do: record["recordType"] == "import-manifest" and record["importId"] == import_id

  defp record_matches?(record, :browser_import, {owner_id, import_id}),
    do:
      record["recordType"] == "browser-import" and record["ownerId"] == owner_id and
        record["importId"] == import_id

  defp record_matches?(record, :schema_registry, nil),
    do: record["recordType"] == "schema-registry"

  defp record_matches?(_record, _type, _identity), do: false

  defp validate_root(root) do
    cond do
      symlink_in_path?(root, root) -> {:error, :symlink}
      not File.dir?(root) -> {:error, :missing}
      test_root?(root) -> validate_test_marker(root)
      String.ends_with?(root, "/data/prod") -> :ok
      true -> {:error, :unsupported_root}
    end
  end

  defp validate_test_marker(root) do
    with {:ok, bytes} <- File.read(Path.join(root, ".bnest-test-run.json")),
         {:ok, record} <- Jason.decode(bytes),
         {:ok, ^record} <- Schema.validate(record),
         true <- record["runId"] == Path.basename(root) do
      :ok
    else
      _invalid -> {:error, :invalid_test_marker}
    end
  end

  defp test_root?(root), do: String.contains?(root, "/data/test/runs/")
  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")
  defp id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)

  defp symlink_in_path?(path, root) do
    relative = Path.relative_to(path, root)

    relative
    |> Path.split()
    |> Enum.reduce_while(root, fn part, current ->
      next = Path.join(current, part)

      case File.lstat(next) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, true}
        _other -> {:cont, next}
      end
    end)
    |> Kernel.==(true)
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

  defp normalize_remove(:ok), do: :ok
  defp normalize_remove({:error, :enoent}), do: :ok
  defp normalize_remove({:error, _reason}), do: {:error, :remove_failed}
end
