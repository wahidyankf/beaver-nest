defmodule BnestApp.FamilyChat.Adapters do
  @moduledoc """
  Family Chat's outbound adapters: the room store over the shared SQLite database, and the
  publisher that broadcasts committed messages to GraphQL subscriptions. Only configuration
  names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [
      BnestApp.FamilyChat,
      BnestApp.SqliteRepo,
      BnestApp.Storage,
      BnestAppWeb,
      Absinthe.Subscription,
      Ecto.Migrator
    ],
    exports: :all
end
