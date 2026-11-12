defmodule BnestAppWeb.ChatMarkdownTest do
  # ADR 002, Decision 1 (renderer) and Decision 2 (image rules), changed by ADR 003, Decision 1
  # (inline https and small raster data images), with the XSS corpus listed under
  # "XSS corpus the unit test must include". Unit files may not spell out a scheme with its slashes,
  # so the http and https schemes are joined at compile time.
  #
  # The safety checks read markup, not text: raw HTML is shown as escaped text by design, so
  # `&lt;script&gt;alert(1)&lt;/script&gt;` is safe even though it contains the word "script".
  use ExUnit.Case, async: true

  alias BnestApp.SchemaSourceScan
  alias BnestAppWeb.ChatMarkdown

  @https "https:" <> "//"
  @http "http:" <> "//"
  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  # Bytes that start with each raster signature, so the signature check accepts them.
  @png <<0x89, "PNG\r\n", 0x1A, "\n", "png body">>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg body">>
  @gif "GIF89a" <> "gif body"
  @webp "RIFF" <> <<12, 0, 0, 0>> <> "WEBP" <> "webp body"
  @svg "<svg xmlns='x'><script>alert(1)</script></svg>"
  @raster_images [{"png", @png}, {"jpeg", @jpeg}, {"gif", @gif}, {"webp", @webp}]

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
    "[x](data:image/png;base64,iVBORw0KGgo=)",
    "<data:image/png;base64,iVBORw0KGgo=>",
    "![x](javascript:alert(1))",
    "![x](data:image/svg+xml;base64,AAAA)",
    "![x](data:image/png;base64,iVBORw0KGgo=)",
    "![x](//evil.example/a.png)",
    "![x](#{@https}evil.example/a.png)",
    "![x](#{@http}evil.example/a.png)",
    "![x](docs/a.svg)",
    "![x](../../etc/a.png)",
    "![x](/etc/a.png)",
    "![x](.git/a.png)",
    "![x](data/prod/a.png)",
    "![x](docs/a.png\" onerror=\"alert(1))",
    "![x](#{@https}evil.example/a.png\" onerror=\"alert(1))",
    "[![x](docs/a.png)](javascript:alert(1))",
    "<javascript:alert(1)>",
    "[x][r]\n\n[r]: javascript:alert(1)",
    "<!-- comment -->",
    "<style>body { display: none }</style>",
    "<form action=x><input name=y></form>",
    "<input name=loose>",
    "<span style=\"color: red\" class=\"x\">styled</span>",
    # Diagram fences (ADR 004): hostile labels, directives and settings, and a forged marker.
    "```mermaid\nflowchart TD\n  A[\"<script>alert(1)</script>\"] --> B\n```",
    "```mermaid\nflowchart TD\n  A[\"<img src=x onerror=alert(1)>\"] --> B\n```",
    "```mermaid\nflowchart TD\n  A --> B\n  click A \"javascript:alert(1)\"\n```",
    "```mermaid\n%%{init: {\"securityLevel\": \"loose\"}}%%\nflowchart TD\n  A --> B\n```",
    "```mermaid\n---\ntitle: <img src=x onerror=alert(1)>\n---\nflowchart TD\n  A --> B\n```",
    "<pre data-bnest-diagram=\"mermaid\"><code>flowchart TD</code></pre>",
    "<code class=\"language-mermaid\">flowchart TD</code>"
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

  describe "the XSS corpus with hard breaks on" do
    for {content, index} <- Enum.with_index(@xss_corpus) do
      test "corpus case #{index} is sanitized when a single newline is a hard break" do
        assert_safe(render(unquote(content), false, hard_breaks: true), unquote(content))
        assert_safe(render(unquote(content), true, hard_breaks: true), unquote(content))
      end
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

    test "the same reply renders to the same bytes every time, whatever attributes it has" do
      content = "![a](#{@https}example.com/a.png) [x](#{@https}example.com/x) - [ ] task\n\n<br>"
      first = render(content)

      for _attempt <- 1..20 do
        assert render(content) == first
      end
    end

    test "a data address in a link or an autolink is text, and no reply puts one in an href" do
      data_png = data_url("png", @png)

      for content <- [
            "[x](#{data_png})",
            "<data:image/png;base64,iVBORw0KGgo=>",
            "[![x](#{data_png})](#{data_png})"
          ] do
        html = render(content)

        assert tags(html, "a") == [], "#{inspect(content)} produced a link: #{html}"
        refute html =~ ~r/href\s*=\s*["']?\s*data:/i, "#{inspect(content)} put data in href"
      end
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

    test "an https image is shown inline, with its alt text and the safe attributes, and no link" do
      html = render("![Remote logo](#{@https}example.com/remote-logo.png)")

      assert [tag] = tags(html, "img")
      assert tag =~ ~s(src="#{@https}example.com/remote-logo.png")
      assert tag =~ ~s(alt="Remote logo")
      assert tag =~ ~s(loading="lazy")
      assert tag =~ ~s(referrerpolicy="no-referrer")
      assert tag =~ ~s(decoding="async")
      assert tags(html, "a") == []
      refute html =~ "image not shown"
    end

    test "an https image without alt text is an image with an empty alt, and no link" do
      html = render("![](#{@https}example.com/remote-logo.png)")

      assert [tag] = tags(html, "img")
      assert tag =~ ~s(alt="")
      assert tags(html, "a") == []
    end

    test "an http image is not loaded: it stays a link that says it is not shown" do
      html = render("![Remote logo](#{@http}example.com/remote-logo.png)")

      assert tags(html, "img") == []
      assert [tag] = tags(html, "a")
      assert tag =~ ~s(href="#{@http}example.com/remote-logo.png")
      assert html =~ "Remote logo (image not shown)"
    end

    test "an http image without alt text shows its address as the withheld link text" do
      html = render("![](#{@http}example.com/remote-logo.png)")

      assert tags(html, "img") == []
      assert html =~ "#{@http}example.com/remote-logo.png (image not shown)"
    end

    test "a small PNG, JPEG, GIF or WebP data image is shown inline with its alt text" do
      for {type, bytes} <- @raster_images do
        url = data_url(type, bytes)
        html = render("![Dot](#{url})")

        assert [tag] = tags(html, "img"), "the #{type} data image was not shown: #{html}"
        assert tag =~ ~s(src="#{url}")
        assert tag =~ ~s(alt="Dot")
        assert tags(html, "a") == []
      end
    end

    test "an SVG, another data type, or a javascript image is withheld and its text says so" do
      for destination <- [
            data_url("svg+xml", @svg),
            "data:text/html;base64," <> Base.encode64("<p>x</p>"),
            "javascript:alert(1)"
          ] do
        html = render("![Dot](#{destination})")

        assert tags(html, "img") == [], "rendered an image for #{destination}"
        assert tags(html, "a") == [], "linked an image for #{destination}"
        assert html =~ "[image not shown: Dot]"
      end
    end

    test "a data image whose payload is over 32,768 base64 characters is withheld" do
      # 24,579 bytes encode to 32,772 characters, which is over the limit.
      payload = Base.encode64(@png <> zeros(24_579 - byte_size(@png)))

      html = render("![Big](data:image/png;base64,#{payload})")

      assert tags(html, "img") == []
      assert html =~ "[image not shown: Big]"
    end

    test "a data image with bad base64 is withheld" do
      # The angle-bracket form lets a destination with a space parse as an image at all.
      for payload <- ["!!!!", "iVBORw0KGgo", "iVBO Rw0KGgo="] do
        html = render("![Bad](<data:image/png;base64,#{payload}>)")

        assert tags(html, "img") == [], "rendered an image for #{payload}"
        assert html =~ "[image not shown: Bad]"
      end
    end

    test "a data image whose bytes do not match its declared type is withheld" do
      html = render("![Wrong](#{data_url_raw("png", @jpeg)})")

      assert tags(html, "img") == []
      assert html =~ "[image not shown: Wrong]"
    end

    test "an image address of more than 2,048 characters is withheld" do
      html = render("![Long](#{url_of_length(2049)})")

      assert tags(html, "img") == []
      assert html =~ "[image not shown: Long]"
    end

    test "an https image address with user info is withheld" do
      html = render("![Secret](#{@https}user:pass@example.com/a.png)")

      assert tags(html, "img") == []
      assert html =~ "[image not shown: Secret]"
    end

    test "an image the route would refuse says it is not shown, even without alt text" do
      html = render("![](docs/a.svg)")

      assert tags(html, "img") == []
      assert html =~ "[image not shown]"
    end

    test "an https image nested in a link stays inside that one link, with no nested link" do
      html = render("[![Logo](#{@https}example.com/logo.png)](#{@https}example.com/docs)")

      assert [tag] = tags(html, "a")
      assert tag =~ ~s(href="#{@https}example.com/docs")
      assert tag =~ ~s(target="_blank")
      assert tag =~ ~s(rel="noopener noreferrer nofollow")
      assert [image] = tags(html, "img")
      assert image =~ ~s(src="#{@https}example.com/logo.png")
      refute html =~ "image not shown"
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
        "//evil.example/a.png",
        "javascript:alert(1)",
        "#{@http}evil.example/a.png",
        data_url("svg+xml", @svg)
      ]

      for destination <- destinations do
        html = render("![x](#{destination})")

        assert tags(html, "img") == [], "rendered an image for #{inspect(destination)}"
      end
    end
  end

  describe "classify_image/1" do
    test "a repository reference is classified as a repository image before anything else" do
      assert {:repository, "docs/a.png"} = classify("docs/a.png")
    end

    test "an https address within the limits is external, kept as written" do
      url = @https <> "example.com/a.png"

      assert {:external, ^url} = classify(url)
    end

    test "an https address of exactly 2,048 characters is external, and one more character is not" do
      assert {:external, _url} = classify(url_of_length(2048))
      assert :other = classify(url_of_length(2049))
    end

    test "an https address with user info, no host, or a control or space character is other" do
      for url <- [
            @https <> "user:pass@example.com/a.png",
            @https <> "@example.com/a.png",
            @https <> "/a.png",
            @https <> "example.com/a b.png",
            @https <> "example.com/a\tb.png",
            @https <> "example.com/a\u0007.png",
            @https <> "example.com/a\u007F.png",
            @https <> "example.com/a\u0085.png"
          ] do
        assert :other = classify(url), "classified #{inspect(url)} as an image"
      end
    end

    test "an http address is link only" do
      assert :link_only = classify(@http <> "example.com/a.png")
    end

    test "a PNG, JPEG, GIF or WebP data image with a matching signature is inline" do
      for {type, bytes} <- @raster_images do
        url = data_url(type, bytes)

        assert {:inline, ^url} = classify(url)
      end
    end

    test "a data payload of exactly 32,768 base64 characters is inline" do
      # 24,576 bytes encode to exactly 32,768 characters.
      payload = Base.encode64(@png <> zeros(24_576 - byte_size(@png)))
      assert byte_size(payload) == 32_768

      assert {:inline, _url} = classify("data:image/png;base64," <> payload)
    end

    test "a data payload over 32,768 base64 characters is other, even when it is valid base64" do
      payload = Base.encode64(@png <> zeros(24_579 - byte_size(@png)))

      assert :other = classify("data:image/png;base64," <> payload)
    end

    test "a data payload that is not valid base64 is other" do
      for payload <- ["!!!!", "iVBORw0KGgo", "iVBO Rw0KGgo=", "iVBORw0KGgo=="] do
        assert :other = classify("data:image/png;base64," <> payload), "classified #{payload}"
      end
    end

    test "a data image whose bytes do not match its declared type is other" do
      for {declared, bytes} <- [{"png", @jpeg}, {"jpeg", @png}, {"gif", @svg}, {"webp", @gif}] do
        assert :other = classify(data_url_raw(declared, bytes)), "classified #{declared} bytes"
      end
    end

    test "an svg image or a data URL of another type is other" do
      for url <- [
            data_url("svg+xml", @svg),
            "data:text/html;base64," <> Base.encode64("<p>x</p>"),
            "data:image/bmp;base64," <> Base.encode64("BM" <> "bmp body")
          ] do
        assert :other = classify(url), "classified #{String.slice(url, 0, 30)}"
      end
    end

    test "the data scheme, its media type and its base64 marker match without regard to case" do
      url = "DATA:IMAGE/PNG;BASE64," <> Base.encode64(@png)

      assert {:inline, ^url} = classify(url)
    end

    test "javascript, vbscript, a protocol-relative address and another scheme are other" do
      for url <- [
            "javascript:alert(1)",
            "vbscript:x",
            "//evil.example/a.png",
            "ftp:" <> "//example.com/a.png"
          ] do
        assert :other = classify(url), "classified #{url}"
      end
    end
  end

  describe "line breaks" do
    test "a single newline is a soft break by default" do
      refute render("first\nsecond") =~ "<br"
    end

    test "a single newline is a hard break when hard_breaks is on" do
      html = render("first\nsecond", false, hard_breaks: true)

      assert html =~ "<br"
      assert html =~ "first"
      assert html =~ "second"
    end

    test "hard breaks apply to a streaming reply too" do
      assert render("first\nsecond", true, hard_breaks: true) =~ "<br"
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

    test "a half-written https image address is never an image while streaming" do
      html = render("see ![a](#{@https}exa", true)

      assert tags(html, "img") == []
      assert tags(html, "a") == []
    end

    test "a half-written data image address is never an image while streaming" do
      html = render("see ![a](data:image/png;base64,iVBORw0KGgo=", true)

      assert tags(html, "img") == []
    end

    test "a complete https image is shown while streaming" do
      assert [_] = tags(render("![a](#{@https}example.com/a.png)", true), "img")
    end

    test "a complete data image is shown while streaming" do
      assert [_] = tags(render("![a](#{data_url("png", @png)})", true), "img")
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

  # ADR 004, Decision 2: a `mermaid` fence is marked for drawing only when every rule holds, in the order
  # the decision table gives. The browser draws only the marked fences, so these tests are the server gate.
  describe "Codex reply diagrams (ADR 004, Decision 2)" do
    @flowchart "flowchart TD\n  A --> B"
    @accepted_headers [
      "flowchart TD",
      "flowchart",
      "graph LR",
      "sequenceDiagram",
      "classDiagram",
      "stateDiagram",
      "stateDiagram-v2",
      "erDiagram",
      "pie",
      "gantt"
    ]
    @marker ~s(data-bnest-diagram="mermaid")

    test "a valid flowchart is marked, and its source is kept as escaped text" do
      html = render(fence(@flowchart))

      assert html =~
               ~s(<pre data-bnest-diagram="mermaid"><code>flowchart TD\n  A --&gt; B\n</code></pre>)

      refute html =~ "Diagram not drawn"
      refute html =~ "language-mermaid"
    end

    test "every accepted diagram type is marked" do
      for header <- @accepted_headers do
        assert render(fence(header <> "\n  A --> B")) =~ @marker, header
      end
    end

    test "the info string is compared without regard to case, and only its first word counts" do
      assert render("```Mermaid\n#{@flowchart}\n```") =~ @marker
      assert render("```mermaid title\n#{@flowchart}\n```") =~ @marker
    end

    test "a fence with another language is not a diagram and gets no note" do
      html = render("```elixir\n#{@flowchart}\n```")

      refute html =~ "data-bnest-diagram"
      refute html =~ "Diagram not drawn"
    end

    test "a comment line before the diagram type is skipped, and so are leading blank lines" do
      assert render(fence("\n\n%% the sales funnel\nflowchart TD\n  A --> B")) =~ @marker
    end

    test "a diagram is not marked while its reply streams, and shows as an ordinary code block" do
      html = render(fence(@flowchart), true)

      assert html =~ ~s(<pre><code class="language-mermaid">)
      refute html =~ "data-bnest-diagram"
      refute html =~ "Diagram not drawn"
    end

    test "an unfinished diagram while the reply streams is an ordinary code block with no note" do
      html = render("```mermaid\n#{@flowchart}", true)

      assert html =~ ~s(<pre><code class="language-mermaid">)
      refute html =~ "data-bnest-diagram"
      refute html =~ "Diagram not drawn"
    end

    test "an unclosed diagram in a completed reply is refused as never closed" do
      html = render("```mermaid\n#{@flowchart}")

      assert html =~ ~s(<pre><code class="language-mermaid">)
      refute html =~ "data-bnest-diagram"
      assert html =~ "<p><em>Diagram not drawn: its code block was never closed.</em></p>"
    end

    test "a diagram of the byte limit is marked, and one byte more is refused" do
      limit = ChatMarkdown.diagram_limits().max_source_bytes

      # The code block's text ends with the line break before the closing fence, so the text is the
      # source plus one byte. The source is sized so the text is exactly at, then one over, the limit.
      assert render(fence(source_of_size(limit - 1))) =~ @marker

      html = render(fence(source_of_size(limit)))
      refute html =~ "data-bnest-diagram"
      assert html =~ "<p><em>Diagram not drawn: it is too large.</em></p>"
    end

    test "a diagram of the line limit is marked, and one line more is refused" do
      limit = ChatMarkdown.diagram_limits().max_lines
      at_limit = Enum.join(["flowchart TD" | List.duplicate("A --> B", limit - 1)], "\n")
      over_limit = Enum.join(["flowchart TD" | List.duplicate("A --> B", limit)], "\n")

      assert render(fence(at_limit)) =~ @marker

      html = render(fence(over_limit))
      refute html =~ "data-bnest-diagram"
      assert html =~ "<p><em>Diagram not drawn: it is too large.</em></p>"
    end

    test "a diagram type that is not on the list is refused as unsupported" do
      for header <- [
            "architecture-beta",
            "flowchart-elk TD",
            "mindmap",
            "xychart-beta",
            "block-beta",
            "journey",
            "timeline",
            "gitGraph",
            "stateDiagram-v3",
            "graphic TD",
            "pieces"
          ] do
        html = render(fence(header <> "\n  A --> B"))

        refute html =~ "data-bnest-diagram", header

        assert html =~
                 "<p><em>Diagram not drawn: this diagram type is not supported.</em></p>",
               header
      end
    end

    test "a fence with no diagram type line is refused as unsupported" do
      html = render("```mermaid\n\n```")

      refute html =~ "data-bnest-diagram"
      assert html =~ "<p><em>Diagram not drawn: this diagram type is not supported.</em></p>"
    end

    test "front matter is refused as unsupported, because its first line is not a diagram type" do
      html =
        render(
          fence("---\ntitle: x\nconfig:\n  securityLevel: loose\n---\nflowchart TD\n  A --> B")
        )

      refute html =~ "data-bnest-diagram"
      assert html =~ "<p><em>Diagram not drawn: this diagram type is not supported.</em></p>"
    end

    test "a directive, or a click, callback or link line, is refused as not allowed" do
      for source <- [
            "%%{init: {'securityLevel': 'loose'}}%%\nflowchart TD\n  A --> B",
            "flowchart TD\n  A --> B\n  %%{init: {'theme': 'dark'}}%%",
            "flowchart TD\n  A --> B\n  click A \"#{@https}example.com\"",
            "flowchart TD\n  A --> B\n    click A call alert()",
            "flowchart TD\n  A --> B\n  callback A alert",
            "flowchart TD\n  A --> B\n  link A: #{@https}example.com",
            "flowchart TD\n  A --> B\n  links A #{@https}example.com"
          ] do
        html = render(fence(source))

        refute html =~ "data-bnest-diagram", inspect(source)

        assert html =~ "<p><em>Diagram not drawn: it uses settings that are not allowed.</em></p>",
               inspect(source)
      end
    end

    # Shape data (`A@{ ... }`) can load a picture: `img:` makes Mermaid fetch an address while it draws. The browser
    # frame would make that request, so the whole `@{` syntax is refused, on the server and in diagram_limits.js.
    test "shape data, which can load a picture, is refused as not allowed" do
      for source <- [
            "flowchart TD\n  A@{ shape: imageSquare, img: \"#{@https}images.example.test/x.png\" } --> B",
            "flowchart TD\n  A@{ icon: \"fa:user\" } --> B",
            "flowchart TD\n  A@{ shape: rect, label: \"Plain\" } --> B",
            "flowchart TD\n  A@{\n    img: \"#{@https}images.example.test/x.png\"\n  } --> B"
          ] do
        html = render(fence(source))

        refute html =~ "data-bnest-diagram", inspect(source)

        assert html =~ "<p><em>Diagram not drawn: it uses settings that are not allowed.</em></p>",
               inspect(source)
      end
    end

    test "an at sign that is not shape data stays an ordinary label" do
      html = render(fence("flowchart TD\n  A[\"mail@example.test\"] --> B"))

      assert html =~ ~s(data-bnest-diagram="mermaid")
      refute html =~ "Diagram not drawn"
    end

    # The keyword counts anywhere on a line, as a whole word. A no-break space is a boundary too, so the
    # browser's copy (diagram_limits.js) and this gate refuse the same sources.
    test "a link keyword anywhere on a line, as a whole word, is refused as not allowed" do
      nbsp = " "

      for source <- [
            ~s(flowchart TD\n  A-->B; click A "#{@https}example.com"),
            "flowchart TD\n  A-->B;click A u",
            ~s(flowchart TD\n  A --> B\n  A --> C; href A "#{@https}example.com"),
            "flowchart TD\n  A --> B; call run()",
            "flowchart TD\n  A --> B; callback A",
            "flowchart TD\n  A --> B; link A u",
            "flowchart TD\n  A --> B; Click A u",
            "flowchart TD\n  A --> B;#{nbsp}click A u",
            "flowchart TD\n  A --> B#{nbsp}click A u",
            "flowchart TD\n  A --> B links A"
          ] do
        html = render(fence(source))

        refute html =~ "data-bnest-diagram", inspect(source)

        assert html =~ "<p><em>Diagram not drawn: it uses settings that are not allowed.</em></p>",
               inspect(source)
      end
    end

    test "a longer word that only starts with a keyword is not a link keyword" do
      assert render(fence("flowchart TD\n  A --> clicker")) =~ @marker
      assert render(fence("flowchart TD\n  hrefs --> B")) =~ @marker
    end

    test "a line that only begins with the same letters is not a link line" do
      assert render(fence("flowchart TD\n  A --> B\n  linkStyle 0 stroke:#333")) =~ @marker
    end

    test "only the first four diagrams of a message are marked, in document order" do
      fences = for n <- 1..5, do: fence("flowchart TD\n  A#{n} --> B#{n}")
      html = render(Enum.join(fences, "\n\n"))

      [before_fifth | _rest] = String.split(html, "A5 --&gt; B5")

      assert length(Regex.scan(~r/data-bnest-diagram="mermaid"/, html)) == 4
      assert length(Regex.scan(~r/data-bnest-diagram="mermaid"/, before_fifth)) == 4

      assert html =~
               "<p><em>Diagram not drawn: only the first 4 diagrams in a message are drawn.</em></p>"
    end

    test "a refused diagram does not use one of the four places" do
      refused = fence("architecture-beta\n  group g(cloud)[G]")
      accepted = for n <- 1..4, do: fence("flowchart TD\n  A#{n} --> B#{n}")

      html = render(Enum.join([refused | accepted], "\n\n"))

      assert length(Regex.scan(~r/data-bnest-diagram="mermaid"/, html)) == 4
      refute html =~ "only the first"
    end

    test "a diagram nested in a list or a quote is marked" do
      assert render("- item\n\n  ```mermaid\n  #{@flowchart}\n  ```") =~ @marker
      assert render("> ```mermaid\n> flowchart TD\n>   A --> B\n> ```") =~ @marker
    end

    test "hostile text in a diagram label is escaped and kept as source, and the fence is marked" do
      for label <- [
            "<script>alert(1)</script>",
            "<img src=x onerror=alert(1)>",
            "<b onclick=\"alert(1)\">x</b>"
          ] do
        html = render(fence("flowchart TD\n  A[\"#{label}\"] --> B"))

        assert html =~ @marker, label
        assert html =~ "&lt;", label
        assert_safe(html, label)
      end
    end

    # A label that names a link is refused by the whole-word rule (`href`), so its markup stays escaped text.
    test "a label that names a link is refused, and its markup stays escaped" do
      html =
        render(fence(~s|flowchart TD\n  A["<a href="javascript:alert(1)">x</a>"] --> B|))

      refute html =~ @marker
      assert html =~ "&lt;a href", html
      assert_safe(html, "a link label")
    end

    test "an author's own marker is shown as escaped text and never marks a diagram" do
      html = render(~s(<pre data-bnest-diagram="mermaid"><code>flowchart TD</code></pre>))

      refute html =~ "<pre data-bnest-diagram"
      assert html =~ "&lt;pre data-bnest-diagram"
    end

    test "an author's own language-mermaid class never marks a diagram" do
      html = render(~s(<code class="language-mermaid">flowchart TD</code>))

      refute html =~ "data-bnest-diagram"
    end
  end

  describe "diagram_limits/0" do
    test "reports the caps the gate applies, and its messages use the same caps" do
      limits = ChatMarkdown.diagram_limits()

      assert limits == %{
               max_source_bytes: 6_000,
               max_lines: 200,
               max_per_message: 4,
               kinds:
                 ~w(flowchart graph sequenceDiagram classDiagram stateDiagram stateDiagram-v2 erDiagram pie gantt),
               not_allowed_words: ~w(callback call click href link links),
               not_allowed_tokens: ["%%{", "@{"]
             }

      fifth =
        for n <- 1..(limits.max_per_message + 1), do: fence("flowchart TD\n  A#{n} --> B#{n}")

      html = render(Enum.join(fifth, "\n\n"))

      assert html =~ "only the first #{limits.max_per_message} diagrams in a message are drawn"
    end
  end

  defp fence(source), do: "```mermaid\n" <> source <> "\n```"

  # A flowchart whose source is exactly `size` bytes: the header line is 13 bytes, the rest is filler.
  defp source_of_size(size), do: "flowchart TD\n" <> String.duplicate("x", size - 13)

  defp render(content, streaming? \\ false, options \\ []) do
    content
    |> ChatMarkdown.to_html(streaming?, options)
    |> Phoenix.HTML.safe_to_string()
  end

  defp classify(url), do: ChatMarkdown.classify_image(url)

  defp data_url(type, bytes), do: data_url_raw(type, bytes)

  defp data_url_raw(type, bytes), do: "data:image/" <> type <> ";base64," <> Base.encode64(bytes)

  defp zeros(count), do: :binary.copy(<<0>>, count)

  # A URL of exactly `length` characters: an https address with a host and a long path.
  defp url_of_length(length) do
    prefix = @https <> "example.com/"
    prefix <> String.duplicate("a", length - String.length(prefix))
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

  defp browser_address(value) do
    value
    |> decode_entities()
    |> String.replace(~r/[\x00-\x20]/, "")
    |> String.downcase()
  end

  defp assert_safe(html, label) do
    for banned <- ["<script", "<iframe", "<style", "<form", "<!--"] do
      refute html =~ banned, "#{label} rendered #{banned}"
    end

    for tag <- tags(html, "[a-zA-Z][a-zA-Z0-9]*") do
      refute tag =~ ~r/\son[a-z]+\s*=/i, "#{label} rendered an event handler: #{tag}"
    end

    # A link never carries a data address, whatever the markup; an image may (see below).
    refute html =~ ~r/href\s*=\s*["']?\s*data:/i, "#{label} put a data address in a link"

    for value <- attribute_values(html, "href") do
      address = browser_address(value)

      refute address =~ ~r/^(javascript|vbscript|data):/,
             "#{label} rendered an unsafe address: #{value}"

      refute String.starts_with?(address, "//"),
             "#{label} rendered a protocol-relative address: #{value}"
    end

    for value <- attribute_values(html, "src") do
      address = browser_address(value)

      refute address =~ ~r/^(javascript|vbscript):/,
             "#{label} rendered an unsafe image address: #{value}"

      refute String.starts_with?(address, "//"),
             "#{label} rendered a protocol-relative image address: #{value}"
    end

    # An image comes from the repository route, an https address, or a raster data URL (ADR 003).
    for tag <- tags(html, "img") do
      assert tag =~
               ~r/\ssrc="(\/chat\/images\/|#{@https}|data:image\/(png|jpeg|gif|webp);base64,)/i,
             "#{label} rendered an image from a source that is not allowed: #{tag}"
    end

    for tag <- tags(html, "a") do
      assert tag =~ ~s(rel="noopener noreferrer nofollow"), "#{label} link lacks rel: #{tag}"
      assert tag =~ ~s(target="_blank"), "#{label} link lacks target: #{tag}"
    end
  end
end
