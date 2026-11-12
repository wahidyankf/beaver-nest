defmodule BnestAppWeb.FamilyChatRenderedBodiesTest do
  @moduledoc """
  Pins the rendered-body fixture the browser tests read.

  `apps/bnest-app/assets/test/support/family_chat_rendered_bodies.json` maps each Markdown source to the
  `bodyHtml` the Family Chat GraphQL field returns for it. The front-end unit room and the end-to-end suite
  feed that HTML to the page, so those tests stay true only while the renderer still produces it. This
  test regenerates each entry through the same call the GraphQL resolver makes and fails on any difference,
  so a renderer change (for example from the shared Markdown work) shows here instead of as a silent drift in
  the browser suites. Regenerate the fixture from the renderer when a change here is intended.
  """
  use ExUnit.Case, async: true

  alias BnestAppWeb.ChatComponents

  @fixture Path.expand("../../../assets/test/support/family_chat_rendered_bodies.json", __DIR__)

  test "every fixture entry is what the renderer returns for its Markdown source" do
    entries = @fixture |> File.read!() |> Jason.decode!()

    assert map_size(entries) > 0

    for {source, expected} <- entries do
      actual =
        ChatComponents.markdown_body_html(source,
          hard_breaks: true,
          attrs: %{"data-role": "family-chat-message-body", class: "family-chat-message-body"}
        )

      assert actual == expected, "rendered body drifted for #{inspect(source)}"
    end
  end
end
