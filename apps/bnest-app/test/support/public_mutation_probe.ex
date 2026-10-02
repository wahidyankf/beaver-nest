defmodule BnestApp.Test.PublicMutationProbe do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # Exercises every mutation field the public GraphQL schema declares, so a test can tell
  # whether any of them commits a system message: the fields come from the schema's own
  # introspection answer, never from a list kept here. Each field's arguments are filled
  # by name from the caller's values; a field with a required argument no value names
  # cannot be exercised, and is reported so, never skipped.

  @introspection """
  {
    __schema {
      mutationType {
        fields {
          name
          args { name type { ...TypeRef } }
          type { ...TypeRef }
        }
      }
    }
  }

  fragment TypeRef on __Type {
    kind
    name
    ofType { kind name ofType { kind name ofType { kind name } } }
  }
  """

  @type field :: %{name: String.t(), args: [map()], selection: String.t()}

  @doc "The introspection query that lists the schema's mutation fields."
  @spec introspection() :: String.t()
  def introspection, do: @introspection

  @doc "The mutation fields of an introspection answer's `data`."
  @spec fields(map()) :: [field()]
  def fields(%{"__schema" => %{"mutationType" => %{"fields" => fields}}}) do
    Enum.map(fields, fn field ->
      %{
        name: field["name"],
        args:
          Enum.map(field["args"], fn arg ->
            %{name: arg["name"], type: render(arg["type"]), required?: required?(arg["type"])}
          end),
        selection: selection(field["type"])
      }
    end)
  end

  def fields(%{"__schema" => %{"mutationType" => nil}}), do: []

  @doc """
  The document and variables that run `field` with the `values` its arguments name, or
  `{:error, {:unexercisable, field, argument}}` for a required argument no value names.
  Optional arguments without a value are left out.
  """
  @spec invocation(field(), %{optional(String.t()) => term()}) ::
          {:ok, String.t(), map()} | {:error, {:unexercisable, String.t(), String.t()}}
  def invocation(field, values) do
    case Enum.find(field.args, &(&1.required? and not Map.has_key?(values, &1.name))) do
      %{name: missing} ->
        {:error, {:unexercisable, field.name, missing}}

      nil ->
        args = Enum.filter(field.args, &Map.has_key?(values, &1.name))
        {:ok, document(field, args), Map.new(args, &{&1.name, Map.fetch!(values, &1.name)})}
    end
  end

  @doc "Whether a field name mentions a system message, in any letter case."
  @spec names_system?(String.t()) :: boolean()
  def names_system?(name), do: name |> String.downcase() |> String.contains?("system")

  defp document(field, []), do: "mutation { #{field.name}#{field.selection} }"

  defp document(field, args) do
    declarations = Enum.map_join(args, ", ", &"$#{&1.name}: #{&1.type}")
    arguments = Enum.map_join(args, ", ", &"#{&1.name}: $#{&1.name}")
    "mutation(#{declarations}) { #{field.name}(#{arguments})#{field.selection} }"
  end

  defp render(%{"kind" => "NON_NULL", "ofType" => inner}), do: render(inner) <> "!"
  defp render(%{"kind" => "LIST", "ofType" => inner}), do: "[" <> render(inner) <> "]"
  defp render(%{"name" => name}), do: name

  defp required?(type), do: type["kind"] == "NON_NULL"

  defp selection(%{"kind" => kind, "ofType" => inner}) when kind in ["NON_NULL", "LIST"],
    do: selection(inner)

  defp selection(%{"kind" => kind}) when kind in ["OBJECT", "INTERFACE", "UNION"],
    do: " { __typename }"

  defp selection(_scalar_or_enum), do: ""
end
