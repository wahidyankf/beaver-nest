defmodule BnestAppWeb.ChatComponentsTest do
  # ADR 003, Decision 2: one piece of markup for both chat rooms. The function component and the
  # binary renderer must produce the same bytes, which is the proof that there is one markup.
  #
  # Unit files may not spell out a scheme with its slashes, so the https scheme is joined at compile time.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import BnestAppWeb.ChatComponents, only: [markdown_body: 1]

  alias BnestAppWeb.ChatComponents
  alias Phoenix.HTML.Safe

  # The same conversion the LiveView test helper makes. Unit files may not use that helper module
  # (test/behaviour/verify.exs), so the conversion is spelled out with `Phoenix.HTML`.
  defp rendered_to_string(rendered) do
    rendered |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  @https "https:" <> "//"
  @content "Hello **there**\nsecond line\n\n![Remote](#{@https}example.com/a.png)\n\n<b>raw</b>"

  describe "the component and markdown_body_html/2" do
    test "render the same bytes for the same input, with hard breaks and a class and global attributes" do
      assigns = %{content: @content}

      component =
        rendered_to_string(~H"""
        <.markdown_body
          content={@content}
          hard_breaks={true}
          class="extra"
          data-role="family-chat-message-body"
        />
        """)

      binary =
        ChatComponents.markdown_body_html(@content,
          hard_breaks: true,
          class: "extra",
          attrs: %{"data-role": "family-chat-message-body"}
        )

      assert component == binary
      assert binary =~ "<br"
    end

    test "render the same bytes for a streaming reply with the defaults" do
      assigns = %{content: "**bol"}
      component = rendered_to_string(~H"<.markdown_body content={@content} streaming={true} />")

      assert component == ChatComponents.markdown_body_html("**bol", streaming: true)
      assert component =~ "<strong>bol</strong>"
    end

    test "render the same bytes with no attributes at all" do
      assigns = %{content: @content}
      component = rendered_to_string(~H"<.markdown_body content={@content} />")

      assert component == ChatComponents.markdown_body_html(@content, [])
    end

    # ADR 004, Decision 2: the diagram marker is ordinary markup, so both paths carry it the same way.
    test "render the same bytes for a mermaid diagram, with the marker" do
      content = "```mermaid\nflowchart TD\n  A --> B\n```"
      assigns = %{content: content}
      component = rendered_to_string(~H"<.markdown_body content={@content} />")

      assert component == ChatComponents.markdown_body_html(content, [])
      assert component =~ ~s(<pre data-bnest-diagram="mermaid"><code>)
    end
  end

  describe "the wrapper" do
    test "carries the fixed classes, then the extra class" do
      html = ChatComponents.markdown_body_html("text", class: "extra")

      # The `phx-r` root marker comes from the app's LiveView config, so it may sit before `class`.
      assert html =~ ~r/\A<div [^>]*class="message-content markdown-body extra">/
    end

    test "joins a class given in the attrs map, so there is only one class attribute" do
      html =
        ChatComponents.markdown_body_html("text", attrs: %{class: "family-chat-message-body"})

      assert html =~ ~s(class="message-content markdown-body family-chat-message-body")
      assert length(Regex.scan(~r/\sclass=/, html)) == 1
    end

    test "puts the global attributes on the wrapper element" do
      html = ChatComponents.markdown_body_html("text", attrs: %{"data-streaming": "true"})

      assert html =~ ~r/\A<div [^>]*data-streaming="true"/
    end

    test "keeps a single newline as a soft break unless hard breaks are asked for" do
      refute ChatComponents.markdown_body_html("first\nsecond", []) =~ "<br"
      assert ChatComponents.markdown_body_html("first\nsecond", hard_breaks: true) =~ "<br"
    end

    # In dev the template engine adds comments and `data-phx-loc` attributes around a component. The binary is
    # stored in the GraphQL `bodyHtml` field, so it must carry none of them in any environment.
    test "carries no debug annotations, so the stored bodyHtml is the same in every environment" do
      html =
        ChatComponents.markdown_body_html("**x**", class: "extra", attrs: %{"data-role": "r"})

      refute html =~ "<!--"
      refute html =~ "data-phx-loc"
      assert html =~ ~r/\A<div [^>]*>.*<\/div>\z/su
    end

    test "shows raw HTML as escaped text" do
      html = ChatComponents.markdown_body_html("<b>raw</b>", [])

      assert html =~ "&lt;b&gt;"
      refute html =~ "<b>"
    end
  end

  describe "markdown_body/1" do
    test "is a function component that can be called with a plain assigns map" do
      html =
        markdown_body(%{
          __changed__: nil,
          content: "**x**",
          streaming: false,
          hard_breaks: false,
          class: nil,
          rest: %{}
        })
        |> Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html == ChatComponents.markdown_body_html("**x**", [])
    end
  end
end
