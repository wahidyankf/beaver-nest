defmodule ExBdd.ReloadableHooks do
  @moduledoc """
  Used only by `ExBdd.HooksTest` to prove `collect_hooks/1` loads
  modules that are compiled into the application but not yet loaded
  (the test unloads this module first). Don't reference it elsewhere —
  a stray reference would load it and mask a regression.
  """

  use ExBdd.Hooks

  before_scenario _context do
    :ok
  end
end
