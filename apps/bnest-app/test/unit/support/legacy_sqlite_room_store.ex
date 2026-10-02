defmodule BnestApp.Test.LegacySqliteRoomStore do
  @moduledoc """
  Temporary. Backup (U12) still snapshots Family Chat's SQLite database and reaches it
  through `BnestApp.FamilyChat`, so a unit test or scenario that drives a backup, the
  Scheduler's scheduled one included, selects the SQLite room store for itself; every
  other unit test keeps the in-memory one `config/test.exs` selects. The Scheduler left
  it in U11, when its schedules and runs moved to an in-memory store at this layer. U12
  deletes the remaining callers, this module and its allow-list line in
  `test/behaviour/verify.exs`.
  """

  @sqlite_room_store BnestApp.FamilyChat.Adapters.SqliteRoomStore

  @doc """
  Selects the SQLite room store until the calling test exits, when the previous adapters
  come back.
  """
  @spec select!() :: :ok
  def select! do
    previous = Application.fetch_env!(:bnest_app, BnestApp.FamilyChat)

    Application.put_env(
      :bnest_app,
      BnestApp.FamilyChat,
      Keyword.put(previous, :room_store, @sqlite_room_store)
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, BnestApp.FamilyChat, previous)
    end)

    :ok
  end
end
