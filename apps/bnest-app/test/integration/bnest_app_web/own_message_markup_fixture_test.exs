defmodule BnestAppWeb.OwnMessageMarkupFixtureTest do
  # ADR 005, decision 4: the Vitest rows for the Codex chat read the committed fixture `test/support/own_message_markup.json`.
  # This test writes that file from the production component, and it fails when the markup changes until the file is
  # written again:
  #
  #     BNEST_WRITE_OWN_MESSAGE_FIXTURE=1 BNEST_TEST_LAYER=integration MIX_ENV=test mix test <this file>
  #
  use ExUnit.Case, async: true

  alias BnestAppWeb.OwnMessageMarkupFixture, as: Fixture

  # Test-only: the fixture file is read and written here, never in the unit layer.
  defp fixture_path, do: Path.expand("../../support/own_message_markup.json", __DIR__)

  defp expected_fixture do
    Map.new(Fixture.inputs(), fn {name, input} ->
      {name, %{"input" => input, "markup" => Fixture.own_message_html(input)}}
    end)
  end

  test "the committed fixture is the markup the production component writes for each input" do
    path = fixture_path()

    if System.get_env("BNEST_WRITE_OWN_MESSAGE_FIXTURE") == "1" do
      File.write!(
        path,
        Jason.encode_to_iodata!(expected_fixture(), pretty: true)
        |> IO.iodata_to_binary()
        |> Kernel.<>("\n")
      )
    end

    committed = path |> File.read!() |> Jason.decode!()

    assert committed == expected_fixture(),
           "the own-message markup changed; write the fixture again with BNEST_WRITE_OWN_MESSAGE_FIXTURE=1"
  end
end
