defmodule BnestAppWeb.BootstrapControllerTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.BootstrapController

  # The setup form posts its account cards as `accounts[<index>][...]`, which Plug decodes
  # into a map keyed by the index text. Setup and its error draft must keep the cards in
  # the order the form showed them, so the keys order by their numeric index, not as text
  # ("10" would otherwise come before "2").
  test "account cards keep the form's order past nine cards" do
    params = Map.new(0..11, &{Integer.to_string(&1), %{"username" => "test-user-#{&1}"}})

    assert params |> BootstrapController.ordered_account_params() |> Enum.map(&elem(&1, 0)) ==
             Enum.map(0..11, &Integer.to_string/1)
  end

  test "keys that are not form indexes order after every indexed card" do
    params = %{"1" => %{}, "x" => %{}, "0" => %{}}

    assert params |> BootstrapController.ordered_account_params() |> Enum.map(&elem(&1, 0)) ==
             ["0", "1", "x"]
  end
end
