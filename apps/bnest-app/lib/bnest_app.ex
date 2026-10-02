defmodule BnestApp do
  @moduledoc """
  BnestApp keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  # Temporary. Every entry is a module not yet moved into a strict context
  # boundary that a module outside this root calls. Delete entries as each
  # context lands; the closure unit requires this list empty.
  @legacy_exports [
    AdminConfig.Registry,
    Deployment
  ]

  # The legacy modules left here call no context facade and no infrastructure directly.
  use Boundary,
    deps: [],
    exports: @legacy_exports
end
