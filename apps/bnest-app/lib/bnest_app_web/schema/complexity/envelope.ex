defmodule BnestAppWeb.Schema.Complexity.Envelope do
  @moduledoc """
  Answers a document the complexity budget refuses with the safe error envelope the Family Chat surface uses.

  Absinthe's own complexity message names the node and both numbers. A client gets only the code and the generic
  message; the numbers stay out of the response. It replaces `Absinthe.Phase.Document.Complexity.Result` in the
  pipeline (see `BnestAppWeb.Schema.Complexity`), and delegates the pricing to that phase.
  """

  @behaviour Absinthe.Phase

  alias Absinthe.Phase.Document.Complexity.Result
  alias Absinthe.Phase.Document.Result, as: RawResult

  @refusal %{message: "The request is invalid.", extensions: %{code: "VALIDATION_FAILED"}}

  # Absinthe's pipeline options always set `jump_phases: true`, and this pipeline never overrides it, so a refused
  # document is always a `{:jump, _, result_phase}` and the `{:error, _}` return of the result phase never occurs.
  # A document that already carries validation errors when it reaches the
  # complexity gate failed earlier (parse or validation jumped here through
  # `result_phase`): its errors are sanitized and sent to render, never
  # re-priced. A clean document is priced as before.
  def run(input, options) do
    case input.execution.validation_errors do
      [] ->
        case Result.run(input, options) do
          {:ok, blueprint} -> {:ok, blueprint}
          {:jump, blueprint, phase} -> {:jump, refuse(blueprint), phase}
        end

      _already_failed ->
        {:jump, refuse(input), RawResult}
    end
  end

  # One refusal is enough: the root field and the operation both exceed the budget, and the client needs one code.
  defp refuse(blueprint) do
    errors =
      blueprint.execution.validation_errors
      |> Enum.take(1)
      |> Enum.map(&%{&1 | message: @refusal})

    put_in(blueprint.execution.validation_errors, errors)
  end
end
