defmodule ExBdd.Verification do
  @moduledoc "Summary of a strictly verified feature corpus."

  @enforce_keys [:feature_count, :scenario_count, :step_count, :binding_count]
  defstruct [:feature_count, :scenario_count, :step_count, :binding_count]

  @type t :: %__MODULE__{
          feature_count: non_neg_integer(),
          scenario_count: non_neg_integer(),
          step_count: non_neg_integer(),
          binding_count: non_neg_integer()
        }
end

defmodule ExBdd.VerificationError do
  @moduledoc "Raised when a feature corpus is not completely implemented."

  defexception errors: []

  @impl Exception
  def message(%__MODULE__{errors: errors}) do
    "Behaviour verification failed:\n" <> Enum.map_join(errors, "\n", &"  * #{&1}")
  end
end

defmodule ExBdd.Verifier do
  @moduledoc false

  alias ExBdd.Discovery.DiscoveryResult
  alias ExBdd.Gherkin.Pickles
  alias ExBdd.{Verification, VerificationError}

  @spec verify!(DiscoveryResult.t()) :: Verification.t()
  def verify!(%DiscoveryResult{} = discovery) do
    compiled = Enum.map(discovery.features, &{&1, Pickles.compile(&1).pickles})
    pickles = Enum.flat_map(compiled, &elem(&1, 1))

    {step_errors, used_bindings} = verify_steps(pickles, discovery)

    errors =
      corpus_errors(discovery, compiled, pickles) ++
        scenario_errors(discovery.features) ++
        step_errors ++ unused_binding_errors(discovery.step_registry, used_bindings)

    if errors != [] do
      raise VerificationError, errors: errors
    end

    %Verification{
      feature_count: length(discovery.features),
      scenario_count: length(pickles),
      step_count: Enum.sum(Enum.map(pickles, &length(&1.steps))),
      binding_count: map_size(discovery.step_registry)
    }
  end

  defp corpus_errors(discovery, compiled, pickles) do
    []
    |> maybe_add(discovery.features == [], "No feature files were discovered")
    |> maybe_add(discovery.step_registry == %{}, "No step bindings were discovered")
    |> maybe_add(discovery.features != [] and pickles == [], "No executable scenarios were found")
    |> Kernel.++(
      for {feature, _feature_pickles} <- compiled,
          scenarios(feature) == [],
          do: "#{feature.file}: feature #{inspect(feature.name)} has no scenarios"
    )
    |> Kernel.++(
      for {feature, feature_pickles} <- compiled,
          scenarios(feature) != [] and feature_pickles == [],
          do:
            "#{feature.file}: feature #{inspect(feature.name)} expands to no executable scenarios"
    )
  end

  defp scenario_errors(features) do
    Enum.flat_map(features, fn feature ->
      Enum.flat_map(scenarios(feature), &missing_phase_errors(feature, &1))
    end)
  end

  defp missing_phase_errors(feature, scenario) do
    keywords = Enum.map(scenario.steps, & &1.keyword)
    location = "#{feature.file}:#{scenario.line} scenario #{inspect(scenario.name)}"

    []
    |> maybe_add("When" not in keywords, "#{location} requires an explicit When step")
    |> maybe_add("Then" not in keywords, "#{location} requires an explicit Then step")
  end

  defp verify_steps(pickles, discovery) do
    Enum.reduce(pickles, {[], MapSet.new()}, &verify_pickle_steps(&1, &2, discovery))
  end

  defp verify_pickle_steps(pickle, accumulator, discovery) do
    Enum.reduce(pickle.steps, accumulator, fn pickle_step, {errors, used} ->
      keys =
        ExBdd.Runtime.matching_definition_keys(
          pickle_step.text,
          discovery.step_registry,
          discovery.parameter_types
        )

      location =
        "#{pickle.uri}:#{pickle_step.step.line} scenario #{inspect(pickle.scenario_name)}, " <>
          "step #{inspect(pickle_step.text)}"

      case keys do
        [] ->
          {errors ++ ["#{location} has no matching binding"], used}

        [key] ->
          {errors, MapSet.put(used, key)}

        multiple ->
          {errors ++ ["#{location} matches #{length(multiple)} bindings"], used}
      end
    end)
  end

  defp unused_binding_errors(step_registry, used_bindings) do
    step_registry
    |> Enum.reject(fn {key, _definition} -> MapSet.member?(used_bindings, key) end)
    |> Enum.sort_by(fn {key, _definition} -> inspect(key) end)
    |> Enum.map(fn {key, {_module, metadata}} ->
      "#{metadata.file}:#{metadata.line} binding #{display_pattern(key)} is not used"
    end)
  end

  defp scenarios(feature) do
    feature.scenarios ++ Enum.flat_map(Map.get(feature, :rules, []), & &1.scenarios)
  end

  defp display_pattern({:expression, pattern}), do: inspect(pattern)
  defp display_pattern({:regex, {source, opts}}), do: inspect(Regex.compile!(source, opts))

  defp maybe_add(errors, true, error), do: errors ++ [error]
  defp maybe_add(errors, false, _error), do: errors
end
