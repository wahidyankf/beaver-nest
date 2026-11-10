defmodule BnestApp.CodexChat.Adapters.RepositoryImageFiles do
  @moduledoc """
  The `BnestApp.CodexChat.Ports.RepositoryImages` over the Codex working directory (ADR 002,
  Decision 2, rules 2 and 3).

  The directory is read from `config :bnest_app, :codex` on every call, as the chat runner reads
  it, never from the request. Every component below that root is checked with `File.lstat/1`,
  which does not follow links: each parent must be a directory and the file itself a regular
  file, so a symbolic link anywhere below the root is refused. The root is trusted, because it is
  the configured checkout, and it is not checked. The file's size is checked against its `lstat`
  size, and its bytes are then read at most `max_bytes + 1` long, so a file that grows after the
  check still cannot exceed the limit.

  Every refusal is `{:error, :not_found}`, so a caller cannot tell a missing file from a refused one.
  """

  @behaviour BnestApp.CodexChat.Ports.RepositoryImages

  @impl true
  def read(path, max_bytes) when is_binary(path) and is_integer(max_bytes) and max_bytes > 0 do
    segments = String.split(path, "/")

    with true <- Enum.all?(segments, &plain_segment?/1),
         {:ok, file} <- regular_file(working_directory(), segments, max_bytes),
         {:ok, bytes} <- read_bounded(file, max_bytes) do
      {:ok, bytes}
    else
      _refused -> {:error, :not_found}
    end
  end

  # The domain already refuses these segments; the adapter refuses them too, because `lstat` of
  # `..` names the parent directory, which would pass the directory check.
  defp plain_segment?(segment) do
    segment not in ["", ".", ".."] and not String.contains?(segment, ["\\", "\0"])
  end

  defp working_directory do
    :bnest_app |> Application.fetch_env!(:codex) |> Keyword.fetch!(:working_directory)
  end

  defp regular_file(root, segments, max_bytes) do
    {parents, [leaf]} = Enum.split(segments, -1)

    with {:ok, directory} <- directory_below(root, parents),
         file = Path.join(directory, leaf),
         {:ok, %File.Stat{type: :regular, size: size}} when size <= max_bytes <-
           File.lstat(file) do
      {:ok, file}
    else
      _refused -> :error
    end
  end

  defp directory_below(root, parents) do
    Enum.reduce_while(parents, {:ok, root}, fn segment, {:ok, directory} ->
      candidate = Path.join(directory, segment)

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :directory}} -> {:cont, {:ok, candidate}}
        _not_a_directory -> {:halt, :error}
      end
    end)
  end

  # One open and one bounded read, so the bytes checked are the bytes served. An empty file reads
  # as `:eof` and is returned empty; the signature check refuses it later.
  defp read_bounded(file, max_bytes) do
    case File.open(file, [:read, :binary], &IO.binread(&1, max_bytes + 1)) do
      {:ok, :eof} -> {:ok, ""}
      {:ok, bytes} when is_binary(bytes) and byte_size(bytes) <= max_bytes -> {:ok, bytes}
      _refused -> :error
    end
  end
end
