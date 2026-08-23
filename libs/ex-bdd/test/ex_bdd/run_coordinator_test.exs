defmodule ExBdd.RunCoordinatorTest do
  # async: false — the coordinator is a named singleton and these tests
  # reset its run id.
  use ExUnit.Case, async: false

  alias ExBdd.RunCoordinator

  test "ensure_started starts the coordinator and returns a run id" do
    run_id = RunCoordinator.ensure_started()

    assert is_integer(run_id)
    assert RunCoordinator.run_id() == run_id
  end

  test "ensure_started on a running coordinator resets to a fresh run id" do
    first = RunCoordinator.ensure_started()
    second = RunCoordinator.ensure_started()

    assert second != first
    assert RunCoordinator.run_id() == second
  end

  defmodule BeforeAllProbe do
    def increment(context) do
      count = Agent.get_and_update(__MODULE__.Counter, &{&1 + 1, &1 + 1})
      {:ok, Map.put(context, :count, count)}
    end
  end

  describe "before_all_context/1" do
    test "executes before_all hooks once and caches the merged context" do
      {:ok, _} = Agent.start(fn -> 0 end, name: BeforeAllProbe.Counter)
      on_exit(fn -> Agent.stop(BeforeAllProbe.Counter) end)

      RunCoordinator.ensure_started()
      hooks = [{:before_all, nil, nil, {BeforeAllProbe, :increment}}]

      assert {:ok, %{count: 1}} = RunCoordinator.before_all_context(hooks)
      # Second call returns the cached result without re-running the hook
      assert {:ok, %{count: 1}} = RunCoordinator.before_all_context(hooks)
      assert Agent.get(BeforeAllProbe.Counter, & &1) == 1

      # A reset clears the cache: the hook runs again for the new run
      RunCoordinator.ensure_started()
      assert {:ok, %{count: 2}} = RunCoordinator.before_all_context(hooks)
    end

    test "returns {:ok, %{}} without hooks and without a coordinator" do
      assert {:ok, %{}} = RunCoordinator.before_all_context([])
    end

    defmodule BeforeAllReturnShapes do
      def map(_context), do: %{map: true}
      def keyword(_context), do: [keyword: true]
      def error(_context), do: {:error, :not_ready}
      def invalid(_context), do: :invalid
    end

    test "merges map and keyword returns from before_all hooks" do
      RunCoordinator.ensure_started()

      hooks = [
        {:before_all, nil, nil, {BeforeAllReturnShapes, :map}},
        {:before_all, nil, nil, {BeforeAllReturnShapes, :keyword}}
      ]

      assert {:ok, %{map: true, keyword: true}} = RunCoordinator.before_all_context(hooks)
    end

    test "reports explicit errors and invalid before_all returns" do
      RunCoordinator.ensure_started()

      assert {:error, error} =
               RunCoordinator.before_all_context([
                 {:before_all, nil, "setup", {BeforeAllReturnShapes, :error}}
               ])

      assert error =~ ~s(BeforeAll hook "setup" failed: :not_ready)

      RunCoordinator.ensure_started()

      assert {:error, error} =
               RunCoordinator.before_all_context([
                 {:before_all, nil, nil, {BeforeAllReturnShapes, :invalid}}
               ])

      assert error =~ "returned invalid value"
    end
  end

  describe "run_after_all/1" do
    defmodule AfterAllProbe do
      # run_after_all executes hooks in the calling process — the test
      # process here — so self() is the test pid
      def record(context) do
        send(self(), {:after_all_ran, context.suite_result})
        :ok
      end

      def explode(_context), do: raise("cleanup went wrong")
      def fail(_context), do: {:error, :cleanup_failed}
    end

    test "claims registered after_all hooks exactly once" do
      RunCoordinator.ensure_started()
      RunCoordinator.register_after_all([{:after_all, nil, nil, {AfterAllProbe, :record}}])

      suite_result = %{total: 5, failures: 0}
      assert :ok = RunCoordinator.run_after_all(suite_result)
      assert_receive {:after_all_ran, ^suite_result}

      # Already claimed: nothing runs the second time
      assert :ok = RunCoordinator.run_after_all(suite_result)
      refute_receive {:after_all_ran, _}
    end

    test "a raising after_all hook fails the run with its own error" do
      RunCoordinator.ensure_started()
      RunCoordinator.register_after_all([{:after_all, nil, nil, {AfterAllProbe, :explode}}])

      assert_raise RuntimeError, "cleanup went wrong", fn ->
        RunCoordinator.run_after_all(%{total: 0, failures: 0})
      end
    end

    test "a named error return fails after_all with a labelled message" do
      RunCoordinator.ensure_started()

      RunCoordinator.register_after_all([
        {:after_all, nil, "cleanup", {AfterAllProbe, :fail}}
      ])

      assert_raise RuntimeError, ~r/AfterAll hook "cleanup" failed: :cleanup_failed/, fn ->
        RunCoordinator.run_after_all(%{total: 0, failures: 0})
      end
    end
  end

  describe "disabled message sink" do
    test "keeps all message operations as no-ops" do
      RunCoordinator.ensure_started()

      assert RunCoordinator.message_context() == nil
      assert RunCoordinator.take_message_ids(2) == nil
      assert RunCoordinator.emit_runtime([%{meta: %{}}]) == :ok
      assert RunCoordinator.finish_test_case("missing", :unknown, false) == :ok
      assert RunCoordinator.skip_unfinished_steps("missing", ["step"], :skipped) == :ok
      assert RunCoordinator.flush_messages(%{failures: 0}) == :ok
    end

    test "starts lazily and records an attachment through the default arity" do
      if pid = Process.whereis(RunCoordinator), do: GenServer.stop(pid)

      attachment = %ExBdd.Attachment{body: "log", media_type: "text/plain"}

      assert :ok = RunCoordinator.record_attachment(attachment)
      assert RunCoordinator.attachments() == [attachment]
    end

    test "ignores hook-finished events when messages are disabled" do
      state = %{
        run_id: 1,
        before_all: :not_run,
        after_all: [],
        attachments: [],
        messages: nil
      }

      assert {:reply, :ok, ^state} =
               RunCoordinator.handle_call(
                 {:run_hook_finished, "started", :passed, 1},
                 self(),
                 state
               )
    end
  end

  describe "unknown message references" do
    test "ignore step and case events whose test case was never opened" do
      RunCoordinator.ensure_started()

      RunCoordinator.configure_messages(%{
        path: Path.join(System.tmp_dir!(), "unused-ex-bdd-messages.ndjson"),
        envelopes: [],
        next_id: 1,
        step_definition_ids: %{},
        hook_ids: %{}
      })

      assert :ok =
               RunCoordinator.emit_runtime([
                 %{
                   testStepStarted: %{
                     testCaseStartedId: "unknown-case",
                     testStepId: "unknown-step"
                   }
                 }
               ])

      assert :ok =
               RunCoordinator.skip_unfinished_steps("unknown-case", ["unknown-step"], :skipped)

      assert :ok = RunCoordinator.finish_test_case("unknown-case", :unknown, false)

      RunCoordinator.ensure_started()
    end
  end
end
