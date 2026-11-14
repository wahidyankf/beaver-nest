defmodule BnestAppWeb.OwnMessageMarkupTest do
  # ADR 005, decision 4: a visitor's own message shows its Markdown and keeps the typed text in a raw element.
  # The committed fixture is checked by the integration test BnestAppWeb.OwnMessageMarkupFixtureTest.
  use ExUnit.Case, async: true

  alias BnestAppWeb.OwnMessageMarkupFixture, as: Fixture

  test "the raw element holds each input exactly as the visitor typed it" do
    for {name, input} <- Fixture.inputs() do
      assert Fixture.raw_text(Fixture.own_message_html(input)) == input,
             "the raw element of #{name} differs from its input"
    end
  end

  test "the rendered view of a hostile message holds no script element and no javascript link" do
    html = Fixture.own_message_html(Fixture.inputs()["hostile"])
    [rendered] = Regex.run(~r/data-role="user-message"[\s\S]*?<\/div>/, html)

    # Positive control: the mailto link renders as the one anchor, so the checks below cannot pass on a message
    # that has no anchor at all.
    anchors = Regex.scan(~r/<a\b[^>]*>/, rendered)
    assert [[anchor]] = anchors
    assert anchor =~ ~s(href="mailto:test-user-visitor@example.invalid")

    refute rendered =~ "<script"
    refute rendered =~ ~s(href="javascript:)
    refute rendered =~ "javascript:"
  end
end
