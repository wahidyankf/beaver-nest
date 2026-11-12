defmodule BnestApp.Test.FamilyChatBodyHtml do
  @moduledoc """
  Reads the `bodyHtml` a Family Chat message carries (ADR 003, Decision 2) for the behaviour bindings.

  Every predicate looks only at the HTML it is given. A `nil` HTML (the response carried no `bodyHtml`)
  is `false`, so an absent field fails a scenario rather than passing it.
  """

  @wrapper_class "message-content markdown-body family-chat-message-body"
  @wrapper_role "family-chat-message-body"

  # A valueless attribute such as LiveView's root marker `phx-r` is allowed: it is inert on this page, and the
  # shared component emits it in every room.
  @attribute ~S/\s+[a-zA-Z][\w-]*(?:="[^"]*")?/

  @doc "True when the HTML is one `div` with the shared Family Chat classes and the body role."
  @spec message_body_element?(String.t() | nil) :: boolean()
  def message_body_element?(nil), do: false

  def message_body_element?(html) when is_binary(html) do
    case Regex.run(~r/\A<div((?:#{@attribute})*)\s*>.*<\/div>\z/su, html, capture: :all_but_first) do
      [attributes] ->
        attrs =
          ~r/([a-zA-Z][\w-]*)(?:="([^"]*)")?/
          |> Regex.scan(attributes, capture: :all_but_first)
          |> Map.new(fn [name | rest] -> {name, List.first(rest)} end)

        attrs["class"] == @wrapper_class and attrs["data-role"] == @wrapper_role

      nil ->
        false
    end
  end

  @doc "True when the HTML contains the fragment."
  @spec contains?(String.t() | nil, String.t()) :: boolean()
  def contains?(nil, _fragment), do: false
  def contains?(html, fragment), do: String.contains?(html, fragment)

  @doc "True when the HTML is present and does not contain the fragment."
  @spec lacks?(String.t() | nil, String.t()) :: boolean()
  def lacks?(nil, _fragment), do: false
  def lacks?(html, fragment), do: not String.contains?(html, fragment)

  @doc """
  True when the HTML shows the image the way the Codex chat decides (ADR 003, Decision 1), for the
  decision named in the feature:

    * `"inline"`: the only image is an `<img>` whose `src` is the address as written.
    * `"link only"`: no `<img>`; the only link goes to the address, and its text says the image is not shown.
    * `"withheld"`: no `<img>`; the text says the image is not shown, and the address appears nowhere.
    * `"repository"`: the only image is an `<img>` whose `src` is the repository route for the path.

  An unknown decision raises, so a typo in a feature cannot pass.
  """
  @spec image_shown?(String.t() | nil, String.t(), String.t()) :: boolean()
  def image_shown?(nil, _decision, _address), do: false

  def image_shown?(html, "inline", address), do: image_sources(html) == [address]

  def image_shown?(html, "repository", path), do: image_sources(html) == ["/chat/images/" <> path]

  def image_shown?(html, "link only", address) do
    image_sources(html) == [] and link_targets(html) == [address] and
      String.contains?(html, "(image not shown)")
  end

  def image_shown?(html, "withheld", address) do
    image_sources(html) == [] and String.contains?(html, "[image not shown: ") and
      not String.contains?(html, address)
  end

  def image_shown?(_html, decision, _address),
    do: raise(ArgumentError, "unknown image decision #{inspect(decision)}")

  # The marked fence the browser draws (ADR 004, Decision 2): the `pre` with the one marker value.
  @diagram_marker ~s(<pre data-bnest-diagram="mermaid"><code>)

  @doc "True when the HTML marks a `mermaid` fence for drawing."
  @spec marks_diagram?(String.t() | nil) :: boolean()
  def marks_diagram?(nil), do: false
  def marks_diagram?(html), do: String.contains?(html, @diagram_marker)

  @doc """
  True when the HTML keeps a `mermaid` fence as an ordinary code block with the server's note (ADR 004,
  Decision 2): the code block carries `language-mermaid`, no marker is present, and the note reads
  `Diagram not drawn: <note>.`. The note is the reason only, as the feature names it.
  """
  @spec keeps_diagram_note?(String.t() | nil, String.t()) :: boolean()
  def keeps_diagram_note?(nil, _note), do: false

  def keeps_diagram_note?(html, note) do
    String.contains?(html, ~s(<pre><code class="language-mermaid">)) and
      not String.contains?(html, "data-bnest-diagram") and
      String.contains?(html, "<p><em>Diagram not drawn: " <> note <> ".</em></p>")
  end

  defp image_sources(html), do: attribute_values(html, ~r/<img\b[^>]*>/, ~r/\ssrc="([^"]*)"/)

  defp link_targets(html), do: attribute_values(html, ~r/<a\b[^>]*>/, ~r/\shref="([^"]*)"/)

  defp attribute_values(html, tag_pattern, attribute_pattern) do
    tag_pattern
    |> Regex.scan(html)
    |> Enum.flat_map(fn [tag] ->
      case Regex.run(attribute_pattern, tag, capture: :all_but_first) do
        [value] -> [value]
        nil -> []
      end
    end)
  end
end
