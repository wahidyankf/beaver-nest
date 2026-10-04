defmodule BnestAppCli do
  @moduledoc """
  The command-line inbound adapter: every `mix bnest.*` task classifies into this boundary,
  so a task may call only the context facades it lists.
  """

  use Boundary,
    deps: [
      BnestApp.Backup,
      BnestApp.Identity,
      BnestApp.Scheduler,
      BnestApp.Storage
    ]
end
