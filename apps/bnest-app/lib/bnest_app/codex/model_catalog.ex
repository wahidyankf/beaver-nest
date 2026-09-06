defmodule BnestApp.Codex.ModelCatalog do
  @moduledoc false

  use GenServer

  require Logger

  alias BnestApp.Codex.ModelDiscovery
  alias BnestApp.Codex.Settings

  @efforts ~w(none minimal low medium high xhigh max ultra)
  @fallback [
    %{
      id: "gpt-5.6-terra",
      display_name: "GPT-5.6-Terra",
      default_reasoning_effort: "medium",
      supported_reasoning_efforts: ~w(low medium high xhigh max ultra),
      is_default: false
    }
  ]

  @type model :: %{
          id: String.t(),
          display_name: String.t(),
          default_reasoning_effort: String.t(),
          supported_reasoning_efforts: [String.t()],
          is_default: boolean()
        }

  def start_link(options) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec all() :: [model()]
  def all(server \\ __MODULE__), do: GenServer.call(server, :all)

  @spec fetch(String.t()) :: {:ok, model()} | :error
  def fetch(id, server \\ __MODULE__), do: GenServer.call(server, {:fetch, id})

  @spec default() :: model()
  def default(server \\ __MODULE__), do: GenServer.call(server, :default)

  @spec reasoning_effort(model(), String.t()) :: String.t()
  def reasoning_effort(model, requested \\ Settings.preferred_reasoning_effort()) do
    cond do
      requested in model.supported_reasoning_efforts ->
        requested

      Settings.preferred_reasoning_effort() in model.supported_reasoning_efforts ->
        Settings.preferred_reasoning_effort()

      true ->
        model.default_reasoning_effort
    end
  end

  @impl GenServer
  def init(options) do
    models = load_models(options)
    {:ok, %{models: models, by_id: Map.new(models, &{&1.id, &1})}}
  end

  @impl GenServer
  def handle_call(:all, _from, state), do: {:reply, state.models, state}

  def handle_call({:fetch, id}, _from, state) do
    {:reply, Map.fetch(state.by_id, id), state}
  end

  def handle_call(:default, _from, state) do
    model =
      Enum.find(state.models, &(&1.id == Settings.preferred_model())) ||
        Enum.find(state.models, & &1.is_default) || List.first(state.models)

    {:reply, model, state}
  end

  defp load_models(options) do
    case Keyword.fetch(options, :models) do
      {:ok, models} ->
        normalize_or_fallback(models)

      :error ->
        load_configured_models(options)
    end
  end

  defp load_configured_models(options) do
    if Keyword.has_key?(options, :models_runner) do
      discover_models(options)
    else
      load_application_models(options, Application.get_env(:bnest_app, :codex_models))
    end
  end

  defp load_application_models(options, nil), do: discover_models(options)

  defp load_application_models(_options, module) when is_atom(module) do
    normalize_or_fallback(module.all())
  end

  defp discover_models(options) do
    case discovery(options).discover(options) do
      {:ok, models} ->
        normalize_or_fallback(models)

      :error ->
        Logger.warning("Codex model discovery failed; using the Terra fallback")
        @fallback
    end
  end

  defp discovery(options), do: Keyword.get(options, :discovery, ModelDiscovery)

  defp normalize_or_fallback(models) when is_list(models) do
    normalized =
      models
      |> Enum.reduce_while({:ok, []}, fn model, {:ok, result} ->
        case normalize(model) do
          {:ok, normalized_model} -> {:cont, {:ok, [normalized_model | result]}}
          :error -> {:halt, :error}
        end
      end)
      |> case do
        {:ok, result} -> Enum.reverse(result)
        :error -> []
      end
      |> Enum.uniq_by(& &1.id)

    if normalized == [] do
      Logger.warning("Codex returned no valid picker models; using the Terra fallback")
      @fallback
    else
      normalized
    end
  end

  defp normalize_or_fallback(_models) do
    Logger.warning("Codex returned no valid picker models; using the Terra fallback")
    @fallback
  end

  defp normalize(model) when is_map(model) do
    id = value(model, :id)
    display_name = value(model, :display_name)
    default_effort = value(model, :default_reasoning_effort)
    supported_efforts = value(model, :supported_reasoning_efforts)
    is_default = value(model, :is_default, false)

    if valid_text?(id) and valid_text?(display_name) and default_effort in @efforts and
         is_list(supported_efforts) and supported_efforts != [] and
         Enum.all?(supported_efforts, &(&1 in @efforts)) and default_effort in supported_efforts and
         is_boolean(is_default) do
      {:ok,
       %{
         id: id,
         display_name: display_name,
         default_reasoning_effort: default_effort,
         supported_reasoning_efforts: supported_efforts,
         is_default: is_default
       }}
    else
      :error
    end
  end

  defp normalize(_model), do: :error

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp valid_text?(value), do: is_binary(value) and byte_size(value) in 1..128
end
