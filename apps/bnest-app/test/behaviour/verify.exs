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

  # Integration owns a loopback socket it starts and stops; the layer is bounded by its
  # observation point, not by socket permission, so only non-loopback reach and browser
  # drivers are refused here. Shared step files stay clean because @unit_forbidden also
  # scans them, which confines socket code to the integration driver.
  @integration_forbidden [
    {~r/\b(?:Playwright|Wallaby|Hound)\b/u, "browser automation"}
  ]

  # Egress needs both a client and a destination. A bare URL in test data reaches nothing,
  # so flagging it alone would reject fixtures that merely mention an address.
  @network_client ~r/\b(?:Req|Finch|Mint|HTTPoison|Tesla)\.|:httpc\b|:gen_(?:tcp|udp)/u
  @non_loopback_url ~r/https?:\/\/(?!(?:localhost|127\.0\.0\.1|\[::1\])(?:[:\/?#"'\s]|$))/u

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
        ) ++
        egress_violations([
          "test/integration/**/*.{ex,exs}",
          "test/behaviour/steps/**/*.exs",
          "test/behaviour/support/integration.exs"
        ])

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

  defp egress_violations(patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(fn file ->
      source = File.read!(file)
      Regex.match?(@network_client, source) and Regex.match?(@non_loopback_url, source)
    end)
    |> Enum.map(&"#{&1} reaches a non-loopback network address")
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
