defmodule ExBdd.Messages.EmitterTest do
  use ExUnit.Case, async: false

  alias ExBdd.Messages.Emitter

  setup do
    ExBdd.RunCoordinator.ensure_started()
    :ok
  end

  test "returns nil when a message session has no step id" do
    assert Emitter.step_message(%{case_started_id: "case"}, nil) == nil
  end

  test "runs hooks without message overrides when the positional id is absent" do
    around = Emitter.hook_around(%{before_ids: [], after_ids: []}, :before)

    assert :plain ==
             around.(0, nil, fn overrides ->
               assert overrides == %{}
               :plain
             end)
  end

  test "reports pending hook results with and without a message" do
    session = %{case_started_id: "case", before_ids: ["step"], after_ids: []}
    around = Emitter.hook_around(session, :before)

    assert :pending == around.(0, nil, fn _overrides -> :pending end)

    assert {:pending, "waiting"} ==
             around.(0, nil, fn _overrides -> {:pending, "waiting"} end)
  end
end
