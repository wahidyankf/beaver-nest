defmodule ExBdd.HooksTest do
  use ExUnit.Case, async: true

  defmodule MacroForms do
    use ExBdd.Hooks

    before_scenario "@macro", context, name: "before scenario" do
      Map.put(context, :before_scenario, true)
    end

    after_scenario "@macro", context, name: "after scenario" do
      send(context.test_pid, :after_scenario)
    end

    before_step "@macro", context, name: "before step" do
      Map.put(context, :before_step, true)
    end

    after_step "@macro", context do
      send(context.test_pid, :tagged_after_step)
    end

    after_step context, name: "global after step" do
      send(context.test_pid, :global_after_step)
    end

    after_step "@macro", context, name: "named after step" do
      send(context.test_pid, :named_after_step)
    end
  end

  defmodule HaltingHooks do
    def pending(_context), do: :pending
    def skipped(_context), do: {:skipped, "not today"}
    def failed(_context), do: {:error, :unavailable}
    def should_not_run(_context), do: raise("hook should have halted")
  end

  describe "duplicate hook detection" do
    test "raises CompileError when defining duplicate tagged hooks" do
      code = """
      defmodule DuplicateTaggedHooks do
        use ExBdd.Hooks

        before_scenario "@database", context do
          {:ok, context}
        end

        before_scenario "@database", context do
          {:ok, context}
        end
      end
      """

      assert_raise CompileError, ~r/Duplicate hook: before_scenario_database/, fn ->
        Code.compile_string(code)
      end
    end

    test "raises CompileError when defining duplicate global hooks" do
      code = """
      defmodule DuplicateGlobalHooks do
        use ExBdd.Hooks

        before_scenario context do
          {:ok, context}
        end

        before_scenario context do
          {:ok, context}
        end
      end
      """

      assert_raise CompileError, ~r/Duplicate hook: before_scenario_global/, fn ->
        Code.compile_string(code)
      end
    end

    test "allows different tags without error" do
      code = """
      defmodule DifferentTagsHooks do
        use ExBdd.Hooks

        before_scenario "@database", context do
          {:ok, context}
        end

        before_scenario "@admin", context do
          {:ok, context}
        end
      end
      """

      # Should compile without error
      assert [{DifferentTagsHooks, _}] = Code.compile_string(code)
    end

    test "rejects invalid hook names" do
      code = """
      defmodule InvalidNamedHooks do
        use ExBdd.Hooks

        before_scenario context, name: "" do
          context
        end
      end
      """

      assert_raise CompileError, ~r/must be a non-empty string/, fn ->
        Code.compile_string(code)
      end
    end

    test "reports duplicate named hooks by name" do
      code = """
      defmodule DuplicateNamedHooks do
        use ExBdd.Hooks

        before_scenario context, name: "load account" do
          context
        end

        before_scenario context, name: "load account" do
          context
        end
      end
      """

      assert_raise CompileError, ~r/for name "load account"/, fn ->
        Code.compile_string(code)
      end
    end
  end

  describe "hook filtering and execution" do
    test "filter_hooks returns global hooks and hooks matching tags" do
      defmodule FilterTestModule do
        def global_hook(context), do: {:ok, context}
        def database_hook(context), do: {:ok, context}
        def special_hook(context), do: {:ok, context}
      end

      hooks = [
        {:before_scenario, nil, nil, {FilterTestModule, :global_hook}},
        {:before_scenario, "@database", nil, {FilterTestModule, :database_hook}},
        {:before_scenario, "@special", nil, {FilterTestModule, :special_hook}}
      ]

      # With ["database"] tags, should get global + @database hooks
      filtered = ExBdd.Hooks.filter_hooks(hooks, :before_scenario, ["database"])
      assert length(filtered) == 2

      # With ["database", "special"] tags, should get all 3 hooks
      filtered_all = ExBdd.Hooks.filter_hooks(hooks, :before_scenario, ["database", "special"])
      assert length(filtered_all) == 3

      # With [] tags, should only get global hook
      filtered_empty = ExBdd.Hooks.filter_hooks(hooks, :before_scenario, [])
      assert length(filtered_empty) == 1
    end

    test "run_before_hooks executes matching hooks and updates context" do
      defmodule RunTestModule do
        def hook_a(context), do: {:ok, Map.put(context, :hook_a, true)}
        def hook_b(context), do: {:ok, Map.put(context, :hook_b, true)}
      end

      hooks = [
        {:before_scenario, nil, nil, {RunTestModule, :hook_a}},
        {:before_scenario, "@database", nil, {RunTestModule, :hook_b}}
      ]

      # With database tag, both hooks run
      {:ok, result} = ExBdd.Hooks.run_before_hooks(hooks, %{}, ["database"])
      assert result.hook_a == true
      assert result.hook_b == true

      # Without database tag, only global hook runs
      {:ok, result_no_tag} = ExBdd.Hooks.run_before_hooks(hooks, %{}, [])
      assert result_no_tag.hook_a == true
      refute Map.has_key?(result_no_tag, :hook_b)
    end

    test "run_before_hooks accepts keyword list return values" do
      defmodule KeywordReturnModule do
        def keyword_hook(_context), do: [db_ready: true, cache: :warm]
      end

      hooks = [
        {:before_scenario, nil, nil, {KeywordReturnModule, :keyword_hook}}
      ]

      {:ok, result} = ExBdd.Hooks.run_before_hooks(hooks, %{}, [])
      assert result.db_ready == true
      assert result.cache == :warm
    end

    test "run_before_hooks raises on invalid return values" do
      defmodule InvalidReturnModule do
        def bad_hook(_context), do: :something_wrong
      end

      hooks = [
        {:before_scenario, nil, nil, {InvalidReturnModule, :bad_hook}}
      ]

      assert_raise RuntimeError, ~r/Invalid hook return value/, fn ->
        ExBdd.Hooks.run_before_hooks(hooks, %{}, [])
      end
    end

    test "hooks run once per scenario with combined feature and scenario tags" do
      defmodule CombinedTagsModule do
        def count_hook(context) do
          count = Map.get(context, :hook_count, 0)
          {:ok, Map.put(context, :hook_count, count + 1)}
        end
      end

      hooks = [
        {:before_scenario, nil, nil, {CombinedTagsModule, :count_hook}},
        {:before_scenario, "@database", nil, {CombinedTagsModule, :count_hook}},
        {:before_scenario, "@special", nil, {CombinedTagsModule, :count_hook}}
      ]

      # Scenario 1: feature has @database, scenario has no extra tags
      # Combined tags: ["database"]
      # Should run: global + @database = 2 hooks
      {:ok, scenario1} = ExBdd.Hooks.run_before_hooks(hooks, %{}, ["database"])
      assert scenario1.hook_count == 2

      # Scenario 2: feature has @database, scenario has @special
      # Combined tags: ["database", "special"]
      # Should run: global + @database + @special = 3 hooks
      {:ok, scenario2} = ExBdd.Hooks.run_before_hooks(hooks, %{}, ["database", "special"])
      assert scenario2.hook_count == 3
    end

    test "supports every named and tagged macro form" do
      hooks = ExBdd.Hooks.collect_hooks([MacroForms])

      assert {:ok, scenario_context} =
               ExBdd.Hooks.run_before_hooks(hooks, %{test_pid: self()}, ["macro"])

      assert scenario_context.before_scenario

      assert {:ok, step_context} =
               ExBdd.Hooks.run_before_step_hooks(hooks, %{test_pid: self()}, ["macro"])

      assert step_context.before_step

      assert :ok =
               ExBdd.Hooks.run_after_step_hooks(
                 hooks,
                 %{test_pid: self()},
                 ["macro"],
                 :passed
               )

      assert_receive :tagged_after_step
      assert_receive :global_after_step
      assert_receive :named_after_step

      assert :ok = ExBdd.Hooks.run_after_hooks(hooks, %{test_pid: self()}, ["macro"])
      assert_receive :after_scenario
    end

    test "halts pending and skipped hooks and preserves the reason" do
      pending = [
        {:before_scenario, nil, nil, {HaltingHooks, :pending}}
      ]

      skipped = [
        {:before_scenario, nil, nil, {HaltingHooks, :skipped}}
      ]

      assert {:halted, :pending, nil} = ExBdd.Hooks.run_before_hooks(pending, %{}, [])

      assert {:halted, :skipped, "not today"} =
               ExBdd.Hooks.run_before_hooks(skipped, %{}, [])
    end

    test "does not invoke later hooks after an error" do
      hooks = [
        {:before_scenario, nil, "failed", {HaltingHooks, :failed}},
        {:before_scenario, nil, nil, {HaltingHooks, :should_not_run}}
      ]

      assert {:error, :unavailable, "failed"} =
               ExBdd.Hooks.run_before_hooks(hooks, %{}, [])
    end
  end

  describe "collect_hooks/1" do
    test "loads modules that are compiled into the application but not yet loaded" do
      # Hook modules under test/support (or any compiled application) are
      # loaded lazily; collect_hooks must not silently drop a module the
      # code server hasn't loaded yet. ExBdd.ReloadableHooks exists only
      # for this test — unload it to reproduce the pre-load state.
      {:module, module} = Code.ensure_loaded(ExBdd.ReloadableHooks)
      :code.purge(module)
      :code.delete(module)
      :code.purge(module)
      refute :erlang.module_loaded(module)

      assert [{:before_scenario, nil, nil, {^module, _fun}}] =
               ExBdd.Hooks.collect_hooks([module])
    end
  end
end
