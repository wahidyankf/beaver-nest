defmodule BnestApp.DataRepository.CanonicalJsonTest do
  use ExUnit.Case, async: true

  alias BnestApp.DataRepository.CanonicalJson

  test "sorts object keys recursively before encoding" do
    a = %{"b" => 1, "a" => %{"z" => 1, "y" => 2}}
    b = %{"a" => %{"y" => 2, "z" => 1}, "b" => 1}
    assert CanonicalJson.encode(a) == CanonicalJson.encode(b)
    assert CanonicalJson.encode(a) == ~s({"a":{"y":2,"z":1},"b":1})
  end

  test "produces the same checksum regardless of Elixir map insertion order" do
    a = %{"one" => 1, "two" => 2}
    b = %{"two" => 2, "one" => 1}
    assert CanonicalJson.sha256(a) == CanonicalJson.sha256(b)
    assert String.length(CanonicalJson.sha256(a)) == 64
  end

  test "changing a value changes the checksum" do
    refute CanonicalJson.sha256(%{"a" => 1}) == CanonicalJson.sha256(%{"a" => 2})
  end

  test "encodes list values in original order without sorting" do
    record = %{"items" => [3, 1, %{"b" => 2, "a" => 1}]}
    assert CanonicalJson.encode(record) == ~s({"items":[3,1,{"a":1,"b":2}]})
  end
end
