defmodule BnestAppWeb.CodexRenderedRepliesTest do
  @moduledoc """
  Pins the rendered Codex replies the browser tests read.

  `apps/bnest-app/assets/test/support/codex_rendered_replies.json` maps each fixture prompt to the HTML the Codex
  chat renders for that fixture's reply text (`ChatMarkdown.to_html/2`, the same call the chat component makes).
  The vitest binding for the hostile diagram scenario reads that HTML as the reply, so those tests stay true only
  while the renderer still produces it. This test renders each entry again and fails on any difference, and the
  failure message prints the expected and the actual HTML, so a change to the server's output (for example a removed
  refusal gate) is read from the failure.

  To regenerate the pin after an intended change, run, from `apps/bnest-app`:

      BNEST_REGENERATE_PINS=1 BNEST_TEST_LAYER=integration MIX_ENV=test \\
        mix test test/integration/bnest_app_web/codex_rendered_replies_test.exs

  then format the file with `npm exec -- prettier --write assets/test/support/codex_rendered_replies.json`
  from the repository root.
  """
  use ExUnit.Case, async: true

  alias BnestAppWeb.ChatMarkdown
  alias Phoenix.HTML.Safe

  @fixture Path.expand("../../support/codex_fixture_replies.json", __DIR__)
  @rendered Path.expand("../../../assets/test/support/codex_rendered_replies.json", __DIR__)

  test "every pinned reply is what the renderer returns for its fixture text" do
    fixtures = @fixture |> File.read!() |> Jason.decode!()
    entries = @rendered |> File.read!() |> Jason.decode!()

    assert map_size(entries) > 0

    if System.get_env("BNEST_REGENERATE_PINS") == "1" do
      regenerated = Map.new(entries, fn {prompt, _html} -> {prompt, render(fixtures, prompt)} end)
      File.write!(@rendered, Jason.encode!(regenerated, pretty: true) <> "\n")
    else
      for {prompt, expected} <- entries do
        actual = render(fixtures, prompt)

        assert actual == expected,
               """
               rendered reply drifted for #{inspect(prompt)}
               expected:
               #{expected}
               actual:
               #{actual}
               """
      end
    end
  end

  defp render(fixtures, prompt) do
    text = fixtures |> Map.fetch!(prompt) |> Map.fetch!("text")

    ChatMarkdown.to_html(text, false)
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
