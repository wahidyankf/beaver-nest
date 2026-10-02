defmodule BnestApp.Backup.Ports.IgnoreCheck do
  @moduledoc """
  Whether a repository ignores one of its paths, so the default destination inside it is
  never committed. `ignored?/3` takes the check's handle first (a map whose `:adapter` key
  names the implementing module) and holds only when the repository's ignore rules match
  `relative_path`.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}

  @callback new() :: handle()
  @callback ignored?(handle(), repository_root :: String.t(), relative_path :: String.t()) ::
              boolean()

  @spec ignored?(handle(), String.t(), String.t()) :: boolean()
  def ignored?(check, repository_root, relative_path),
    do: check.adapter.ignored?(check, repository_root, relative_path)
end
