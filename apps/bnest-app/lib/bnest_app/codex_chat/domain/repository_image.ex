defmodule BnestApp.CodexChat.Domain.RepositoryImage do
  @moduledoc """
  The rules for a repository image a Codex reply may show: which paths are references to read,
  which bytes are a raster image, and how large a file may be (ADR 002, Decision 2). Pure: no
  file or process access.

  `reference/1` is rule 1 and `signature/1` is rule 4. The containment and size checks that
  need the file system (rules 2 and 3) live in the file adapter.
  """

  @max_bytes 5 * 1024 * 1024
  @raster_extensions ~w(.png .jpg .jpeg .gif .webp)

  # Directories that hold runtime data, tools, build output or test output. A reference
  # through any of them is refused, wherever it appears in the path, in any letter case:
  # macOS and Windows treat `Data` and `data` as one folder.
  @denied_segments ~w(data node_modules local-tmp generated-reports worktrees _build deps
                      test-results playwright-report blob-report)

  @doc """
  Accepts a repository-relative raster path and returns it normalized: one leading `./` is
  dropped and nothing else changes. A path is refused when it is empty, absolute, contains a
  backslash, a NUL byte, a colon (any scheme) or a percent sign (an escape left after the
  one decoding, which means double encoding), when a segment is empty, `.`, `..` or starts
  with a dot, when a segment is a denied directory, or when the extension is not a raster
  one. Denied directory names and the extension are compared without case.
  """
  @spec reference(String.t()) :: {:ok, String.t()} | :error
  def reference(path), do: path |> drop_leading_dot_slash() |> validate()

  @doc """
  Returns the media type of bytes that start with a raster signature: PNG, JPEG, GIF87a or
  GIF89a, or a WebP container (`RIFF` size `WEBP`). Anything else, including SVG, HTML and
  text, is refused, whatever its file name says.
  """
  @spec signature(binary()) :: {:ok, String.t()} | :error
  def signature(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {:ok, "image/png"}
  def signature(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg"}
  def signature(<<"GIF87a", _rest::binary>>), do: {:ok, "image/gif"}
  def signature(<<"GIF89a", _rest::binary>>), do: {:ok, "image/gif"}
  def signature(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: {:ok, "image/webp"}
  def signature(_bytes), do: :error

  @doc "The largest repository image served, in bytes (5 MiB)."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  defp drop_leading_dot_slash("./" <> path), do: path
  defp drop_leading_dot_slash(path), do: path

  defp validate(path) do
    segments = String.split(path, "/")

    if clean_text?(path) and Enum.all?(segments, &valid_segment?/1) and
         raster_extension?(List.last(segments)) do
      {:ok, path}
    else
      :error
    end
  end

  defp clean_text?(path), do: not String.contains?(path, ["\\", "\0", ":", "%"])

  defp valid_segment?(""), do: false
  defp valid_segment?("." <> _name), do: false
  defp valid_segment?(segment), do: String.downcase(segment) not in @denied_segments

  defp raster_extension?(name), do: String.downcase(Path.extname(name)) in @raster_extensions
end
