defmodule BnestApp.Scheduler.Domain.PolicyTest do
  use ExUnit.Case, async: true

  alias BnestApp.Scheduler.Domain.Policy

  @now ~U[2026-08-30 10:00:00Z]

  test "computes latest eligible and next future fixed-UTC slots" do
    assert Policy.latest_slot("19:00", @now) == ~U[2026-08-29 19:00:00Z]
    assert Policy.next_slot("19:00", @now) == ~U[2026-08-30 19:00:00Z]
    assert Policy.latest_slot("09:00", @now) == ~U[2026-08-30 09:00:00Z]
    assert Policy.next_slot("09:00", @now) == ~U[2026-08-31 09:00:00Z]
  end

  test "validates strict daily time and converts WIB input" do
    assert {:ok, "19:00"} = Policy.wib_to_utc("02:00")
    assert {:ok, "16:30"} = Policy.wib_to_utc("23:30")
    assert {:error, :invalid_time} = Policy.wib_to_utc("2:00")
    assert {:error, :invalid_time} = Policy.wib_to_utc("24:00")
    assert {:error, :invalid_time} = Policy.wib_to_utc(nil)
  end

  test "uses a renewable lease and bounded retry delays" do
    assert Policy.lease_until(@now) == ~U[2026-08-30 10:15:00Z]
    assert Policy.retry_at(1, @now) == ~U[2026-08-30 10:05:00Z]
    assert Policy.retry_at(2, @now) == ~U[2026-08-30 10:30:00Z]
    assert Policy.retry_at(3, @now) == nil
  end

  test "absolute and occurrence expiry preserve the final occurrence" do
    assert Policy.eligible?(%{expiration_kind: "never"}, @now)
    refute Policy.eligible?(%{expiration_kind: "at", expires_at: @now}, @now)
    assert Policy.eligible?(%{expiration_kind: "at", expires_at: "2026-08-30T10:00:01Z"}, @now)

    assert Policy.eligible?(
             %{expiration_kind: "after_occurrences", claimed_occurrences: 1, max_occurrences: 2},
             @now
           )

    refute Policy.eligible?(
             %{expiration_kind: "after_occurrences", claimed_occurrences: 2, max_occurrences: 2},
             @now
           )

    refute Policy.eligible?(%{expiration_kind: "unsupported"}, @now)
  end

  test "parses only UTC ISO 8601 instants" do
    assert Policy.parse_datetime!("2026-08-30T10:00:00Z") == @now

    assert_raise ArgumentError, ~r/UTC ISO 8601/, fn ->
      Policy.parse_datetime!("2026-08-30T17:00:00+07:00")
    end
  end

  test "maps UTC instants to WIB calendar dates" do
    assert Policy.wib_date(~U[2026-08-29 18:59:59Z]) == ~D[2026-08-30]
  end

  test "names setup claims only for safe destination IDs" do
    assert Policy.setup_claim_key("destination-1_a") == "setup:destination-1_a"
    assert Policy.valid_destination_id?("destination-1_a")
    refute Policy.valid_destination_id?("../escape")
    refute Policy.valid_destination_id?("")
  end

  test "an operator's daily edit converts WIB and validates enabled and revision" do
    backup = %{handler_key: "prod_sqlite_backup"}

    assert Policy.daily_edit(backup, %{
             "daily_time_wib" => "02:00",
             "enabled" => "on",
             "revision" => "4"
           }) == {:ok, %{daily_at_utc: "19:00", enabled: true, revision: 4}}

    assert {:ok, %{enabled: false, revision: 2}} =
             Policy.daily_edit(backup, %{"daily_time_wib" => "02:00", "revision" => 2})

    assert {:error, :not_editable} =
             Policy.daily_edit(%{handler_key: "fixture"}, %{"daily_time_wib" => "02:00"})

    assert {:error, :invalid_time} = Policy.daily_edit(backup, %{"revision" => "1"})

    for {enabled, revision, reason} <- [
          {"maybe", "1", :invalid_enabled},
          {"true", "0", :invalid_revision},
          {"true", "1x", :invalid_revision},
          {"true", 0, :invalid_revision},
          {"true", nil, :invalid_revision}
        ] do
      params = %{"daily_time_wib" => "02:00", "enabled" => enabled, "revision" => revision}
      assert Policy.daily_edit(backup, params) == {:error, reason}
    end
  end
end
