defmodule BnestAppWeb.ChatComponents do
  @moduledoc """
  The one piece of markup for a message body rendered by `BnestAppWeb.ChatMarkdown` (ADR 003,
  Decision 2). Both chat rooms render Markdown through `markdown_body/1`.

  `markdown_body_html/2` renders the same component to a binary, for a place that needs a string,
  such as a GraphQL field. Both paths produce the same bytes for the same input.
  """

  use Phoenix.Component

  alias BnestAppWeb.ChatMarkdown
  alias Phoenix.HTML.Safe

  attr :content, :string, required: true, doc: "the Markdown source"
  attr :streaming, :boolean, default: false, doc: "true while the reply is still being written"

  attr :hard_breaks, :boolean,
    default: false,
    doc: "true to keep a single newline as a line break"

  attr :class, :any, default: nil, doc: "classes added after `message-content markdown-body`"
  attr :rest, :global, doc: "other HTML attributes for the wrapper element"

  # The HTML is computed first and placed with `{@html}`, so the template holds no whitespace text
  # around the message: the wrapper is exactly `<div ...>` + the rendered reply + `</div>`.
  def markdown_body(assigns) do
    assigns =
      assign(
        assigns,
        :html,
        ChatMarkdown.to_html(assigns.content, assigns.streaming, hard_breaks: assigns.hard_breaks)
      )

    ~H"""
    <div class={["message-content markdown-body", @class]} {@rest}>{@html}</div>
    """
  end

  @doc """
  Renders `markdown_body/1` with `content` to a binary, with the same bytes the component writes.

  `attrs` is a keyword list:

    * `:hard_breaks` and `:streaming` (booleans, default `false`), as on the component.
    * `:class`, classes added after the fixed ones.
    * `:attrs`, the other HTML attributes of the wrapper element, as a map or a keyword list. A
      `:class` key inside `:attrs` joins `:class`, so the wrapper never has two class attributes.

  The wrapper is written here, not by the template engine: in dev the engine adds debug comments and
  `data-phx-loc` attributes, and this binary is stored as the GraphQL `bodyHtml`, which must not carry them.
  The class list and the root marker are escaped by `Phoenix.HTML.attributes_escape/1` in the same form the
  template uses, so the two paths write the same bytes (chat_components_test.exs proves it in the test environment).
  """
  @spec markdown_body_html(String.t(), keyword()) :: String.t()
  def markdown_body_html(content, attrs) when is_binary(content) and is_list(attrs) do
    global = attrs |> Keyword.get(:attrs, %{}) |> Map.new()
    {global_class, rest} = Map.pop(global, :class)
    classes = ["message-content markdown-body", [Keyword.get(attrs, :class), global_class]]

    # LiveView marks the root of a rendered component with its root attribute (config.exs), before `class`.
    marker =
      Enum.map(
        List.wrap(Application.get_env(:phoenix_live_view, :root_tag_attribute)),
        &{&1, true}
      )

    {:safe, wrapper} =
      Phoenix.HTML.attributes_escape(marker ++ [{:class, classes} | Map.to_list(rest)])

    html =
      ChatMarkdown.to_html(
        content,
        Keyword.get(attrs, :streaming, false),
        hard_breaks: Keyword.get(attrs, :hard_breaks, false)
      )

    IO.iodata_to_binary(["<div", wrapper, ">", Safe.to_iodata(html), "</div>"])
  end
end
