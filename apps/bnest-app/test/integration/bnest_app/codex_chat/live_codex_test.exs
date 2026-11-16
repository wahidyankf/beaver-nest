defmodule BnestApp.CodexChat.LiveCodexTest do
  @moduledoc """
  Development-only proof that Bnest chat consumes the real Codex CLI through the production
  adapter and runner. Both tests need a logged-in system `codex` binary on PATH, so they carry
  the `:ci-exempt` tag: `test:integration` excludes them and only the dev-only `test:live`
  target runs them, with `--only ci-exempt`.
  """

  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.CodexCliModelDiscovery
  alias BnestApp.CodexChat.Adapters.CodexPortSession

  @moduletag :"ci-exempt"

  @tag timeout: 300_000
  test "a real turn completes through the production runner" do
    with_bundled_runner(fn ->
      assert {:ok, session} =
               CodexPortSession.open(self(), nil, "gpt-6-luna", "medium", :read_only)

      try do
        assert :ok = CodexPortSession.send_prompt(session, "Reply with exactly: OK")

        assert_receive {:codex, ^session, {:thread_started, _thread_id}}, 60_000

        texts = collect_until_completed(session, 120_000)

        assert Enum.any?(texts, &String.contains?(&1, "OK")),
               "the real turn never answered OK: #{inspect(texts)}"

        refute Enum.any?(texts, &String.contains?(&1, "Fixture")),
               "the turn answered with fixture text, not the real CLI: #{inspect(texts)}"
      after
        CodexPortSession.close(session)
      end
    end)
  end

  test "real model discovery lists gpt-6-luna" do
    with_env("BNEST_CODEX_MODELS_RUNNER", CodexCliModelDiscovery.bundled_models_runner(), fn ->
      assert {:ok, models} = CodexCliModelDiscovery.discover([])
      assert Enum.any?(models, &(&1["id"] == "gpt-6-luna"))
    end)
  end

  # The integration layer may point BNEST_CODEX_RUNNER at the fixture runner; this test needs the
  # real bundled runner, which the port session reads from the system environment at open time.
  defp with_bundled_runner(fun),
    do: with_env("BNEST_CODEX_RUNNER", CodexPortSession.bundled_runner(), fun)

  # A developer's BNEST_CODEX_MODELS_RUNNER override would substitute a fixture the same way,
  # so the discovery test clears it around the call too.
  defp with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if previous,
        do: System.put_env(name, previous),
        else: System.delete_env(name)
    end
  end

  defp collect_until_completed(session, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect_until_completed(session, deadline, [])
  end

  defp collect_until_completed(session, deadline, texts) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex, ^session, {:assistant_update, _item_id, text}} ->
        collect_until_completed(session, deadline, [text | texts])

      {:codex, ^session, {:reasoning_update, _item_id, _text}} ->
        collect_until_completed(session, deadline, texts)

      {:codex, ^session, {:activity_update, _item_id, _text}} ->
        collect_until_completed(session, deadline, texts)

      {:codex, ^session, :turn_completed} ->
        Enum.reverse(texts)

      {:codex, ^session, {:error, message}} ->
        flunk("the real turn failed: #{message}")

      {:codex, ^session, {:resume_failed, message}} ->
        flunk("the real turn resume failed: #{message}")
    after
      remaining -> flunk("the real turn did not complete in time")
    end
  end
end
