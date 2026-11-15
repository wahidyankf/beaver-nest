defmodule BnestApp.CodexChat.Domain.GeneratedImage do
  @moduledoc """
  The rules for a generated image a Codex reply may show: which thread directory and file
  names are references to read (ADR 007, Decision 2). Pure: no file or process access.

  `reference/2` is the strict-name rule. The size and signature checks reuse
  `BnestApp.CodexChat.Domain.RepositoryImage` (`max_bytes/0` and `signature/1`), and the
  containment rule lives in the file adapter, mirroring the repository image shape.
  """

  @max_bytes 5 * 1024 * 1024
  @thread_pattern ~r/\A[0-9A-Fa-f-]{1,64}\z/
  @file_pattern ~r/\Aexec-[0-9A-Za-z-]{1,64}\.(png|jpg|jpeg|gif|webp)\z/i

  @doc """
  Accepts a Codex thread id and a saved generated-image file name, and returns the
  two-segment reference the route reads. A reference is refused when the thread is not
  1 to 64 hexadecimal or hyphen characters containing a hyphen, or when the file is not
  `exec-` followed by 1 to 64 alphanumeric or hyphen characters and a raster extension.
  """
  @spec reference(String.t(), String.t()) :: {:ok, String.t()} | :error
  def reference(thread, file) when is_binary(thread) and is_binary(file) do
    if valid_thread?(thread) and valid_file?(file) do
      {:ok, thread <> "/" <> file}
    else
      :error
    end
  end

  def reference(_thread, _file), do: :error

  @doc "The largest generated image served, in bytes (5 MiB, shared with repository images)."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  defp valid_thread?(thread) do
    String.contains?(thread, "-") and Regex.match?(@thread_pattern, thread) and
      thread not in [".", ".."] and not String.starts_with?(thread, ".") and
      not String.contains?(thread, ["\\", "\0", ":", "%", "/"])
  end

  defp valid_file?(file) do
    Regex.match?(@file_pattern, file) and not String.contains?(file, ["\\", "\0", ":", "%", "/"])
  end
end
