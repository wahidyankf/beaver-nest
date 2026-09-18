defmodule BnestApp.SchemaSourceScan do
  @moduledoc """
  Source-text file listing/reading for `BnestAppWeb.SchemaTest`'s dependency-direction
  proof (Phase 3's REFACTOR item, mirrored again for Phase 5 Item 6). Lives under
  `test/support/` (not `test/unit/`), so calling `Path.wildcard`/`File.read!` here does
  not trip the unit-layer filesystem-access boundary scan (`test/behaviour/verify.exs`)
  -- mirrors `BnestApp.TestBackupDestination`'s own documented convention for the same
  reason. This performs no domain/runtime filesystem access; it only reads this
  project's own committed Elixir source files as text for a static architecture check.
  """

  @app_lib_root Path.expand("../../lib", __DIR__)

  @doc "Wildcards `path_segments` joined onto this app's own `lib/` root."
  @spec wildcard([String.t()]) :: [String.t()]
  def wildcard(path_segments) when is_list(path_segments) do
    [@app_lib_root | path_segments] |> Path.join() |> Path.wildcard()
  end

  @doc "Reads `path_segments` joined onto this app's own `lib/` root as text."
  @spec read_lib_file!([String.t()]) :: String.t()
  def read_lib_file!(path_segments) when is_list(path_segments) do
    [@app_lib_root | path_segments] |> Path.join() |> File.read!()
  end

  @doc "Reads an already-resolved absolute path as text (for paths `wildcard/1` returned)."
  @spec read!(String.t()) :: String.t()
  def read!(path) when is_binary(path), do: File.read!(path)

  @doc "Formats an already-resolved absolute path relative to the current working directory."
  @spec relative_to_cwd(String.t()) :: String.t()
  def relative_to_cwd(path) when is_binary(path), do: Path.relative_to_cwd(path)
end
