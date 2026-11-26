defmodule BnestApp.CodexChat.Domain.ModelAccess do
  @moduledoc """
  Which Codex models a user may use, and which reasoning efforts they may choose (ADR 006).

  Only the latest model of each tier is offered: Luna is `gpt-6-luna`, Terra is `gpt-6.1-terra` and Sol is
  `gpt-6.1-sol`. Astra and every older id are never offered. Roles are checked in this order, child administrator
  first:

  - child administrator (roles with both admin and children): like children, Luna at medium effort, with no picker;
  - admin (and a user with no recognised role): any offered model, listed Sol, Terra, Luna whatever order Codex lists
    them in, default Terra; any effort the model supports, default medium;
  - parents: Luna or Terra, default Terra; the effort is always medium and is not chosen;
  - children: Luna at medium effort, with no picker.

  The access map says what the view shows (`model_selectable?`, `effort_selectable?`) and the functions below say
  what a request may change. The server applies them to every event, so a forged value is refused, not just hidden.
  """

  @luna "gpt-6-luna"
  @terra "gpt-6.1-terra"
  @sol "gpt-6.1-sol"
  @offered [@luna, @terra, @sol]
  # The admin's picker order, highest tier first (see admin_rank/1).
  @admin_order [@sol, @terra, @luna]
  # A parent's choices, the default first. The picker lists them in this order whatever order Codex lists the models in.
  @parent_order [@terra, @luna]

  @default_effort "medium"
  # The effort a conversation takes when its model does not support the one it had: the highest effort Luna has.
  @fallback_effort "max"

  @required %{
    children: {@luna, "GPT-6-Luna"},
    parents: {@terra, "GPT-6.1 Terra"}
  }

  @type model :: map()

  @type access :: %{
          model_selectable?: boolean(),
          effort_selectable?: boolean(),
          available?: boolean(),
          models: [model()],
          model: model(),
          reasoning_effort: String.t(),
          error: String.t() | nil
        }

  @doc "Whether Codex's model `id` is one of the offered latest models."
  @spec offered?(String.t()) :: boolean()
  def offered?(id), do: id in @offered

  @spec resolve(map(), [model()]) :: access()
  def resolve(%{"roles" => roles}, models) when is_list(roles) and is_list(models) do
    cond do
      "admin" in roles and "children" in roles -> children(models)
      "admin" in roles -> choose(models)
      "parents" in roles -> parents(models)
      "children" in roles -> children(models)
      true -> choose(models)
    end
  end

  def resolve(_user, models) when is_list(models), do: choose(models)

  @doc """
  The model and reasoning effort a conversation runs with, given the model and effort it saved. A saved model the
  role does not offer keeps its tier when the role still offers that tier's latest model, else it resolves to the
  role's default. The effort is the role's fixed effort, or for a role that picks its effort the rule of
  `reasoning_effort/2`.
  """
  @spec settle(access(), String.t(), String.t()) :: {model(), String.t()}
  def settle(access, saved_model_id, saved_effort) do
    model =
      Enum.find(access.models, &(&1.id == saved_model_id)) ||
        same_tier_model(access, saved_model_id) ||
        access.model

    {model, effort_for(access, model, saved_effort)}
  end

  @doc """
  The latest offered model id of the tier `model_id` names (`luna`, `terra` or `sol`, case-insensitive), or `nil`
  when it names no known tier.
  """
  @spec tier_latest(String.t()) :: String.t() | nil
  def tier_latest(model_id) when is_binary(model_id) do
    case tier_token(model_id) do
      "luna" -> @luna
      "terra" -> @terra
      "sol" -> @sol
      nil -> nil
    end
  end

  def tier_latest(_model_id), do: nil

  @doc """
  The result of choosing `model_id` in the picker, as `{:ok, model, effort}` where `effort` is the one the
  conversation runs with after the switch. `:error` when the role may not pick a model, or the model is not one of
  its choices.
  """
  @spec select_model(access() | nil, String.t(), String.t()) ::
          {:ok, model(), String.t()} | :error
  def select_model(
        %{model_selectable?: true, available?: true} = access,
        model_id,
        current_effort
      ) do
    case Enum.find(access.models, &(&1.id == model_id)) do
      nil -> :error
      model -> {:ok, model, effort_for(access, model, current_effort)}
    end
  end

  def select_model(_access, _model_id, _current_effort), do: :error

  @doc """
  `{:ok, effort}` when the role may pick efforts and `model` supports `effort`. `:error` otherwise.
  """
  @spec select_effort(access() | nil, model(), String.t()) :: {:ok, String.t()} | :error
  def select_effort(%{effort_selectable?: true, available?: true}, model, effort) do
    if effort in model.supported_reasoning_efforts, do: {:ok, effort}, else: :error
  end

  def select_effort(_access, _model, _effort), do: :error

  @doc """
  The reasoning effort to run `model` with: `requested` when the model supports it, else `"max"` when it supports
  that, else the model's default.
  """
  @spec reasoning_effort(model(), String.t()) :: String.t()
  def reasoning_effort(model, requested \\ @default_effort) do
    cond do
      requested in model.supported_reasoning_efforts -> requested
      @fallback_effort in model.supported_reasoning_efforts -> @fallback_effort
      true -> model.default_reasoning_effort
    end
  end

  # A saved model the role no longer offers keeps its tier when the role still offers that tier's latest model.
  defp same_tier_model(access, saved_model_id) do
    case tier_latest(saved_model_id) do
      nil -> nil
      latest_id -> Enum.find(access.models, &(&1.id == latest_id))
    end
  end

  # The tier token in a model id: `-luna`, `-terra` or `-sol`, case-insensitive, or the id ending in the tier name.
  defp tier_token(model_id) do
    downcased = String.downcase(model_id)
    Enum.find(["luna", "terra", "sol"], &tier_match?(downcased, &1))
  end

  defp tier_match?(downcased, tier),
    do: String.contains?(downcased, "-" <> tier) or String.ends_with?(downcased, tier)

  defp effort_for(%{effort_selectable?: true}, model, requested),
    do: reasoning_effort(model, requested)

  defp effort_for(access, _model, _requested), do: access.reasoning_effort

  defp choose([]), do: raise(ArgumentError, "Codex model catalog cannot be empty")

  defp choose(discovered) do
    models = Enum.sort_by(discovered, &admin_rank/1)
    [first | _] = models

    default =
      Enum.find(models, &(&1.id == @terra)) || Enum.find(models, & &1.is_default) || first

    %{
      model_selectable?: true,
      effort_selectable?: true,
      available?: true,
      models: models,
      model: default,
      reasoning_effort: @default_effort,
      error: nil
    }
  end

  # The admin's picker lists the latest models highest tier first, whatever order Codex lists them in. A model outside
  # this list keeps its place after them, so no discovered model is dropped by the sort.
  defp admin_rank(model) do
    Enum.find_index(@admin_order, &(&1 == model.id)) || length(@admin_order)
  end

  defp parents(models) do
    choices = Enum.flat_map(@parent_order, fn id -> Enum.filter(models, &(&1.id == id)) end)
    fixed(:parents, choices, true)
  end

  defp children(models) do
    fixed(:children, Enum.filter(models, &(&1.id == @luna)), false)
  end

  # A role whose model is fixed, or who picks among its own models, is usable only when its default is offered at
  # medium effort. Only a choice that supports medium effort is kept, so no role can pick a model without it. Nothing
  # falls back to another model, so the role is unavailable instead.
  defp fixed(role, choices, picker?) do
    {id, display_name} = Map.fetch!(@required, role)
    choices = Enum.filter(choices, &(@default_effort in &1.supported_reasoning_efforts))
    default = Enum.find(choices, &(&1.id == id))
    available? = not is_nil(default)
    model = default || required_model(id, display_name)
    picker? = picker? and available?

    %{
      model_selectable?: picker?,
      effort_selectable?: false,
      available?: available?,
      models: if(picker?, do: choices, else: [model]),
      model: model,
      reasoning_effort: @default_effort,
      error: if(available?, do: nil, else: "#{display_name} is not available in local Codex.")
    }
  end

  defp required_model(id, display_name) do
    %{
      id: id,
      display_name: display_name,
      default_reasoning_effort: @default_effort,
      supported_reasoning_efforts: [@default_effort],
      is_default: false
    }
  end
end
