defmodule BnestApp.Backup.Ports do
  @moduledoc """
  The behaviours the Backup application needs from the outside world: the backup
  configuration, the destination's files, the live database it snapshots, the destination's
  free space and the repository's ignore rules. Adapters under `BnestApp.Backup.Adapters`
  implement them; configuration chooses which.
  """

  use Boundary, type: :strict, deps: [BnestApp.Backup.Domain], exports: :all
end
