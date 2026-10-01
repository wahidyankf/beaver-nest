defmodule BnestApp.Storage.Ports.Lock do
  @moduledoc """
  The storage lease. Any number of shared holders may run together; an exclusive holder waits
  for every shared lease to drain and keeps new ones out until it finishes.
  """

  @callback with_shared((-> result)) :: result when result: var
  @callback with_exclusive((-> result)) :: result when result: var
end
