defmodule BnestApp.Credo.Checks.UnitHermeticity do
  @moduledoc """
  Bans impure calls in the unit-test layer (`test/unit/**`).

  This is the repository-owned mechanical enforcement of hermetic unit tests
  (contract rule C21, decision D26): a unit test touches no clock, file system,
  network, environment, process, or randomness, so it may not call `File`,
  `System`, `:httpc`, `Req`, `DateTime.utc_now`, or `:rand`. A test that needs
  one of these injects a double (a fake clock, id source, or config value) or
  moves to the integration layer. The check is scoped to `test/unit/**` through
  its `files` parameter; production code and the other test layers keep the
  default Credo checks only.
  """

  use Credo.Check,
    id: "BN9001",
    base_priority: :high,
    category: :warning,
    param_defaults: [files: %{included: ["test/unit/**/*.{ex,exs}"]}],
    explanations: [
      check: """
      Unit tests must stay hermetic: no clock, file system, network,
      environment, process, or randomness. Inject a double (a fake clock, id
      source, or config value passed through the port or the test setup) or
      move the test to the integration layer with its scenario kept bound at
      every level.
      """
    ]

  alias Credo.Code
  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # `File.read!`, `System.get_env`, `Req.get`, and friends: module calls.
  defp traverse(
         {{:., meta, [{:__aliases__, _, [module]}, fun]}, _, _} = ast,
         issues,
         issue_meta
       )
       when module in [:File, :System, :Req] and is_atom(fun) do
    {ast, [issue_for(issue_meta, meta, "#{module}.#{fun}", boundary(module)) | issues]}
  end

  # `DateTime.utc_now` only: the rest of `DateTime` is pure date arithmetic.
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:DateTime]}, :utc_now]}, _, _} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta, "DateTime.utc_now", "the system clock") | issues]}
  end

  # `:httpc.request`, `:rand.uniform`, and friends: Erlang module calls.
  defp traverse({{:., meta, [module, fun]}, _, _} = ast, issues, issue_meta)
       when module in [:httpc, :rand] and is_atom(fun) do
    {ast, [issue_for(issue_meta, meta, ":#{module}.#{fun}", boundary(module)) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp boundary(:File), do: "the file system"
  defp boundary(:System), do: "the operating-system environment"
  defp boundary(:Req), do: "a network client"
  defp boundary(:httpc), do: "a network client"
  defp boundary(:rand), do: "unseeded randomness"

  defp issue_for(issue_meta, meta, trigger, boundary) do
    format_issue(issue_meta,
      message:
        "Unit tests must not reach #{boundary} (#{trigger}); " <>
          "inject a double or move the test to the integration layer.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
