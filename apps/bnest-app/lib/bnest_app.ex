defmodule BnestApp do
  @moduledoc """
  BnestApp keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # The root boundary exports nothing and no boundary depends on it. Every core module sits
  # in a context, `SqliteRepo`, `Application`, `Release` or `Mailer`, which the layering
  # scan's rule L3 enforces.
  use Boundary, deps: [], exports: []
end
