defmodule BnestApp.Backup.Domain do
  @moduledoc """
  The Backup domain: which destinations are safe, the ownership marker and receipt a backup
  writes, how much free space a snapshot needs, which owned backups retention keeps, and the
  redacted evidence a restore reports. Pure: no file, process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
