defmodule BnestAppWeb.OwnMessageMarkupFixture do
  @moduledoc """
  The own-message markup the Codex chat writes for a visitor's message (ADR 005, decision 4).

  The unit tests check the production component with these helpers. The integration test compares the committed JSON
  fixture that the Vitest rows use with the output of `own_message_html/1`.
  """

  alias BnestAppWeb.ChatComponents

  # The three inputs the Codex chat scenarios use: Markdown, a hostile message, and typed line breaks.
  # The hostile input starts its link on a new paragraph. A line that starts with `<script>` would open an HTML block
  # and the whole line would stay text, so no anchor would ever be parsed. The mailto link is a positive control: it
  # proves the message does render links, so a missing anchor cannot pass the javascript check. It is a mailto address
  # with a synthetic test user, so no network address appears in the unit layer.
  @inputs %{
    "plain" => "**Bold** and `code`",
    "hostile" =>
      "Hi <script>alert(\"x\")</script>\n\n[click](" <>
        "javascript" <> ":alert(1)) and [ok](mailto:test-user-visitor@example.invalid)",
    "whitespace" => "first  line\n\n  indented **line**"
  }

  def inputs, do: @inputs

  def own_message_html(content) do
    ChatComponents.own_message(%{id: "fixture", content: content})
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  # The text inside the raw element, with the escapes HEEx writes undone (`&amp;` last).
  def raw_text(html) do
    [raw] =
      Regex.run(~r/data-role="user-message-raw"[^>]*>(.*?)<\/p>/s, html, capture: :all_but_first)

    raw
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end
end
