defmodule BnestAppWeb.ChatMarkdown do
  @moduledoc """
  Renders a Codex reply as sanitized GitHub-flavoured Markdown (ADR 002, Decision 1).

  Four layers keep the output safe. Raw HTML is escaped, so it shows as text. An AST step gates
  every destination: a repository image becomes a route URL, using the same rules the route
  applies (`BnestApp.CodexChat.Domain.RepositoryImage`); an http or https image becomes a link
  whose text says it is not loaded, and is never loaded; any other image becomes its alt text in
  a note that says it is not shown; a link whose scheme is not http, https or mailto becomes its
  text. The sanitizer allows only the tags and attributes a reply
  needs, and sets `target` and `rel` on links and the loading attributes on images.

  A reply still streaming closes its unfinished syntax. A parse that fails, runs past its time
  budget, or meets invalid UTF-8 shows the escaped reply in a pre-wrapped paragraph, so the text
  never disappears and is never unsafe.
  """

  alias BnestApp.CodexChat.Domain.RepositoryImage
  alias MDEx.{Image, Link, Text}

  @default_parse_time_ms 250
  @image_route "/chat/images/"
  @link_schemes ~w(http https mailto)
  @image_schemes ~w(http https)

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
    tag_attribute_values: %{"input" => %{"type" => ["checkbox"]}},
    set_tag_attribute_values: %{
      "a" => %{"target" => "_blank"},
      "img" => %{"loading" => "lazy", "referrerpolicy" => "no-referrer", "decoding" => "async"}
    },
    link_rel: "noopener noreferrer nofollow",
    url_schemes: @link_schemes
  ]

  @doc """
  Renders `content` as safe HTML. `streaming?` closes unfinished syntax, as a reply still being
  written needs. The `:parse_time_ms` option is the parse budget, 250 ms by default; a parse
  that exceeds it shows the escaped reply.
  """
  @spec to_html(String.t(), boolean(), keyword()) :: Phoenix.HTML.safe()
  def to_html(content, streaming?, options \\ [])
      when is_binary(content) and is_boolean(streaming?) do
    budget = Keyword.get(options, :parse_time_ms, @default_parse_time_ms)

    case render(content, streaming?, budget) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      {:error, _reason} -> escaped_reply(content)
    end
  end

  # The native parser raises, instead of returning an error, on bytes that are not UTF-8, so
  # such a reply is refused here and shown escaped.
  defp render(content, streaming?, budget) do
    if String.valid?(content) do
      with {:ok, document} <- MDEx.parse_document(content, parse_options(streaming?, budget)) do
        document
        |> gate_destinations()
        |> MDEx.to_html(render_options())
      end
    else
      {:error, :invalid_utf8}
    end
  end

  defp parse_options(streaming?, budget) do
    options = [extension: @extension, render: @render, budget: [parse_time: budget]]

    if streaming?, do: Keyword.put(options, :auto_close, @auto_close), else: options
  end

  defp render_options, do: [extension: @extension, render: @render, sanitize: @sanitize]

  # The traversal visits children before their parent, so a link's text is already gated when
  # the link itself is checked.
  defp gate_destinations(document), do: MDEx.traverse_and_update(document, &gate/1)

  defp gate(%Image{url: url, nodes: alt} = image) do
    case classify_image(url) do
      {:repository, path} -> %{image | url: image_route(path)}
      {:external, href} -> external_link(href, alt)
      :other -> withheld_text(alt)
    end
  end

  defp gate(%Link{url: url, nodes: nodes} = link) do
    if scheme_of(url) in @link_schemes, do: link, else: text(nodes)
  end

  defp gate(node), do: node

  defp classify_image(url) do
    with {:ok, decoded} <- decode(url),
         {:ok, path} <- RepositoryImage.reference(decoded) do
      {:repository, path}
    else
      _not_a_repository_image ->
        if scheme_of(url) in @image_schemes, do: {:external, url}, else: :other
    end
  end

  # An external image is shown as a link to its address and is never requested by the browser. The
  # link text says the image is not loaded; with no alt text, the address stands in for it.
  defp external_link(href, alt) do
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
