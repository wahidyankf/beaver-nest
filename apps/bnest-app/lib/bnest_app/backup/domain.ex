defmodule BnestApp.Backup.Domain do
  @moduledoc """
  The Backup domain: which destinations are safe, the ownership marker and receipt a backup
  writes, how much free space a snapshot needs, which owned backups retention keeps, and the
  redacted evidence a restore reports and the drill's words for it. Pure: no file, process,
  clock, or database access. `Jason` is allowed because the evidence is a JSON document the
  drill report reads.
  """

  use Boundary, type: :strict, deps: [Jason], exports: :all
end
