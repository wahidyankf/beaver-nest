defmodule BnestApp.ApplicationTest do
  use ExUnit.Case, async: true

  test "propagates configuration changes to the endpoint" do
    assert :ok = BnestApp.Application.config_change(%{}, [], [])
  end
end
