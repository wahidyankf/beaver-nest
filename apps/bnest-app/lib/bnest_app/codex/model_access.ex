defmodule BnestApp.Codex.ModelAccess do
  @moduledoc false

  @required_models %{
    children: {"gpt-5.6-luna", "GPT-5.6-Luna"},
    parents: {"gpt-5.6-terra", "GPT-5.6-Terra"}
  }

  @type access :: %{
          selectable?: boolean(),
          available?: boolean(),
          models: [map()],
          model: map(),
          reasoning_effort: String.t(),
          error: String.t() | nil
        }

  @spec resolve(map(), [map()]) :: access()
  def resolve(%{"roles" => roles}, models) when is_list(roles) and is_list(models) do
    cond do
      "admin" in roles -> selectable(models)
      "parents" in roles -> restricted(:parents, models)
      "children" in roles -> restricted(:children, models)
      true -> selectable(models)
    end
  end

  def resolve(_user, models) when is_list(models), do: selectable(models)

  defp selectable([model | _] = models) do
    preferred =
      Enum.find(models, &(&1.id == "gpt-5.6-terra")) ||
        Enum.find(models, & &1.is_default) || model

    %{
      selectable?: true,
      available?: true,
      models: models,
      model: preferred,
      reasoning_effort: "medium",
      error: nil
    }
  end

  defp selectable([]), do: raise(ArgumentError, "Codex model catalog cannot be empty")

  defp restricted(role, models) do
    {id, display_name} = Map.fetch!(@required_models, role)
    model = Enum.find(models, &(&1.id == id)) || required_model(id, display_name)
    available? = Enum.any?(models, &(&1.id == id and "medium" in &1.supported_reasoning_efforts))

    %{
      selectable?: false,
      available?: available?,
      models: [model],
      model: model,
      reasoning_effort: "medium",
      error: if(available?, do: nil, else: "#{display_name} is not available in local Codex.")
    }
  end

  defp required_model(id, display_name) do
    %{
      id: id,
      display_name: display_name,
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ["medium"],
      is_default: false
    }
  end
end
