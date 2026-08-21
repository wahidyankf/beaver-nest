defmodule BnestAppWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "defines the application metrics" do
    metrics = BnestAppWeb.Telemetry.metrics()

    assert Enum.any?(metrics, &(&1.event_name == [:phoenix, :endpoint, :start]))
    assert Enum.any?(metrics, &(&1.name == [:vm, :memory, :total]))
  end
end
