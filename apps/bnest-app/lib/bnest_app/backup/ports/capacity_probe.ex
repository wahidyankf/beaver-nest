defmodule BnestApp.Backup.Ports.CapacityProbe do
  @moduledoc """
  Measures what `BnestApp.Backup.Domain.CapacityPolicy` decides on: a destination's free
  bytes and the live database's page geometry and WAL size. `measure/2` takes the probe's
  handle first (a map whose `:adapter` key names the implementing module) and returns
  `{:error, :unmeasurable}` when any of them cannot be measured, which the Backup
  application treats as too little space.
  """

  alias BnestApp.Backup.Domain.CapacityPolicy

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}

  @callback new() :: handle()
  @callback measure(handle(), directory :: String.t()) ::
              {:ok, CapacityPolicy.measurement()} | {:error, :unmeasurable}

  @spec measure(handle(), String.t()) ::
          {:ok, CapacityPolicy.measurement()} | {:error, :unmeasurable}
  def measure(probe, directory), do: probe.adapter.measure(probe, directory)
end
