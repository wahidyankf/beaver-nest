defmodule BnestApp.Backup.Adapters.FileArtifactStore do
  @moduledoc """
  `BnestApp.Backup.Ports.ArtifactStore` over the local filesystem: destination directories
  and markers, promoted artifacts and their JSON receipts.
  """

  @behaviour BnestApp.Backup.Ports.ArtifactStore

  alias BnestApp.Backup.Domain.Location

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def symlink_in_path?(_store, path) do
    path
    |> Path.split()
    |> Enum.scan(fn segment, prefix -> Path.join(prefix, segment) end)
    |> Enum.any?(fn candidate ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(candidate))
    end)
  end

  @impl true
  def prepare_directory(_store, directory) do
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    :ok
  rescue
    File.Error -> {:error, :unavailable}
  end

  @impl true
  def read_marker(_store, directory) do
    with {:ok, bytes} <- File.read(Location.marker_path(directory)),
         {:ok, marker} <- Jason.decode(bytes) do
      {:ok, marker}
    else
      {:error, :enoent} -> {:error, :absent}
      _unreadable -> {:error, :invalid_marker}
    end
  end

  @impl true
  def write_marker(_store, directory, marker) do
    path = Location.marker_path(directory)
    temporary = path <> ".partial-" <> random_id()
    File.write!(temporary, Jason.encode!(marker))
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
  end

  @impl true
  def remove(_store, path) do
    _result = File.rm(path)
    :ok
  end

  @impl true
  def restrict(_store, path), do: File.chmod!(path, 0o600)

  @impl true
  def sync(_store, path), do: sync_file!(path)

  @impl true
  def promote(_store, from, to), do: File.rename!(from, to)

  @impl true
  def digest(_store, path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary, :raw])

    try do
      file
      |> hash_chunks(:crypto.hash_init(:sha256))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    after
      :ok = :file.close(file)
    end
  end

  @impl true
  def size(_store, path), do: File.stat!(path).size

  @impl true
  def regular?(_store, path), do: File.regular?(path)

  # Written beside its path, made private and flushed before the rename, so the receipt
  # appears whole or not at all.
  @impl true
  def write_receipt(_store, path, receipt) do
    temporary = path <> ".partial"
    File.write!(temporary, Jason.encode!(receipt))
    File.chmod!(temporary, 0o600)
    sync_file!(temporary)
    File.rename!(temporary, path)
  end

  @impl true
  def receipts(_store, directory) do
    directory
    |> Path.join("*.receipt.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      with {:ok, bytes} <- File.read(path),
           {:ok, receipt} <- Jason.decode(bytes) do
        [receipt]
      else
        _unreadable -> []
      end
    end)
  end

  defp sync_file!(path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary])
    :ok = :file.sync(file)
    :ok = :file.close(file)
  end

  defp hash_chunks(file, hash) do
    case :file.read(file, 64 * 1024) do
      {:ok, bytes} -> hash_chunks(file, :crypto.hash_update(hash, bytes))
      :eof -> hash
      {:error, reason} -> raise "backup digest failed: #{inspect(reason)}"
    end
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
