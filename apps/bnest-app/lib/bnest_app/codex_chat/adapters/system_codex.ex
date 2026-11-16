defmodule BnestApp.CodexChat.Adapters.SystemCodex do
  @moduledoc """
  Locates the host Codex CLI without the SDK's bundled fallback.

  Package managers also install a `codex` shim inside the project's `node_modules/.bin`, which
  points at the pinned `@openai/codex` bundle whose model catalog predates the gpt-6 family.
  Any PATH lookup that trusts order alone finds that shim first in npm-launched processes, so
  both the chat runner's `codexPathOverride` and model discovery resolve through here: the
  first executable `codex` whose real absolute path (symlinks resolved) holds no
  `node_modules` segment wins, and the lookup returns `nil` when nothing qualifies.
  """

  @doc """
  Returns the first host `codex` executable on the given `PATH` string, or `nil` when none
  qualifies.

  Entries are scanned in order; a candidate must be a regular executable file whose real
  absolute path, with symlinks resolved, contains no `node_modules` segment, so the SDK's
  bundled shim never wins, even behind a link. Empty `PATH` segments are skipped (never
  treated as the working directory), entries starting with `~` do not qualify, and an empty
  `PATH` (or no qualifying entry) returns `nil`.
  """
  @spec resolve(String.t()) :: String.t() | nil
  def resolve(path_env) when is_binary(path_env) do
    path_env
    |> String.split(":")
    |> Enum.find_value(&candidate/1)
  end

  def resolve(_path_env), do: nil

  defp candidate(""), do: nil

  # A literal `~` entry names a directory called `~`, not the home directory, and `Path`
  # would expand it to the home tree; it never qualifies.
  defp candidate("~" <> _), do: nil

  defp candidate(directory) do
    expanded = directory |> Path.join("codex") |> Path.expand()

    with {:ok, real} <- resolve_links(expanded),
         true <- executable_file?(real),
         false <- "node_modules" in Path.split(real) do
      real
    else
      _otherwise -> nil
    end
  end

  # Follows symlink hops to the real path, so a `codex` link outside `node_modules` that
  # points into the SDK bundle is still rejected. Relative targets resolve against the
  # link's directory; an unreadable hop or a hop cycle disqualifies the candidate.
  @max_link_hops 40
  defp resolve_links(path), do: resolve_links(path, @max_link_hops)

  defp resolve_links(path, hops) when hops >= 0 do
    case File.read_link(path) do
      {:ok, target} -> resolve_links(expand_link_target(path, target), hops - 1)
      {:error, :einval} -> {:ok, path}
      {:error, _reason} -> :error
    end
  end

  defp resolve_links(_path, _hops), do: :error

  defp expand_link_target(link, target) do
    if Path.type(target) == :absolute,
      do: Path.expand(target),
      else: link |> Path.dirname() |> Path.join(target) |> Path.expand()
  end

  # The execute bits of the file itself; a shim without them never qualifies.
  defp executable_file?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} ->
        Bitwise.band(mode, 0o111) != 0

      _otherwise ->
        false
    end
  end
end
