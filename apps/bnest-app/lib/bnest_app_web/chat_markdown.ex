defmodule BnestAppWeb.ChatMarkdown do
  @moduledoc """
  Renders a Codex reply, or a Family Chat message, as sanitized GitHub-flavoured Markdown (ADR 002,
  Decision 1; ADR 003, Decisions 1 and 2).

  Four layers keep the output safe. Raw HTML is escaped, so it shows as text. An AST step gates
  every destination. An image goes through `classify_image/1`, first match wins: a repository image
  becomes a route URL, using the rules the route applies (`BnestApp.CodexChat.Domain.RepositoryImage`);
  an `https` image becomes an inline `<img>` when its address is at most 2,048 characters, has a host,
  and has no user info and no control or space character; a PNG, JPEG, GIF or WebP `data:` image
  becomes an inline `<img>` when its base64 payload is at most 32,768 characters, is valid base64, and
  decodes to bytes whose signature matches the declared type; an `http` image becomes a link whose text
  says it is not shown, and is never loaded; any other image becomes its alt text in a note that says it
  is not shown. A link whose scheme is not http, https or mailto becomes its text. The sanitizer allows
  only the tags and attributes a reply needs, and sets `target` and `rel` on links and the loading
  attributes on images.

  A reply still streaming closes its unfinished syntax, and shows an image only once its closing
  parenthesis has arrived, so a half-written address never becomes an `<img>`. The `:hard_breaks` option
  keeps a single newline as a line break. A parse that fails, runs past its time budget, or meets invalid
  UTF-8 shows the escaped reply in a pre-wrapped paragraph, so the text never disappears and is never
  unsafe.

  A fence tagged `mermaid` is marked for drawing only when the reply is complete and the fence passes
  the caps and the rules `diagram_limits/0` reports (ADR 004, Decision 2). A marked fence is a `pre`
  with the `data-bnest-diagram="mermaid"` attribute and its source as escaped text; a refused one stays
  an ordinary code block with a note that says why. The browser draws only the marked fences.
  """

  alias BnestApp.CodexChat.Domain.RepositoryImage
  alias MDEx.{CodeBlock, Image, Link, Raw, Text}

  @default_parse_time_ms 250
  @image_route "/chat/images/"
  @link_schemes ~w(http https mailto)
  # `data` is allowed in the sanitizer only for image sources. Ammonia cannot scope a scheme to a tag,
  # so a link never reaches it: the link gate turns any link outside @link_schemes into text, and raw
  # HTML is escaped before it is parsed.
  @sanitize_schemes ~w(http https mailto data)
  @max_https_length 2_048
  @max_data_payload 32_768

  # ADR 004, Decision 2. The caps are read through `diagram_limits/0`, so a test and the browser's
  # client copy can check one source.
  @max_diagram_source_bytes 6_000
  @max_diagram_lines 200
  @max_diagrams_per_message 4
  @diagram_kinds ~w(flowchart graph sequenceDiagram classDiagram stateDiagram stateDiagram-v2 erDiagram pie gantt)
  # A directive (`%%{`) and shape data (`@{`, which can name a picture with `img:` that Mermaid fetches while it
  # draws) are refused anywhere in the source. The words are whole words, matched without case.
  @not_allowed_words ~w(callback call click href link links)
  @not_allowed_tokens ["%%{", "@{"]

  @extension [strikethrough: true, table: true, tasklist: true, autolink: true]
  @render [escape: true]
  @auto_close [links: :text, images: :text]

  @tags ~w(a blockquote br code del em h1 h2 h3 h4 h5 h6 hr img input li ol p pre strong table tbody td th thead tr ul)
  @tag_attributes %{
    "a" => ~w(href),
    "code" => ~w(class),
    "img" => ~w(src alt),
    "input" => ~w(type checked disabled),
    "ol" => ~w(start),
    "td" => ~w(align),
    "th" => ~w(align)
  }
  @sanitize [
    tags: @tags,
    tag_attributes: @tag_attributes,
    # The diagram marker is an attribute with one value and is not in `@tag_attributes`, so no other
    # `pre` attribute, and no other value of this one, survives (ADR 004, Decision 2).
    tag_attribute_values: %{
      "input" => %{"type" => ["checkbox"]},
      "pre" => %{"data-bnest-diagram" => ["mermaid"]}
    },
    set_tag_attribute_values: %{
      "a" => %{"target" => "_blank"},
      "img" => %{"loading" => "lazy", "referrerpolicy" => "no-referrer", "decoding" => "async"}
    },
    link_rel: "noopener noreferrer nofollow",
    url_schemes: @sanitize_schemes
  ]

  @doc """
  Renders `content` as safe HTML. `streaming?` closes unfinished syntax, as a reply still being
  written needs. Options:

    * `:parse_time_ms` is the parse budget, 250 ms by default; a parse that exceeds it shows the
      escaped reply.
    * `:hard_breaks` (default `false`) makes a single newline a line break. Family Chat uses it,
      because people type a line break on purpose; the Codex chat keeps standard Markdown.
  """
  @spec to_html(String.t(), boolean(), keyword()) :: Phoenix.HTML.safe()
  def to_html(content, streaming?, options \\ [])
      when is_binary(content) and is_boolean(streaming?) do
    budget = Keyword.get(options, :parse_time_ms, @default_parse_time_ms)
    hard_breaks? = Keyword.get(options, :hard_breaks, false)

    case render(content, streaming?, budget, hard_breaks?) do
      {:ok, html} -> Phoenix.HTML.raw(sorted_attributes(html))
      {:error, _reason} -> escaped_reply(content)
    end
  end

  @doc """
  Classifies an image destination. The first matching row wins (ADR 003, Decision 1):

    * `{:repository, path}`: a repository image that `RepositoryImage.reference/1` accepts; the
      route URL is built from `path`.
    * `{:external, url}`: an `https` address that may be shown inline, as written.
    * `{:inline, url}`: a PNG, JPEG, GIF or WebP `data:` image that may be shown inline, as written.
    * `:link_only`: an `http` address, shown as a link and never loaded.
    * `:other`: anything else, shown as text.
  """
  @spec classify_image(String.t()) ::
          {:repository, String.t()}
          | {:external, String.t()}
          | {:inline, String.t()}
          | :link_only
          | :other
  def classify_image(url) do
    # The regular expressions below need valid UTF-8, so bytes that are not UTF-8 are refused first.
    if String.valid?(url), do: classify_valid_image(url), else: :other
  end

  @doc """
  The caps and the accepted diagram types for a `mermaid` fence (ADR 004, Decision 2). The browser's
  client copy is checked against this map, so the numbers live in one place:

    * `max_source_bytes`: the most bytes of diagram source;
    * `max_lines`: the most lines of diagram source;
    * `max_per_message`: how many diagrams a reply may draw, in document order;
    * `kinds`: the first words of a diagram type line the gate accepts;
    * `not_allowed_words`: the words a diagram may not contain, as whole words;
    * `not_allowed_tokens`: the character sequences a diagram may not contain.
  """
  @spec diagram_limits() :: %{
          max_source_bytes: pos_integer(),
          max_lines: pos_integer(),
          max_per_message: pos_integer(),
          kinds: [String.t()],
          not_allowed_words: [String.t()],
          not_allowed_tokens: [String.t()]
        }
  def diagram_limits do
    %{
      max_source_bytes: @max_diagram_source_bytes,
      max_lines: @max_diagram_lines,
      max_per_message: @max_diagrams_per_message,
      kinds: @diagram_kinds,
      not_allowed_words: @not_allowed_words,
      not_allowed_tokens: @not_allowed_tokens
    }
  end

  # The sanitizer writes a tag's attributes in a hash-map order that can change from one call to the
  # next, so the same reply could render to different bytes. The attributes of each tag are sorted by
  # name. Only the order changes: a value is never touched. The sanitizer writes every value in double
  # quotes and escapes a `"` inside one, so a match cannot run past the end of a value.
  defp sorted_attributes(html) do
    Regex.replace(
      ~r/<([a-z][a-z0-9]*)((?:\s+[a-zA-Z][a-zA-Z0-9-]*(?:="[^"]*")?)+)(\s*\/?)>/,
      html,
      fn _whole, name, attributes, close ->
        sorted =
          ~r/\s+[a-zA-Z][a-zA-Z0-9-]*(?:="[^"]*")?/
          |> Regex.scan(attributes)
          |> List.flatten()
          |> Enum.sort_by(&attribute_name/1)

        "<" <> name <> Enum.join(sorted) <> close <> ">"
      end
    )
  end

  defp attribute_name(attribute) do
    attribute |> String.trim_leading() |> String.split("=", parts: 2) |> hd()
  end

  # The native parser raises, instead of returning an error, on bytes that are not UTF-8, so
  # such a reply is refused here and shown escaped.
  defp render(content, streaming?, budget, hard_breaks?) do
    if String.valid?(content) do
      with {:ok, document} <- MDEx.parse_document(content, parse_options(streaming?, budget)) do
        document
        |> gate_destinations(streaming?)
        |> MDEx.to_html(render_options(hard_breaks?))
      end
    else
      {:error, :invalid_utf8}
    end
  end

  defp parse_options(streaming?, budget) do
    options = [extension: @extension, render: @render, budget: [parse_time: budget]]

    if streaming?, do: Keyword.put(options, :auto_close, @auto_close), else: options
  end

  defp render_options(hard_breaks?) do
    render = if hard_breaks?, do: Keyword.put(@render, :hardbreaks, true), else: @render

    [extension: @extension, render: render, sanitize: @sanitize]
  end

  # The traversal visits children before their parent, so a link's text is already gated when
  # the link itself is checked. Its accumulator counts the diagrams drawn so far in document order.
  defp gate_destinations(document, streaming?) do
    {document, _drawn} = MDEx.traverse_and_update(document, 0, &gate(&1, &2, streaming?))
    document
  end

  defp gate(%Image{url: url, nodes: alt} = image, drawn, _streaming?) do
    node =
      case classify_image(url) do
        {:repository, path} -> %{image | url: image_route(path)}
        {:external, _url} -> image
        {:inline, _url} -> image
        :link_only -> link_only(url, alt)
        :other -> withheld_text(alt)
      end

    {node, drawn}
  end

  defp gate(%Link{url: url, nodes: nodes} = link, drawn, _streaming?) do
    {if(scheme_of(url) in @link_schemes, do: link, else: text(nodes)), drawn}
  end

  # A reply still streaming keeps its diagrams as ordinary code blocks: the fence is not complete until
  # the reply is (ADR 004, Decision 2, rule 0).
  defp gate(%CodeBlock{} = block, drawn, streaming?) do
    if streaming?, do: {block, drawn}, else: gate_diagram(block, drawn)
  end

  defp gate(node, drawn, _streaming?), do: {node, drawn}

  # A fence tagged `mermaid` is marked when every rule in `diagram_refusal/2` holds. The first failing
  # rule gives the note. Only an accepted diagram counts toward the message's limit.
  defp gate_diagram(%CodeBlock{info: info, literal: literal} = block, drawn) do
    if mermaid_info?(info) do
      case diagram_refusal(block, drawn) do
        nil -> {diagram_markup(literal), drawn + 1}
        reason -> {refused_diagram_markup(literal, reason), drawn}
      end
    else
      {block, drawn}
    end
  end

  # The rules in the order of ADR 004, Decision 2. A front matter block starts with `---`, which is not a
  # diagram type, so the type rule refuses it before the settings rule is reached.
  defp diagram_refusal(%CodeBlock{closed: false}, _drawn), do: :unfinished

  defp diagram_refusal(%CodeBlock{literal: literal}, drawn) do
    cond do
      too_large?(literal) ->
        :too_large

      not diagram_kind?(literal) ->
        :unsupported

      not_allowed?(literal) ->
        :not_allowed

      drawn >= @max_diagrams_per_message ->
        :too_many

      true ->
        nil
    end
  end

  defp mermaid_info?(info) do
    case String.split(info) do
      [word | _rest] -> String.downcase(word) == "mermaid"
      [] -> false
    end
  end

  defp too_large?(literal) do
    byte_size(literal) > @max_diagram_source_bytes or line_count(literal) > @max_diagram_lines
  end

  defp line_count(literal) do
    literal |> String.trim_trailing("\n") |> String.split("\n") |> length()
  end

  # The first line that is neither blank nor a `%%` comment names the diagram type. The type must be one
  # of the listed words, as a whole word: `flowchart-elk` is not `flowchart`.
  defp diagram_kind?(literal) do
    case diagram_type_line(literal) do
      nil -> false
      line -> hd(String.split(line)) in @diagram_kinds
    end
  end

  defp diagram_type_line(literal) do
    literal
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 != "" and not String.starts_with?(&1, "%%")))
  end

  # A token (`%%{`, `@{`) anywhere, or a listed word anywhere in the source as a whole word, may link, run code or
  # fetch a picture. A word boundary is any character that is not a letter, a digit or an underscore, so a no-break
  # space ends a word too; the browser's copy (diagram_limits.js) builds the same pattern from the same lists.
  # `linkStyle` is styling, not a link, so it passes.
  defp not_allowed?(literal) do
    Enum.any?(@not_allowed_tokens, &String.contains?(literal, &1)) or
      Regex.match?(not_allowed_word_pattern(), literal)
  end

  defp not_allowed_word_pattern do
    alternatives = Enum.map_join(@not_allowed_words, "|", &Regex.escape/1)
    Regex.compile!("(?<![\\p{L}\\p{N}_])(?:#{alternatives})(?![\\p{L}\\p{N}_])", "iu")
  end

  # The accepted fence: the marker the browser acts on, then the source as escaped text. The marker is
  # the only thing that makes the browser draw; the source stays visible beside the drawing.
  defp diagram_markup(literal) do
    %Raw{
      literal:
        IO.iodata_to_binary([
          ~s(<pre data-bnest-diagram="mermaid"><code>),
          escape(literal),
          "</code></pre>\n"
        ])
    }
  end

  # The refused fence: the ordinary code block, then a note with the reason. Both use only allowed tags.
  defp refused_diagram_markup(literal, reason) do
    %Raw{
      literal:
        IO.iodata_to_binary([
          ~s(<pre><code class="language-mermaid">),
          escape(literal),
          "</code></pre>\n<p><em>Diagram not drawn: ",
          refusal_note(reason),
          ".</em></p>\n"
        ])
    }
  end

  defp refusal_note(:unfinished), do: "its code block was never closed"
  defp refusal_note(:too_large), do: "it is too large"
  defp refusal_note(:unsupported), do: "this diagram type is not supported"
  defp refusal_note(:not_allowed), do: "it uses settings that are not allowed"

  defp refusal_note(:too_many),
    do: "only the first #{@max_diagrams_per_message} diagrams in a message are drawn"

  defp escape(text) do
    {:safe, escaped} = Phoenix.HTML.html_escape(text)
    escaped
  end

  defp classify_valid_image(url) do
    case repository_path(url) do
      {:ok, path} -> {:repository, path}
      :error -> classify_remote(url)
    end
  end

  defp repository_path(url) do
    with {:ok, decoded} <- decode(url), do: RepositoryImage.reference(decoded)
  end

  defp classify_remote(url) do
    case scheme_of(url) do
      "https" -> if inline_https?(url), do: {:external, url}, else: :other
      "http" -> :link_only
      "data" -> if inline_data?(url), do: {:inline, url}, else: :other
      _other -> :other
    end
  end

  # An https image is loaded by the viewer's browser, so the address must be a plain absolute one: at
  # most 2,048 characters, a host, no user info (a credential would travel in the URL), and no control
  # or space character. URI.parse does not report an empty user info such as `https://@host`, so the
  # authority text is checked for `@` directly.
  defp inline_https?(url) do
    String.length(url) <= @max_https_length and
      not Regex.match?(~r/[\x{00}-\x{20}\x{7F}-\x{9F}]/u, url) and
      not String.contains?(authority(url), "@") and
      host?(URI.parse(url))
  end

  # The text between `//` and the path. A browser reads a backslash as a slash in an https address,
  # so a backslash ends the authority too.
  defp authority(url) do
    url
    |> String.split("//", parts: 2)
    |> List.last()
    |> String.split(["/", "\\", "?", "#"], parts: 2)
    |> hd()
  end

  defp host?(%URI{host: host}), do: is_binary(host) and host != ""

  # The payload length is checked before anything is decoded. The declared type must match the
  # signature of the decoded bytes, so a wrongly labelled file is never shown.
  defp inline_data?(url) do
    pattern = ~r/\Adata:image\/(png|jpeg|gif|webp);base64,(.*)\z/i

    case Regex.run(pattern, url, capture: :all_but_first) do
      [type, payload] ->
        byte_size(payload) <= @max_data_payload and signature_matches?(type, payload)

      nil ->
        false
    end
  end

  defp signature_matches?(type, payload) do
    with {:ok, bytes} <- Base.decode64(payload),
         {:ok, media_type} <- RepositoryImage.signature(bytes) do
      media_type == "image/" <> String.downcase(type)
    else
      _invalid -> false
    end
  end

  # An http image is shown as a link to its address and is never requested by the browser, because a
  # page served over https would block or upgrade it. The link text says the image is not shown; with
  # no alt text, the address stands in for it.
  defp link_only(href, alt) do
    label = alt |> plain_text() |> String.trim()
    label = if label == "", do: href, else: label
    %Link{url: href, nodes: [%Text{literal: label <> " (image not shown)"}]}
  end

  # An image the reply may not show keeps its alt text inside a note that says it is not shown.
  defp withheld_text(alt) do
    case alt |> plain_text() |> String.trim() do
      "" -> %Text{literal: "[image not shown]"}
      label -> %Text{literal: "[image not shown: " <> label <> "]"}
    end
  end

  # Each segment is encoded on its own, so the slashes stay literal and the route splits them.
  defp image_route(path) do
    @image_route <> Enum.map_join(String.split(path, "/"), "/", &encode_segment/1)
  end

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  # The destination is percent-decoded once, as the route receives it. A malformed escape, or
  # decoded text that is not UTF-8, is refused.
  defp decode(url) do
    if Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, url) do
      :error
    else
      decoded = URI.decode(url)
      if String.valid?(decoded), do: {:ok, decoded}, else: :error
    end
  end

  # Browsers ignore control characters and spaces inside a scheme, so the check ignores them too.
  defp scheme_of(url) do
    normalized = url |> String.replace(~r/[\x00-\x20\x7F]/, "") |> String.downcase()

    case Regex.run(~r/\A([a-z][a-z0-9+.\-]*):/, normalized, capture: :all_but_first) do
      [scheme] -> scheme
      nil -> nil
    end
  end

  defp text(nodes), do: %Text{literal: plain_text(nodes)}

  defp plain_text(nodes), do: Enum.map_join(nodes, &node_text/1)

  defp node_text(%{nodes: nodes}), do: plain_text(nodes)
  defp node_text(%{literal: literal}) when is_binary(literal), do: literal
  # A soft or hard line break has no text of its own; a space keeps the words either side apart.
  defp node_text(_break), do: " "

  # The fallback must be valid UTF-8 too, so bytes that are not UTF-8 are replaced before escaping.
  defp escaped_reply(content) do
    {:safe, escaped} = content |> String.replace_invalid() |> Phoenix.HTML.html_escape()
    {:safe, [~s(<p class="whitespace-pre-wrap">), escaped, "</p>"]}
  end
end
