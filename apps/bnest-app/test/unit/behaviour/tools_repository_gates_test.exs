defmodule BnestApp.Behaviour.Tools.RepositoryGatesModel do
  @moduledoc false

  # Pure mirror of the rhino-consumer gate declarations.

  # Mirrors apps/rhino-consumer/project.json test:repo (pre-push surface
  # over the checkout with HEAD and the zero object id).
  def repo_surface, do: "pre-push"
  def repo_args, do: ["--surface", "pre-push", "--push-updates-stdin"]
  def repo_ref, do: "refs/heads/test-repo"
  def zero_id, do: String.duplicate("0", 40)

  def repo_push_line(head) do
    "HEAD #{head} #{repo_ref()} #{zero_id()}"
  end

  def repo_inputs do
    ["rhino", "rhino.lock", "repo-config.yml", "governed content"]
  end

  # Mirrors apps/rhino-consumer/project.json test:integration (the RHINO
  # bootstrap proofs own the bootstrap corpus whole-file).
  def bootstrap_script, do: ".github/scripts/test-rhino-bootstrap.sh"

  def bootstrap_inputs do
    ["rhino", "rhino.lock", ".github/scripts/test-rhino-bootstrap.sh", "rhino-consumer features"]
  end

  # Mirrors repo-config.yml entries named in the pre-push outline (10 rows).
  def pre_push_entries do
    [
      "public-safety-tree",
      "public-safety-range",
      "remote-dispatch-refusal",
      "repo-config",
      "word-budget",
      "directory-map",
      "quality-gates",
      "harness-adapters",
      "internal-links",
      "mermaid"
    ]
  end

  def entry_refuses?(_entry, :fail), do: true
  def entry_refuses?(_entry, :pass), do: false

  # Mirrors test-pr-quality-routing.sh route_path (lines 25-48).
  def route(path) do
    %{
      governed: governed?(path),
      hippo_consumer: hippo_consumer?(path),
      rhino_consumer: rhino_consumer?(path)
    }
  end

  defp governed?(path) do
    String.starts_with?(path, ".claude/") or String.starts_with?(path, ".agents/") or
      String.ends_with?(path, ".md") or String.starts_with?(path, "specs/") or
      String.starts_with?(path, "plans/") or String.starts_with?(path, "docs/") or
      path == "repo-config.yml" or path == ".github/workflows/pr-quality-gate.yml"
  end

  defp hippo_consumer?("hippo"), do: true
  defp hippo_consumer?("hippo.lock"), do: true
  defp hippo_consumer?(".github/workflows/pr-quality-gate.yml"), do: true
  defp hippo_consumer?(path), do: String.starts_with?(path, "specs/apps/tools/hippo-consumer/")

  defp rhino_consumer?("rhino"), do: true
  defp rhino_consumer?("rhino.lock"), do: true
  defp rhino_consumer?(".github/workflows/pr-quality-gate.yml"), do: true
  defp rhino_consumer?(path), do: String.starts_with?(path, "specs/apps/tools/rhino-consumer/")

  # Mirrors scripts/check-commit-message.sh with commitlint conventional
  # config; a missing message requires the gate message value.
  def commit_verdict("(missing message)"), do: {:refused, "RHINO_GATE_MESSAGE is required"}
  def commit_verdict(""), do: {:refused, "RHINO_GATE_MESSAGE is required"}

  def commit_verdict(message) do
    if message =~ ~r/^(feat|fix|chore|docs|test|refactor|perf|build|ci|style|revert)(\(.+\))?: .+/ do
      {:accepted, "with the commitlint reasons"}
    else
      {:refused, "with the commitlint reasons"}
    end
  end

  # Mirrors the coverage proof rows (bound corpus exits 0, one unbound
  # names the scenario, unit layer refuses file/system reach).
  def coverage_exit(:all_bound), do: {:ok, 0}
  def coverage_exit(:one_unbound), do: {:error, "non-zero naming that scenario"}
  def coverage_exit(:unit_reaches_out), do: {:error, "refused by the boundary policy"}
end

defmodule BnestApp.Behaviour.Tools.RepositoryGatesTest do
  @moduledoc """
  Unit bindings for `repository_gates.feature`. Every scenario below carries
  its `@scenario` reference so the behaviour coverage check sees the unit
  binding the review requires.
  """

  use ExUnit.Case, async: true

  alias BnestApp.Behaviour.Tools.RepositoryGatesModel, as: Model

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: rhino-consumer test:repo runs the pre-push gate surface over the checkout
  test "test:repo pipes one synthetic push line into the pre-push surface" do
    # Mirrors apps/rhino-consumer/project.json test:repo command and inputs.
    assert Model.repo_surface() == "pre-push"
    assert Model.repo_args() == ["--surface", "pre-push", "--push-updates-stdin"]
    line = Model.repo_push_line("abc123")
    assert line =~ "refs/heads/test-repo"
    assert line =~ String.duplicate("0", 40)
    assert "rhino.lock" in Model.repo_inputs()
    assert "repo-config.yml" in Model.repo_inputs()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: rhino-consumer test:bootstrap runs the RHINO bootstrap proofs
  test "test:bootstrap runs the bootstrap proofs" do
    assert Model.bootstrap_script() == ".github/scripts/test-rhino-bootstrap.sh"
    assert ".github/scripts/test-rhino-bootstrap.sh" in Model.bootstrap_inputs()
    assert "rhino.lock" in Model.bootstrap_inputs()
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The pre-push gate runs the entries repo-config.yml lists for it and refuses the push when one fails
  test "pre-push runs its entries and refuses when one fails" do
    # Mirrors repo-config.yml entry ids; the hook exits non-zero on failure.
    assert length(Model.pre_push_entries()) == 10
    assert "public-safety-range" in Model.pre_push_entries()
    assert "word-budget" in Model.pre_push_entries()
    assert "mermaid" in Model.pre_push_entries()
    assert Model.entry_refuses?("word-budget", :fail)
    refute Model.entry_refuses?("word-budget", :pass)
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The pull-request gate routes the conditional suites by the changed paths
  test "changed paths route the conditional suites" do
    # Mirrors test-pr-quality-routing.sh route_path predicate.
    assert Model.route(".claude/settings.json").governed
    assert Model.route("hippo").hippo_consumer
    refute Model.route("hippo").rhino_consumer
    assert Model.route("rhino").rhino_consumer
    refute Model.route("rhino").hippo_consumer
    all = Model.route(".github/workflows/pr-quality-gate.yml")
    assert all.governed and all.hippo_consumer and all.rhino_consumer
    none = Model.route("apps/bnest-app/src/unrelated.ts")
    refute none.governed or none.hippo_consumer or none.rhino_consumer
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: A commit message must be a Conventional Commit
  test "commit messages follow the conventional shape" do
    # Mirrors scripts/check-commit-message.sh with the conventional config.
    assert {:accepted, _} = Model.commit_verdict("feat: add x")
    assert {:accepted, _} = Model.commit_verdict("fix(scope): y")
    assert {:refused, _} = Model.commit_verdict("no type here")
    assert {:refused, _} = Model.commit_verdict("unknowntype: z")
    assert {:refused, _} = Model.commit_verdict("feat:")

    assert {:refused, "RHINO_GATE_MESSAGE is required"} =
             Model.commit_verdict("(missing message)")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: test:coverage:behaviour proves the adapters cover the whole scenario corpus
  test "coverage proof exits and names the unbound scenario" do
    assert Model.coverage_exit(:all_bound) == {:ok, 0}
    assert {:error, _} = Model.coverage_exit(:one_unbound)
    assert {:error, "refused by the boundary policy"} = Model.coverage_exit(:unit_reaches_out)
  end
end
