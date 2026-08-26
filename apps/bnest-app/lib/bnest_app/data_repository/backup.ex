defmodule BnestApp.DataRepository.Backup do
  @moduledoc false

  @id_pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/u

  @spec preserve(map(), {:app, String.t()} | {:user, String.t()}, String.t(), binary()) ::
          {:ok, map()} | {:error, atom()}
  def preserve(store, owner, import_id, bytes) when is_binary(bytes) do
    with {:ok, relative} <- recovery_path(owner, import_id),
         destination <- Path.expand(relative, store.root),
         true <- String.starts_with?(destination, store.root <> "/"),
         :ok <- write_immutable(destination, bytes),
         {:ok, ^bytes} <- File.read(destination) do
      {:ok, %{relative_path: relative, sha256: digest(bytes), byte_size: byte_size(bytes)}}
    else
      false -> {:error, :path_escape}
      {:error, :eexist} -> verify_existing(store, owner, import_id, bytes)
      {:error, reason} when is_atom(reason) -> {:error, normalize_error(reason)}
      _failure -> {:error, :read_back_failed}
    end
  end

  def preserve(_store, _owner, _import_id, _bytes), do: {:error, :invalid_source}

  @spec read(map(), {:app, String.t()} | {:user, String.t()}, String.t(), String.t()) ::
          {:ok, binary()} | {:error, atom()}
  def read(store, owner, import_id, expected_sha256) do
    with {:ok, relative} <- recovery_path(owner, import_id),
         {:ok, bytes} <- File.read(Path.join(store.root, relative)),
         true <- digest(bytes) == expected_sha256 do
      {:ok, bytes}
    else
      false -> {:error, :checksum_mismatch}
      {:error, :enoent} -> {:error, :missing}
      {:error, _reason} -> {:error, :read_failed}
    end
  end

  defp write_immutable(path, bytes) do
    File.mkdir_p!(Path.dirname(path))

    File.open(path, [:write, :binary, :exclusive], fn device ->
      with :ok <- IO.binwrite(device, bytes), do: :file.sync(device)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, :eexist} -> {:error, :eexist}
      _failure -> {:error, :write_failed}
    end
  end

  defp verify_existing(store, owner, import_id, expected) do
    case read(store, owner, import_id, digest(expected)) do
      {:ok, ^expected} ->
        {:ok,
         %{
           relative_path: elem(recovery_path(owner, import_id), 1),
           sha256: digest(expected),
           byte_size: byte_size(expected)
         }}

      {:ok, _other} ->
        {:error, :immutable_collision}

      {:error, :checksum_mismatch} ->
        {:error, :immutable_collision}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recovery_path({:app, "beaver-nest"}, import_id) do
    if id?(import_id),
      do: {:ok, "apps/beaver-nest/legacy/#{import_id}/source.bin"},
      else: {:error, :invalid_id}
  end

  defp recovery_path({:user, user_id}, import_id) do
    if id?(user_id) and id?(import_id),
      do: {:ok, "users/#{user_id}/legacy/#{import_id}/source.bin"},
      else: {:error, :invalid_id}
  end

  defp recovery_path(_owner, _import_id), do: {:error, :invalid_owner}

  defp id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp normalize_error(:write_failed), do: :write_failed
  defp normalize_error(reason), do: reason
end
