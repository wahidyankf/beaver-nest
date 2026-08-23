defmodule BnestApp.Behaviour.BoundaryPolicy do
  @moduledoc false

  @unit_forbidden [
    {~r/\bFile\./u, "filesystem access"},
    {~r/\bPath\./u, "filesystem path access"},
    {~r/\bSystem\./u, "operating-system access"},
    {~r/\bProcess\./u, "process access"},
    {~r/\bPort\./u, "external process ports"},
    {~r/:gen_(?:tcp|udp)/u, "socket access"},
    {~r/:httpc\b/u, "HTTP access"},
    {~r/\b(?:Req|Finch|Mint)\./u, "network clients"},
    {~r/\bPhoenix\.(?:ConnTest|LiveViewTest)\b/u, "integration test helpers"},
    {~r/https?:\/\//u, "network URLs"},
    {~r/\b(?:localhost|127\.0\.0\.1)\b/u, "loopback network access"}
  ]

  @integration_forbidden [
    {~r/:gen_(?:tcp|udp)/u, "sockets"},
    {~r/:httpc\b/u, "HTTP access"},
    {~r/\b(?:Req|Finch|Mint|HTTPoison|Tesla)\./u, "network clients"},
    {~r/https?:\/\//u, "network URLs"},
    {~r/\b(?:localhost|127\.0\.0\.1)\b/u, "loopback network access"},
    {~r/server:\s*true/u, "local server startup"},
    {~r/\bBandit\b/u, "HTTP server startup"}
  ]

  @spec verify!() :: :ok
  def verify! do
    violations =
      violations(
        [
          "test/unit/**/*.{ex,exs}",
          "test/behaviour/steps/**/*.exs",
          "test/behaviour/support/unit.exs"
        ],
        @unit_forbidden,
        :unit
      ) ++
        violations(
          [
            "test/integration/**/*.{ex,exs}",
            "test/behaviour/steps/**/*.exs",
            "test/behaviour/support/integration.exs"
          ],
          @integration_forbidden,
          :integration
        )

    if violations != [] do
      raise "Test boundary verification failed:\n  * " <> Enum.join(violations, "\n  * ")
    end

    :ok
  end

  defp violations(patterns, forbidden, layer) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.flat_map(fn file -> violations_in(file, File.read!(file), forbidden, layer) end)
  end

  defp violations_in(file, source, forbidden, layer) do
    for {pattern, boundary} <- forbidden,
        Regex.match?(pattern, source),
        do: "#{file} uses forbidden #{layer} #{boundary}"
  end
end

behaviour_root = Path.expand("../../../../specs/apps/bnest/app/behaviours", __DIR__)
steps = [Path.join(__DIR__, "steps/**/*.exs")]

:ok = BnestApp.Behaviour.BoundaryPolicy.verify!()

adapters = [
  unit: {
    Path.join(__DIR__, "support/unit.exs"),
    BnestApp.Behaviour.UnitHomePageDriver
  },
  integration: {
    Path.join(__DIR__, "support/integration.exs"),
    BnestApp.Behaviour.IntegrationHomePageDriver
  }
]

callbacks = BnestApp.Behaviour.Driver.behaviour_info(:callbacks)

Enum.each(adapters, fn {layer, {support, driver}} ->
  verification =
    ExBdd.verify_features!(
      features: [Path.join(behaviour_root, "**/*.feature")],
      steps: steps,
      support: [support]
    )

  unless Code.ensure_loaded?(driver) do
    raise "#{layer} behaviour driver #{inspect(driver)} could not be loaded"
  end

  missing =
    Enum.reject(callbacks, fn {name, arity} -> function_exported?(driver, name, arity) end)

  if missing != [] do
    raise "#{layer} behaviour driver #{inspect(driver)} is missing #{inspect(missing)}"
  end

  IO.puts(
    "#{layer}: #{verification.feature_count} feature(s), " <>
      "#{verification.scenario_count} scenario(s), " <>
      "#{verification.step_count} step(s), " <>
      "#{verification.binding_count} binding(s)"
  )
end)
