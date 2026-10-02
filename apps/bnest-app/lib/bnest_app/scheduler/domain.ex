defmodule BnestApp.Scheduler.Domain do
  @moduledoc """
  The Scheduler domain: daily UTC slots, the WIB conversion an operator edits in, claim
  leases and retry waits, expiration, and the schedule edits it accepts. Pure: no file,
  process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
