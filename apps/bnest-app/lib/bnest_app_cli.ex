defmodule BnestAppCli do
  @moduledoc """
  The command-line inbound adapter: every `mix bnest.*` task classifies into this boundary,
  so a task may call only the context facades it lists.
  """

  use Boundary,
    deps: [
      BnestApp,
      # legacy: bnest.identity.benchmark; removed in U5
      Argon2,
      # legacy: bnest.storage.migrate; removed in U4
      Ecto.Migrator
    ]
end
