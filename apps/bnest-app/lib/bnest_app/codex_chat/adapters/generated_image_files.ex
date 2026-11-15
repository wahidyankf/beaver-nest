defmodule BnestApp.CodexChat.Adapters.GeneratedImageFiles do
  @moduledoc """
  The `BnestApp.CodexChat.Ports.GeneratedImages` over the Codex home's `generated_images`
  directory (ADR 007, Decision 2, rules 2 and 3).

  The directory is read from `config :bnest_app, :codex` on every call, as the chat runner reads
  it, never from the request. The reference is exactly two segments, `<thread>/<file>`; every
  component below the root is checked with `File.lstat/1`, which does not follow links: the
  thread directory must be a directory and the file itself a regular file, so a symbolic link
  anywhere below the root is refused. The root is trusted, because it is the configured Codex
  home, and it is not checked. The file's size is checked against its `lstat` size, and its
  bytes are then read at most `max_bytes + 1` long, so a file that grows after the check still
  cannot exceed the limit.

  Every refusal is `{:error, :not_found}`, so a caller cannot tell a missing file from a refused one.
  """

  @behaviour BnestApp.CodexChat.Ports.GeneratedImages

  @impl true
  def read(path, max_bytes) when is_binary(path) and is_integer(max_bytes) and max_bytes > 0 do
    with [thread, file] <- String.split(path, "/"),
         true <- plain_segment?(thread) and plain_segment?(file),
         {:ok, bytes} <- regular_file(generated_images_root(), thread, file, max_bytes),
         {:ok, bytes} <- read_bounded(bytes, max_bytes) do
      {:ok, bytes}
    else
      _refused -> {:error, :not_found}
    end
  end

  def read(_path, _max_bytes), do: {:error, :not_found}

  # The domain already refuses these segments; the adapter refuses them too, because `lstat` of
  # `..` names the parent directory, which would pass the directory check.
  defp plain_segment?(segment) do
    segment not in ["", ".", ".."] and not String.contains?(segment, ["\\", "\0"])
  end

  defp generated_images_root do
    :bnest_app
    |> Application.fetch_env!(:codex)
    |> Keyword.fetch!(:codex_home)
    |> Path.expand()
    |> Path.join("generated_images")
  end

  defp regular_file(root, thread, file, max_bytes) do
    with {:ok, %File.Stat{type: :directory}} <- File.lstat(Path.join(root, thread)),
         candidate = Path.join([root, thread, file]),
         {:ok, %File.Stat{type: :regular, size: size}} when size <= max_bytes <-
           File.lstat(candidate) do
      {:ok, candidate}
    else
      _refused -> :error
    end
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
