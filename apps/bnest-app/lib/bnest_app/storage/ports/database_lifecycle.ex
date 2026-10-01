defmodule BnestApp.Storage.Ports.DatabaseLifecycle do
  @moduledoc """
  The authoritative database's process lifecycle: start it against a path (restarting it when
  the path changed), stop it, apply its schema migrations, and name its record backend.
  """

  alias BnestApp.Storage.Ports.RecordBackend

  @callback ensure_started!() :: :ok
  @callback ensure_started!(database_path :: String.t()) :: :ok
  @callback stop() :: :ok
  @callback migrate_schema!() :: :ok
  @callback record_backend() :: {module(), RecordBackend.state()}
end
