defmodule BnestAppWeb.ChatReplyWrapperTest do
  # ADR 004, Decision 3: a Codex reply's wrapper carries its id, and `phx-update="ignore"` once the reply is
  # finished. The ChatLive template passes both through the global attributes of `markdown_body/1`, so the
  # component must put them on the wrapper and must omit an attribute whose value is nil.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import BnestAppWeb.ChatComponents, only: [markdown_body: 1]

  alias BnestAppWeb.ChatComponents

  defp rendered_to_string(rendered) do
    rendered |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  test "puts an id and a phx-update attribute on the wrapper element" do
    html =
      ChatComponents.markdown_body_html("text",
        attrs: %{id: "assistant-message-7", "phx-update": "ignore"}
      )

    assert html =~ ~r/\A<div [^>]*id="assistant-message-7"/
    assert html =~ ~r/\A<div [^>]*phx-update="ignore"/
  end

  test "omits a phx-update attribute whose value is nil, as a streaming reply does" do
    assigns = %{}

    component =
      rendered_to_string(~H"""
      <.markdown_body content="text" id="assistant-message-7" phx-update={nil} />
      """)

    refute component =~ "phx-update"
    assert component =~ ~s(id="assistant-message-7")
  end

  test "the function component and the binary renderer give the same wrapper" do
    assigns = %{}

    component =
      rendered_to_string(~H"""
      <.markdown_body content="text" id="assistant-message-7" phx-update="ignore" />
      """)

    binary =
      ChatComponents.markdown_body_html("text",
        attrs: %{id: "assistant-message-7", "phx-update": "ignore"}
      )

    assert component == binary
  end
end
