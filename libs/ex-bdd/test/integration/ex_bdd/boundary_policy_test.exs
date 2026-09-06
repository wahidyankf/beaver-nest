defmodule ExBdd.BoundaryPolicyTest do
  @moduledoc """
  Guards the layer separation defined in
  `repo-governance/development/quality-gates.md` ("Test Boundaries").

  This test reads real source files, so it belongs to the integration layer by the same
  rule it enforces. `bnest-app` and `badakmini-cli` already guard their boundaries; this
  closes the equivalent gap for ExBdd.
  """

  use ExUnit.Case, async: true

  # Unit replaces every OS-facing dependency with a double. `System.version/0` is excluded
  # deliberately: it reports the compiled runtime version and reaches no OS resource.
  @unit_forbidden [
    {~r/\bFile\./u, "filesystem access"},
    {~r/\bPath\.wildcard\b/u, "filesystem discovery"},
    {~r/\bSystem\.(?:get_env|put_env|cmd|shell|delete_env)\b/u, "environment or process access"},
    {~r/\bPort\.open\b/u, "external process ports"},
    {~r/:gen_(?:tcp|udp)/u, "socket access"},
    {~r/:httpc\b/u, "HTTP access"}
  ]

  # Integration may own a loopback socket; it may not reach an external network or drive a
  # browser. ExBdd owns no public boundary, so it has no E2E layer at all.
  @integration_forbidden [
    {~r/\b(?:Playwright|Wallaby|Hound)\b/u, "browser automation"}
  ]

  # Egress needs both a client and a destination. A bare URL in test data reaches nothing,
  # so flagging it alone produces false positives on fixtures such as CCK attachments.
  @network_client ~r/\b(?:Req|Finch|Mint|HTTPoison|Tesla)\.|:httpc\b|:gen_(?:tcp|udp)/u
  @non_loopback_url ~r/https?:\/\/(?!(?:localhost|127\.0\.0\.1|\[::1\])(?:[:\/?#"'\s]|$))/u

  test "unit sources reach no real OS resource" do
    assert violations("test/unit/**/*.{ex,exs}", @unit_forbidden) == []
  end

  test "integration sources reach no external network and drive no browser" do
    assert violations("test/integration/**/*.{ex,exs}", @integration_forbidden) == []
    assert egress_violations("test/integration/**/*.{ex,exs}") == []
  end

  defp egress_violations(pattern) do
    pattern
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "boundary_policy_test.exs"))
    |> Enum.filter(fn file ->
      source = File.read!(file)
      Regex.match?(@network_client, source) and Regex.match?(@non_loopback_url, source)
    end)
  end

  defp violations(pattern, forbidden) do
    pattern
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "boundary_policy_test.exs"))
    |> Enum.flat_map(fn file ->
      source = File.read!(file)

      for {regex, label} <- forbidden, Regex.match?(regex, source) do
        "#{file}: #{label}"
      end
    end)
  end
end
