defmodule BnestApp.Backup.Adapters.GitIgnoreCheck do
  @moduledoc """
  `BnestApp.Backup.Ports.IgnoreCheck` through `git check-ignore`, which applies every
  ignore rule of the repository at `repository_root`.
  """

  @behaviour BnestApp.Backup.Ports.IgnoreCheck

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def ignored?(_check, repository_root, relative_path) do
    case System.cmd("git", ["-C", repository_root, "check-ignore", "-q", relative_path]) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end
end
