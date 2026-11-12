defmodule BnestAppWeb.Schema.Complexity do
  @moduledoc """
  The complexity budget of the public GraphQL schema.

  Absinthe prices a document before it resolves anything. Rendering a message's
  `bodyHtml` runs the Markdown renderer once per message, so each `bodyHtml`
  field costs `@body_html_weight`. A page costs its size times the price of one
  of its messages. A document priced above `max_complexity/0` is refused before
  resolution with the safe `VALIDATION_FAILED` error (see `Envelope`).

  The Plug route runs the budget through `pipeline/2` with `max_complexity/0`;
  in-process callers run it through `run_options/0`. Both name the same budget.
  """

  alias Absinthe.Phase.Document.Complexity.Result
  alias BnestApp.FamilyChat.Domain.Cursor
  alias BnestAppWeb.Schema.Complexity.Envelope

  @max_complexity 7_500
  @body_html_weight 100

  @doc "The largest document price the public schema admits."
  @spec max_complexity() :: pos_integer()
  def max_complexity, do: @max_complexity

  @doc "The price of a `bodyHtml` field, given the price of its children (none for a scalar)."
  @spec body_html(non_neg_integer()) :: non_neg_integer()
  def body_html(child_complexity), do: @body_html_weight + child_complexity

  @doc """
  The price of a `familyChatMessages` page: its size times the price of its
  connection children. An argument that is not a valid size is priced at the
  largest page; the resolver refuses such a size anyway.
  """
  @spec page(map(), non_neg_integer()) :: non_neg_integer()
  def page(args, child_complexity) do
    max = Cursor.max_limit()
    size = Map.get(args, :limit, max)
    size = if is_integer(size) and size in 1..max, do: size, else: max
    size * child_complexity
  end

  @doc "The pipeline `Absinthe.Plug` builds for the route: Absinthe's default one, with the budget's envelope."
  @spec pipeline(map(), keyword()) :: Absinthe.Pipeline.t()
  def pipeline(config, pipeline_opts) do
    config
    |> Absinthe.Plug.default_pipeline(pipeline_opts)
    |> with_envelope()
  end

  @doc "The same envelope as `pipeline/2`, for `Absinthe.run/3`'s `:pipeline_modifier` option."
  @spec pipeline_modifier(Absinthe.Pipeline.t(), keyword()) :: Absinthe.Pipeline.t()
  def pipeline_modifier(pipeline, _options), do: with_envelope(pipeline)

  @doc "The `Absinthe.run/3` options that price a document against the budget, as the Plug route does."
  @spec run_options() :: keyword()
  def run_options do
    [
      analyze_complexity: true,
      max_complexity: @max_complexity,
      pipeline_modifier: &pipeline_modifier/2
    ]
  end

  # The envelope replaces the result phase rather than following it: a refused document jumps from the complexity
  # result straight to the result phase, so a phase placed after the complexity result would never run for it.
  defp with_envelope(pipeline) do
    Absinthe.Pipeline.replace(pipeline, Result, Envelope)
  end
end
