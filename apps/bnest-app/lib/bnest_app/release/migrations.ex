defmodule BnestApp.Release.Migrations do
  @moduledoc """
  Aggregates every domain's release-time migration/verification step behind
  one arity-0 entry point, so restart/recovery proof and future release
  tooling call a single function rather than enumerating each domain.
  """

  alias BnestApp.Release.Migrations.FamilyChat
  alias BnestApp.Release.Migrations.PersistentSchedules

  @spec apply_and_verify!() :: :ok
  def apply_and_verify! do
    :ok = PersistentSchedules.apply_and_verify!(DateTime.utc_now())
    :ok = FamilyChat.apply_and_verify!()
    :ok
  end
end
