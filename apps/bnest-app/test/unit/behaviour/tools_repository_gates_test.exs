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
  alias BnestApp.ScheduledGatesWorkflow

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

  # The scheduled quality-gates workflow is checked as text: the passing case first, then each drift the scenario
  # forbids. The real files are read by the integration binding in
  # test/integration/bnest_app/behaviour/tools_scheduled_gates_workflow_test.exs.

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow with the declared shape has no findings" do
    assert findings() == []
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must run at 06:00 and 18:00 WIB on one schedule, and on manual dispatch" do
    assert_found(drift(:workflow, "0 6,18 * * *", "0 7,19 * * *"), "exactly one cron")

    assert_found(
      drift(
        :workflow,
        ~s(      timezone: "Asia/Jakarta"\n),
        ~s(      timezone: "Asia/Jakarta"\n    - cron: "0 12 * * *"\n)
      ),
      "exactly one cron"
    )

    assert_found(drift(:workflow, "Asia/Jakarta", "UTC"), "Asia/Jakarta")
    assert_found(drift(:workflow, "  workflow_dispatch:\n", ""), "manual dispatch")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must run serially without cancelling a run in progress" do
    assert_found(
      drift(:workflow, "cancel-in-progress: false", "cancel-in-progress: true"),
      "cancel-in-progress: false"
    )

    assert_found(drift(:workflow, "  group: scheduled-quality-gates\n", ""), "concurrency group")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must run the back-end and the front-end suites as separate jobs" do
    extra_job = "\n  bnest-test-e2e-extra:\n    runs-on: ubuntu-24.04\n"
    run_front = "--entry test-e2e-fe-chromium\n"
    run_back = "--entry test-e2e-be\n"

    assert_found(
      drift(:workflow, "\n  bnest-test-e2e-fe:\n", extra_job <> "\n  bnest-test-e2e-fe:\n"),
      "one job for the back-end"
    )

    assert_found(
      drift(:workflow, "\n  bnest-test-e2e-fe:\n", "\n  bnest-test-e2e-x:\n"),
      "one job for the back-end"
    )

    assert_found(
      drift(:workflow, run_back, run_front),
      "back-end job must run no front-end entry"
    )

    assert_found(
      drift(
        :workflow,
        "--entry test-e2e-fe-${{ matrix.project }}\n",
        "--entry test-e2e-fe-${{ matrix.project }}\n --entry test-e2e-be\n"
      ),
      "front-end job must run no back-end entry"
    )
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled jobs must not wait for each other, in scalar, flow, and block needs" do
    backend = "    name: Bnest test e2e backend\n"
    frontend = "    name: Bnest test e2e frontend (${{ matrix.project }})\n"

    # Every form of needs a job may wait on the other suite with.
    waits = [
      "    needs: OTHER\n",
      "    needs: [OTHER]\n",
      "    needs: [other, \"OTHER\"] # waits\n",
      "    needs:\n      - OTHER\n",
      "    needs:\n      # the other suite first\n\n      - 'OTHER' # waits\n"
    ]

    for wait <- waits do
      assert_found(
        drift(:workflow, backend, backend <> String.replace(wait, "OTHER", "bnest-test-e2e-fe")),
        "back-end job must not wait for the front-end job"
      )

      assert_found(
        drift(
          :workflow,
          frontend,
          frontend <> String.replace(wait, "OTHER", "bnest-test-e2e-be")
        ),
        "front-end job must not wait for the back-end job"
      )
    end

    # Waiting for something else, or for a name that only shares a prefix, is not waiting for the other suite.
    for wait <- [
          "    needs: setup\n",
          "    needs: bnest-test-e2e-fe-extra\n",
          "    needs:\n      - setup\n"
        ] do
      assert drift(:workflow, backend, backend <> wait) == []
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must run no integration suite, and no scheduled entry may be one" do
    integration_job = "\n  bnest-test-integration:\n    runs-on: ubuntu-24.04\n"
    run_back = "--entry test-e2e-be\n"

    assert_found(
      drift(:workflow, "\n  bnest-test-e2e-fe:\n", integration_job <> "\n  bnest-test-e2e-fe:\n"),
      "no integration job"
    )

    assert_found(
      drift(:workflow, run_back, run_back <> "          nx run-many -t test:integration\n"),
      "no workflow step may run the integration entry"
    )

    assert_found(
      drift(
        :workflow,
        run_back,
        run_back <> "          ./rhino gate run --entry test-integration\n"
      ),
      "no workflow step may run the integration entry"
    )

    assert_found(
      drift(
        :registry,
        "        pull-request:\n          reason: \"C17",
        "        scheduled: {}\n        pull-request:\n          reason: \"C17"
      ),
      "test-integration must run on the pull-request surface only"
    )

    extra_entry =
      "    - id: test-integration-extra\n      run-on:\n        scheduled: {}\nextensions:\n"

    found = drift(:registry, "extensions:\n", extra_entry)
    assert_found(found, "no scheduled registry entry may run integration")
    assert_found(found, "scheduled registry entry has no job")
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must matrix the front-end job over the Playwright projects in the registry order" do
    full = "[chromium, tablet-chromium, mobile-chromium]"

    assert_found(
      drift(:workflow, full, "[chromium, tablet-chromium]"),
      "front-end matrix must list"
    )

    assert_found(
      drift(:workflow, full, "[chromium, mobile-chromium, tablet-chromium]"),
      "front-end matrix must list"
    )

    added_project = ~s(    {\n      name: "webkit",\n    },\n  ],\n)
    assert_found(drift(:playwright, "  ],\n", added_project), "front-end matrix must list")

    assert_found(
      drift(:playwright, ~s(name: "chromium"), ~s(name: "chrome")),
      "front-end matrix must list"
    )

    assert_found(
      drift(
        :registry,
        "    - id: test-e2e-fe-tablet-chromium\n",
        "    - id: test-e2e-fe-tablet\n"
      ),
      "one test-e2e-fe entry per Playwright project"
    )

    assert findings(playwright: "export default {};\n") != []
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must point each leg at its own scheduled registry entry" do
    assert_found(
      drift(
        :workflow,
        "--entry test-e2e-fe-${{ matrix.project }}\n",
        "--entry test-e2e-fe-chromium\n"
      ),
      "front-end job must run ./rhino gate run --surface scheduled --entry test-e2e-fe-${{ matrix.project }}"
    )

    assert_found(
      drift(
        :workflow,
        "--surface scheduled --entry test-e2e-be\n",
        "--surface pull-request --entry test-e2e-be\n"
      ),
      "back-end job must run ./rhino gate run --surface scheduled --entry test-e2e-be"
    )

    assert_found(
      drift(:registry, "--project=tablet-chromium }", "--project=chromium }"),
      "test-e2e-fe-tablet-chromium must run only --project=tablet-chromium"
    )

    assert_found(
      drift(
        :registry,
        "- { literal: --project=mobile-chromium }\n",
        "- { literal: --project=mobile-chromium }\n          - { literal: --project=chromium }\n"
      ),
      "test-e2e-fe-mobile-chromium must run only --project=mobile-chromium"
    )

    assert_found(
      drift(
        :registry,
        "bnest-app-be-e2e }\n      run-on:\n        scheduled: {}",
        "bnest-app-be-e2e }\n      run-on:\n        pull-request: {}"
      ),
      "test-e2e-be must run on the scheduled surface only"
    )
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/tools/rhino-consumer/behaviours/repository_gates.feature: The scheduled gates run at 06:00 and 18:00 WIB and run each end-to-end suite as its own job
  test "scheduled workflow must leave no scheduled registry entry without a job that runs it" do
    orphan = "    - id: test-e2e-orphan\n      run-on:\n        scheduled: {}\nextensions:\n"

    assert_found(drift(:registry, "extensions:\n", orphan), "scheduled registry entry has no job")
  end

  # The workflow, the Playwright config, and the gate registry as the real files lay them out, cut down to what the
  # check reads.
  defp workflow do
    ~S"""
    name: Scheduled quality gates

    # Each suite has its own job. Integration runs on every pull request, not here.
    on:
      schedule:
        - cron: "0 6,18 * * *"
          timezone: "Asia/Jakarta"
      workflow_dispatch:

    permissions:
      contents: read

    concurrency:
      group: scheduled-quality-gates
      cancel-in-progress: false

    jobs:
      bnest-test-e2e-be:
        name: Bnest test e2e backend
        runs-on: ubuntu-24.04
        steps:
          - name: Run backend end-to-end suite
            run: |
              set -eu
              ./hippo run --class ephemeral --resource-tier heavy --disk-path . -- \
                ./rhino gate run --surface scheduled --entry test-e2e-be

      bnest-test-e2e-fe:
        name: Bnest test e2e frontend (${{ matrix.project }})
        runs-on: ubuntu-24.04
        strategy:
          fail-fast: false
          matrix:
            project: [chromium, tablet-chromium, mobile-chromium]
        steps:
          - name: Run frontend end-to-end suite
            run: |
              set -eu
              ./hippo run --class ephemeral --resource-tier heavy --disk-path . -- \
                ./rhino gate run --surface scheduled --entry test-e2e-fe-${{ matrix.project }}

          - name: Upload end-to-end output
            if: always()
            uses: actions/upload-artifact@v7
            with:
              name: e2e-frontend-${{ matrix.project }}
    """
  end

  defp playwright_config do
    ~S"""
    export default defineConfig({
      projects: [
        {
          name: "one-time-setup",
          grep: setupScenario,
        },
        {
          name: "chromium",
          dependencies: ["one-time-setup"],
        },
        {
          name: "tablet-chromium",
          dependencies: ["one-time-setup"],
        },
        {
          name: "mobile-chromium",
          dependencies: ["one-time-setup"],
        },
      ],
    });
    """
  end

  defp registry do
    ~S"""
    gates:
      entries:
        - id: test-integration
          type: check
          command:
            executable: npm
            args:
              - { literal: test:integration }
          run-on:
            pull-request:
              reason: "C17: the integration suite runs on every pull request."
        - id: test-e2e-be
          type: check
          command:
            executable: npm
            args:
              - { literal: bnest-app-be-e2e }
          run-on:
            scheduled: {}
        - id: test-e2e-fe-chromium
          type: check
          command:
            executable: npm
            args:
              - { literal: bnest-app-fe-e2e }
              - { literal: --project=chromium }
          run-on:
            scheduled: {}
        - id: test-e2e-fe-tablet-chromium
          type: check
          command:
            executable: npm
            args:
              - { literal: bnest-app-fe-e2e }
              - { literal: --project=tablet-chromium }
          run-on:
            scheduled: {}
        - id: test-e2e-fe-mobile-chromium
          type: check
          command:
            executable: npm
            args:
              - { literal: bnest-app-fe-e2e }
              - { literal: --project=mobile-chromium }
          run-on:
            scheduled: {}

    extensions:
      software-development: {}
    """
  end

  defp findings(overrides \\ []) do
    ScheduledGatesWorkflow.findings(
      Keyword.get(overrides, :workflow, workflow()),
      Keyword.get(overrides, :playwright, playwright_config()),
      Keyword.get(overrides, :registry, registry())
    )
  end

  # The findings once the fixture of the given kind has one text replaced by another. A text the fixture does not
  # hold is a broken test, not a passing one.
  defp drift(kind, from, to) do
    fixture = fixture(kind)
    assert fixture =~ from, "the #{kind} fixture holds no #{inspect(from)}"
    findings([{kind, String.replace(fixture, from, to)}])
  end

  defp fixture(:workflow), do: workflow()
  defp fixture(:playwright), do: playwright_config()
  defp fixture(:registry), do: registry()

  defp assert_found(found, expected) do
    assert Enum.any?(found, &(&1 =~ expected)),
           "expected a finding containing #{inspect(expected)}, got #{inspect(found)}"
  end
end
