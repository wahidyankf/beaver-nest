defmodule BnestApp.CodexChat.RunnerExitTest do
  # A Codex runner that is gone, or that prints a line the session cannot parse,
  # reports one fixed line to its owner. The scripts below stand in for the
  # bundled chat runner through `BNEST_CODEX_RUNNER`, the same seam the chat
  # scenarios use.
  #
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A runner exit or invalid runner output shows one fixed line
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.CodexPortSession

  @moduletag :tmp_dir

  test "a runner exit reports its status to the owner", %{tmp_dir: dir} do
    script = write_script!(dir, "exit-three.mjs", "process.exit(3);\n")

    {:ok, session} =
      with_runner(script, fn ->
        CodexPortSession.open(self(), nil, "gpt-6.1-terra", "medium", :read_only)
      end)

    assert_receive {:codex, ^session, {:error, "Codex runner exited with status 3."}}, 10_000
  end

  test "runner output that is not JSON reports invalid data to the owner", %{tmp_dir: dir} do
    script =
      write_script!(
        dir,
        "invalid-line.mjs",
        "process.stdout.write(\"this line is not runner JSON\\n\");\n"
      )

    {:ok, session} =
      with_runner(script, fn ->
        CodexPortSession.open(self(), nil, "gpt-6.1-terra", "medium", :read_only)
      end)

    assert_receive {:codex, ^session, {:error, "Codex runner returned invalid data."}}, 10_000
  end

  defp write_script!(dir, name, source) do
    path = Path.join(dir, name)
    File.write!(path, source)
    path
  end

  defp with_runner(script, fun) do
    previous = System.get_env("BNEST_CODEX_RUNNER")
    System.put_env("BNEST_CODEX_RUNNER", script)

    try do
      fun.()
    after
      if is_nil(previous),
        do: System.delete_env("BNEST_CODEX_RUNNER"),
        else: System.put_env("BNEST_CODEX_RUNNER", previous)
    end
  end
end
