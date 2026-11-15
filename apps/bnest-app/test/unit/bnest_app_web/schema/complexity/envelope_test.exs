defmodule BnestAppWeb.Schema.Complexity.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Absinthe.Blueprint
  alias Absinthe.Blueprint.Execution
  alias Absinthe.Phase.Document.Result, as: RawResult
  alias Absinthe.Phase.Error
  alias BnestAppWeb.Schema.Complexity.Envelope

  test "a document that already failed sanitizes its errors to the safe envelope" do
    blueprint = %Blueprint{
      execution: %Execution{
        validation_errors: [
          %Error{
            message: "An unknown error occurred during parsing: expected a map, got:\n\n    42\n",
            phase: Absinthe.Phase.Parse
          }
        ]
      }
    }

    assert {:jump, refused, RawResult} = Envelope.run(blueprint, [])

    assert [
             %Error{
               message: %{
                 message: "The request is invalid.",
                 extensions: %{code: "VALIDATION_FAILED"}
               }
             }
           ] = refused.execution.validation_errors
  end
end
