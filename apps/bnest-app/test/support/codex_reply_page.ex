defmodule BnestApp.Test.CodexReplyPage do
  @moduledoc """
  Reads the Codex reply a rendered chat page shows. The unit driver renders the LiveView's
  template and the integration driver renders its live view; both pass the page here as
  LazyHTML, so the two layers check the same output by the same rules.

  Each function reads only what the page holds: an element, its text, its attributes. None of
  them trusts a value the test stored itself.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc "The newest Codex reply on the page. A page with no reply is a failed check."
  def latest_reply(page) do
    case page |> LazyHTML.query("[data-role=assistant-message]") |> Enum.at(-1) do
      nil -> raise "the chat page shows no Codex reply"
      reply -> reply
    end
  end

  def streaming?(reply), do: LazyHTML.attribute(reply, "data-streaming") == ["true"]

  def complete?(reply), do: LazyHTML.attribute(reply, "data-streaming") == ["false"]

  def contains_element?(reply, element), do: reply |> LazyHTML.query(element) |> Enum.any?()

  def contains_element_with_text?(reply, element, text) do
    reply
    |> LazyHTML.query(element)
    |> Enum.any?(&(&1 |> LazyHTML.text() |> String.contains?(text)))
  end

  def shows_text?(reply, text), do: reply |> LazyHTML.text() |> String.contains?(text)

  # The text is on the page and no link holds it, so it is shown as plain text.
  def shows_text_without_link?(reply, text) do
    shows_text?(reply, text) and
      not (reply
           |> LazyHTML.query("a")
           |> Enum.any?(&(&1 |> LazyHTML.text() |> String.contains?(text))))
  end

  def lacks_link_to_address?(reply, prefix) do
    not (reply
         |> LazyHTML.query("a")
         |> LazyHTML.attribute("href")
         |> Enum.any?(&String.starts_with?(&1, prefix)))
  end

  def links_to?(reply, label, address) do
    reply
    |> LazyHTML.query("a")
    |> Enum.any?(fn link ->
      link_label(link) == label and LazyHTML.attribute(link, "href") == [address]
    end)
  end

  # A link opens in a new tab only with the exact target, and a `rel` that drops the opener and
  # the referrer, so the page it opens cannot reach the reply's page.
  def opens_in_new_tab_privately?(reply, label) do
    reply
    |> LazyHTML.query("a")
    |> Enum.any?(fn link ->
      rel = link |> LazyHTML.attribute("rel") |> List.first("") |> String.split()

      link_label(link) == label and LazyHTML.attribute(link, "target") == ["_blank"] and
        "noopener" in rel and "noreferrer" in rel
    end)
  end

  # The repository image the reply shows points at the image route for exactly this path.
  def shows_repository_image?(reply, path) do
    reply
    |> LazyHTML.query("img")
    |> Enum.any?(fn image ->
      case LazyHTML.attribute(image, "src") do
        ["/chat/images/" <> encoded] -> URI.decode(encoded) == path
        _other -> false
      end
    end)
  end

  # The visitor message that holds `message` has its text and nothing the browser would format.
  def unformatted_visitor_message?(page, message) do
    matching = visitor_messages_with(page, message)

    matching != [] and Enum.all?(matching, &plain_content?/1)
  end

  # A visitor message element's text is exactly `text`, which may span line breaks. Nothing the template
  # adds around the typed message counts: the element shows the message and no blank line or indentation.
  def shows_visitor_text?(page, text), do: page |> visitor_messages_exactly(text) |> Enum.any?()

  # The visitor message keeps the line break between `first` and `second`: its text is exactly those two
  # lines joined by one `\n`, and its element preserves white space (`whitespace-pre-wrap`), so the browser
  # draws the break the visitor typed.
  def keeps_visitor_line_break?(page, first, second) do
    page
    |> visitor_messages_exactly(first <> "\n" <> second)
    |> Enum.any?(&pre_wrapped?/1)
  end

  # The reply's task checkboxes: `checked` of them are ticked and `unchecked` are not.
  def task_checkboxes?(reply, checked, unchecked) do
    boxes = LazyHTML.query(reply, "input[type=checkbox]")

    Enum.count(boxes) == checked + unchecked and
      Enum.count(boxes, &(LazyHTML.attribute(&1, "checked") != [])) == checked
  end

  # The structure the browser layout check measures: a table of at least eight columns, task items
  # that hold their text, a link and an image. Layout itself is proved in the browser.
  def lays_out_structure?(reply) do
    task_items = reply |> LazyHTML.query("li") |> Enum.filter(&task_item?/1)

    Enum.count(LazyHTML.query(reply, "table th")) >= 8 and task_items != [] and
      Enum.all?(task_items, &(&1 |> LazyHTML.text() |> String.trim() != "")) and
      contains_element?(reply, "a") and contains_element?(reply, "img")
  end

  # An image the reply shows inline: an `img` with this alt text and a source, and no link around it.
  # The browser decodes it; that a decoded image has a width is proved by the browser layer.
  def shows_inline_image?(reply, alt) do
    linked_alts = reply |> LazyHTML.query("a img") |> Enum.map(&image_alt/1)

    reply
    |> LazyHTML.query("img")
    |> Enum.any?(fn image ->
      image_alt(image) == alt and LazyHTML.attribute(image, "src") != [] and
        alt not in linked_alts
    end)
  end

  # The inline image with this alt text has exactly this source address.
  def loads_inline_image?(reply, alt, address) do
    shows_inline_image?(reply, alt) and
      reply
      |> LazyHTML.query("img")
      |> Enum.any?(&(image_alt(&1) == alt and LazyHTML.attribute(&1, "src") == [address]))
  end

  # The content a phone width must fit: a table of at least eight columns and an image. The unit
  # layer proves that this content is in the reply; the browser layer measures the overflow.
  def holds_wide_content?(reply) do
    Enum.count(LazyHTML.query(reply, "table th")) >= 8 and contains_element?(reply, "img")
  end

  # A diagram the reply keeps as ordinary text: a code block tagged mermaid inside a `pre` that has no
  # drawing marker. The server keeps a diagram this way while the reply streams and when it refuses one.
  def plain_diagram_count(reply) do
    reply
    |> LazyHTML.query("pre:not([data-bnest-diagram]) > code.language-mermaid")
    |> Enum.count()
  end

  # A diagram the server marks for drawing: a `pre` carrying the one marker value the browser acts on.
  def marked_diagram_count(reply) do
    reply
    |> LazyHTML.query(~s(pre[data-bnest-diagram="mermaid"]))
    |> Enum.count()
  end

  defp image_alt(image), do: image |> LazyHTML.attribute("alt") |> List.first()

  defp visitor_messages_with(page, text) do
    page
    |> LazyHTML.query("[data-role=user-message]")
    |> Enum.filter(&(&1 |> LazyHTML.text() |> String.contains?(text)))
  end

  defp visitor_messages_exactly(page, text) do
    page
    |> LazyHTML.query("[data-role=user-message]")
    |> Enum.filter(&(LazyHTML.text(&1) == text))
  end

  # The element's content is text only: no tag sits inside its opening and closing tags.
  defp plain_content?(element) do
    inner =
      element
      |> LazyHTML.to_html()
      |> String.replace(~r/\A<[^>]*>/, "")
      |> String.replace(~r/<\/[^>]*>\z/, "")

    not String.contains?(inner, "<")
  end

  defp pre_wrapped?(element) do
    element
    |> LazyHTML.attribute("class")
    |> List.first("")
    |> String.split()
    |> Enum.member?("whitespace-pre-wrap")
  end

  defp task_item?(item), do: not Enum.empty?(LazyHTML.query(item, "input[type=checkbox]"))

  defp link_label(link), do: link |> LazyHTML.text() |> String.trim()
end
