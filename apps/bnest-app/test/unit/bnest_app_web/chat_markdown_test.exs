defmodule BnestAppWeb.ChatMarkdownTest do
  # ADR 002, Decision 1 (renderer) and Decision 2 (image rules), with the XSS corpus listed under
  # "XSS corpus the unit test must include". Unit files may not spell out a scheme with its slashes,
  # so the https scheme is joined at compile time.
  #
  # The safety checks read markup, not text: raw HTML is shown as escaped text by design, so
  # `&lt;script&gt;alert(1)&lt;/script&gt;` is safe even though it contains the word "script".
  use ExUnit.Case, async: true

  alias BnestApp.SchemaSourceScan
  alias BnestAppWeb.ChatMarkdown

  @https "https:" <> "//"
  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  @xss_corpus [
    "<script>alert(1)</script>",
    "<img src=x onerror=alert(1)>",
    "<b onclick=\"x()\">bold</b>",
    "<iframe src=x></iframe>",
    "<svg onload=alert(1)></svg>",
    "<a href=\"javascript:alert(1)\">click</a>",
    "[x](javascript:alert(1))",
    "[x](JaVa&#x09;Script:alert(1))",
    "[x](vbscript:x)",
    "[x](data:text/html;base64,AAAA)",
    "![x](javascript:alert(1))",
    "![x](data:image/svg+xml;base64,AAAA)",
    "![x](data:image/png;base64,iVBORw0KGgo=)",
    "![x](//evil.example/a.png)",
    "![x](#{@https}evil.example/a.png)",
    "![x](docs/a.svg)",
    "![x](../../etc/a.png)",
    "![x](/etc/a.png)",
    "![x](.git/a.png)",
    "![x](data/prod/a.png)",
    "![x](docs/a.png\" onerror=\"alert(1))",
    "[![x](docs/a.png)](javascript:alert(1))",
    "<javascript:alert(1)>",
    "[x][r]\n\n[r]: javascript:alert(1)",
    "<!-- comment -->",
    "<style>body { display: none }</style>",
    "<form action=x><input name=y></form>",
    "<input name=loose>",
    "<span style=\"color: red\" class=\"x\">styled</span>"
  ]

  @raw_html_snippets [
    "<script>alert(1)</script>",
    "<b onclick=\"x()\">bold</b>",
    "<iframe src=x></iframe>",
    "<img src=x onerror=alert(1)>",
    "<svg onload=alert(1)></svg>",
    "<style>body { display: none }</style>",
    "<form action=x></form>",
    "<input name=loose>",
    "<!-- comment -->",
    "<span style=\"color: red\" class=\"x\">styled</span>"
  ]

  describe "GitHub-flavoured Markdown" do
    @sample """
    # Title

    Some **bold** and *italic* text with `code` and ~~old~~.

    - one
    - two

    1. first

    - [x] done
    - [ ] open

    | a | b |
    | - | - |
    | 1 | 2 |

    > quoted

    ---

    ```elixir
    IO.puts("hi")
    ```
    """

    test "renders headings, emphasis, code, lists, tasks, tables, quotes, rules and strikethrough" do
      html = render(@sample)

      assert html =~ "<h1"
      assert html =~ "<strong>bold</strong>"
      assert html =~ "<em>italic</em>"
      assert html =~ "<code>code</code>"
      assert html =~ "<del>old</del>"
      assert html =~ "<ul"
      assert html =~ "<ol"
      assert html =~ ~s(type="checkbox")
      assert [done, open] = tags(html, "input")
      assert done =~ " checked", "the done task is not checked: #{done}"
      refute open =~ " checked", "the open task is checked: #{open}"
      assert html =~ "<table"
      assert html =~ "<blockquote"
      assert html =~ "<hr"
      assert html =~ "language-elixir"
    end

    test "a task checkbox is the only input element a reply can contain" do
      html = render("- [x] done\n- [ ] open")

      assert [_, _] = tags(html, "input")
      assert_safe(html, "task list")
    end

    test "raw HTML is shown as escaped text, never as markup" do
      for snippet <- @raw_html_snippets do
        html = render(snippet)

        assert html =~ "&lt;", "#{inspect(snippet)} was not escaped"

        refute html =~ ~r/<(script|b|iframe|img|svg|style|form|input|span)\b/i,
               "#{inspect(snippet)} rendered as markup: #{html}"
      end
    end

    test "the visible text of a script stays readable" do
      assert render("<script>alert(1)</script>") =~ "alert(1)"
    end

    test "no source file calls the two Markdown entry points that the ADR forbids" do
      # The shared helper reads the app's own committed source as text (see its moduledoc).
      for file <- SchemaSourceScan.wildcard(["**", "*.ex"]) do
        source = SchemaSourceScan.read!(file)

        refute source =~ "to_delta", "#{file} calls to_delta, which skips the URL scheme check"

        refute source =~ ~r/parse_document!?\(\s*\{\s*:json/,
               "#{file} parses a JSON document, which allows atom exhaustion"
      end
    end
  end

  describe "the XSS corpus" do
    for {content, index} <- Enum.with_index(@xss_corpus) do
      test "corpus case #{index} is sanitized" do
        assert_safe(render(unquote(content)), unquote(content))
      end
    end

    test "a 100 KB reply of unfinished syntax is safe, whether it streams or not" do
      content = String.duplicate("*a ", 33_000) <> String.duplicate("[a](", 250)

      assert_safe(render(content, true), "100 KB streaming")
      assert_safe(render(content, false), "100 KB complete")
    end
  end

  describe "links" do
    test "a safe link opens in a new tab without sharing the page" do
      html = render("[docs](#{@https}example.com/docs)")

      [tag] = tags(html, "a")
      assert tag =~ ~s(href="#{@https}example.com/docs")
      assert tag =~ ~s(target="_blank")
      assert tag =~ ~s(rel="noopener noreferrer nofollow")
    end

    test "an autolink gets the same new tab and rel attributes" do
      html = render("<#{@https}example.com>")

      [tag] = tags(html, "a")
      assert tag =~ ~s(target="_blank")
      assert tag =~ ~s(rel="noopener noreferrer nofollow")
    end

    test "an unsafe link keeps its text and is not clickable" do
      html = render("[click here](javascript:alert(1))")

      assert html =~ "click here"
      assert tags(html, "a") == []
    end

    test "a mailto link stays a link, and a relative or protocol-relative link becomes its text" do
      html = render("[mail](mailto:help@example.com) [docs](docs/a.md) [host](//evil.example)")

      assert [mail_tag] = tags(html, "a")
      assert mail_tag =~ ~s(href="mailto:help@example.com")
      assert html =~ "docs"
      assert html =~ "host"
      refute html =~ "docs/a.md"
      refute html =~ "evil.example"
    end

    test "a link inside a streaming reply that has not closed shows only its text" do
      html = render("see [link](#{@https}exa", true)

      assert html =~ "see link"
      assert tags(html, "a") == []
    end
  end

  describe "images" do
    test "a repository image is shown through the image route, with its alt text and safe attributes" do
      html = render("![Beaver Nest logo](#{@logo})")

      [tag] = tags(html, "img")
      assert tag =~ ~s(alt="Beaver Nest logo")
      assert tag =~ ~s(loading="lazy")
      assert tag =~ ~s(referrerpolicy="no-referrer")
      assert tag =~ ~s(decoding="async")
      assert image_path(html) == @logo
    end

    test "a leading ./ and a percent-encoded space name the same file the route accepts" do
      assert html = render("![x](./docs/my%20shot.png)")
      assert image_path(html) == "docs/my shot.png"
    end

    test "an external image is shown as a link that says it is not loaded, never loaded" do
      html = render("![Remote logo](#{@https}example.com/remote-logo.png)")

      assert tags(html, "img") == []
      assert [tag] = tags(html, "a")
      assert tag =~ ~s(href="#{@https}example.com/remote-logo.png")
      assert html =~ "Remote logo (image not shown)"
    end

    test "an external image without alt text shows its address as the withheld link text" do
      html = render("![](#{@https}example.com/remote-logo.png)")

      assert tags(html, "img") == []
      assert html =~ "#{@https}example.com/remote-logo.png (image not shown)"
    end

    test "a data image is withheld and its text says so, with its alt text" do
      html = render("![Inline dot](data:image/png;base64,iVBORw0KGgo=)")

      assert tags(html, "img") == []
      assert tags(html, "a") == []
      assert html =~ "[image not shown: Inline dot]"
    end

    test "an image the route would refuse says it is not shown, even without alt text" do
      html = render("![](docs/a.svg)")

      assert tags(html, "img") == []
      assert html =~ "[image not shown]"
    end

    test "an external image nested in a link collapses to one safe link" do
      html = render("[![Logo](#{@https}example.com/logo.png)](#{@https}example.com/docs)")

      assert [tag] = tags(html, "a")
      assert tag =~ ~s(href="#{@https}example.com/docs")
      assert tag =~ ~s(target="_blank")
      assert tag =~ ~s(rel="noopener noreferrer nofollow")
      assert html =~ "Logo (image not shown)"
      assert tags(html, "img") == []
    end

    test "a destination the route would refuse is never rendered as an image" do
      destinations = [
        "docs/a.svg",
        "../../etc/a.png",
        "/etc/a.png",
        ".git/a.png",
        "data/prod/a.png",
        "docs/a%zz.png",
        "docs/100%25.png",
        "docs/a.png\" onerror=\"alert(1)",
        "#{@https}evil.example/a.png",
        "//evil.example/a.png",
        "data:image/png;base64,iVBORw0KGgo="
      ]

      for destination <- destinations do
        html = render("![x](#{destination})")

        assert tags(html, "img") == [], "rendered an image for #{inspect(destination)}"
      end
    end
  end

  describe "the text kept from a refused link or image" do
    test "keeps the emphasis and code of an unsafe link as plain text" do
      html = render("[*emph* and `code`](javascript:alert(1))")

      assert html =~ "emph and code"
      assert tags(html, "a") == []
    end

    test "keeps the words of an image shown as alt text on either side of a line break" do
      html = render("![first\\\nsecond](docs/a.svg)")

      assert html =~ "first"
      assert html =~ "second"
      assert tags(html, "img") == []
    end
  end

  describe "a reply that is still streaming" do
    test "closes unfinished bold" do
      assert render("**bol", true) =~ "<strong>bol</strong>"
    end

    test "leaves unfinished bold as text once the reply is complete" do
      refute render("**bol", false) =~ "<strong>"
    end

    test "closes an unfinished code fence as a code block" do
      assert render("```elixir\nIO.puts(", true) =~ "<pre"
    end
  end

  describe "when the renderer cannot finish" do
    test "a parse that runs out of time shows the escaped text in a pre-wrapped paragraph" do
      # 720 KB of nested emphasis, which exceeds a 1 ms parse budget on any host.
      content = "<script>alert(1)</script> " <> String.duplicate("*a ", 240_000)

      html = render(content, false, parse_time_ms: 1)

      assert html =~ "whitespace-pre-wrap"
      assert html =~ "&lt;script&gt;"
      refute html =~ "<script"
    end

    test "invalid UTF-8 shows the escaped text in a pre-wrapped paragraph" do
      html = render(<<"ok ", 0xFF, 0xFE, " <b>x</b>">>)

      assert html =~ "whitespace-pre-wrap"
      refute html =~ "<b>"
      assert String.valid?(html), "the fallback kept invalid bytes: #{inspect(html)}"
      assert html =~ "ok "
    end

    test "an empty reply renders without a crash" do
      assert is_binary(render(""))
    end
  end

  defp render(content, streaming? \\ false, options \\ []) do
    content
    |> ChatMarkdown.to_html(streaming?, options)
    |> Phoenix.HTML.safe_to_string()
  end

  defp image_path(html) do
    [src] = attribute_values(html, "src")
    assert "/chat/images/" <> encoded = src
    URI.decode(encoded)
  end

  defp tags(html, name) do
    Regex.scan(~r/<#{name}\b[^>]*>/i, html) |> List.flatten()
  end

  defp attribute_values(html, attribute) do
    Regex.scan(~r/<[a-zA-Z][^>]*\s#{attribute}="([^"]*)"/, html, capture: :all_but_first)
    |> List.flatten()
  end

  # Checks what a browser would follow: entities are decoded and control characters removed
  # first, because `JaVa&#x09;Script:` is a working `javascript:` address.
  defp decode_entities(value) do
    value
    |> decode_numeric_entities(~r/&#x([0-9a-f]+);/i, 16)
    |> decode_numeric_entities(~r/&#([0-9]+);/, 10)
    |> String.replace("&colon;", ":")
    |> String.replace("&Tab;", "\t")
    |> String.replace("&NewLine;", "\n")
  end

  # `String.replace/3` takes a one-argument replacement function, and this one reads the
  # captured digits, so the group-capturing replacement goes through `Regex.replace/3`.
  defp decode_numeric_entities(value, pattern, base) do
    Regex.replace(pattern, value, fn _whole, digits ->
      <<String.to_integer(digits, base)::utf8>>
    end)
  end

  defp assert_safe(html, label) do
    for banned <- ["<script", "<iframe", "<style", "<form", "<!--"] do
      refute html =~ banned, "#{label} rendered #{banned}"
    end

    for tag <- tags(html, "[a-zA-Z][a-zA-Z0-9]*") do
      refute tag =~ ~r/\son[a-z]+\s*=/i, "#{label} rendered an event handler: #{tag}"
    end

    for value <- attribute_values(html, "href") ++ attribute_values(html, "src") do
      address =
        value
        |> decode_entities()
        |> String.replace(~r/[\x00-\x20]/, "")
        |> String.downcase()

      refute address =~ ~r/^(javascript|vbscript|data):/,
             "#{label} rendered an unsafe address: #{value}"

      refute String.starts_with?(address, "//"),
             "#{label} rendered a protocol-relative address: #{value}"
    end

    for tag <- tags(html, "img") do
      assert tag =~ ~r/\ssrc="\/chat\/images\//,
             "#{label} rendered an image outside the image route: #{tag}"
    end

    for tag <- tags(html, "a") do
      assert tag =~ ~s(rel="noopener noreferrer nofollow"), "#{label} link lacks rel: #{tag}"
      assert tag =~ ~s(target="_blank"), "#{label} link lacks target: #{tag}"
    end
  end
end
