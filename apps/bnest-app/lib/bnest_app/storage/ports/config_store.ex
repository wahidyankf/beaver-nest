defmodule BnestApp.Storage.Ports.ConfigStore do
  @moduledoc """
  The storage pointer: where the authoritative database lives, which phase owns the records
  (`:flat_primary` or `:sqlite_primary`), and the relocation generation.
  """

  @type phase :: :flat_primary | :sqlite_primary

  @callback pointer_path() :: String.t()
  @callback read() :: {:ok, map()} | {:error, :absent | :invalid}
  @callback write!(map()) :: :ok
  @callback resolved_database_path() :: String.t()
  @callback phase() :: phase()
  @callback database_generation() :: String.t() | nil
  @callback validate_directory(String.t()) :: {:ok, String.t()} | {:error, atom()}
  @callback ensure_default!() :: map()
  @callback activate_sqlite_primary!() :: map()
  @callback relocate!(String.t(), String.t()) :: map()
  @callback mark_legacy_retired!() :: map()
  @callback restore!(map()) :: map()
end
