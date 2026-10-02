defmodule BnestApp.Backup.Ports.ConfigStore do
  @moduledoc """
  The backup configuration: the one document naming the operator's destination override,
  where it is kept, and the repository whose ignored `data/backup` is the default.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module.

  Semantics every implementation keeps:

    * `read/1` returns the stored document as decoded, whatever its shape (the Backup
      application validates it), `{:error, :absent}` when none is stored,
      `{:error, :invalid_config}` when what is stored is no document, and
      `{:error, :unavailable}` when it cannot be read.
    * `write/2` replaces the whole document at once, readable only by its owner, so a reader
      sees either the previous document or the new one, never a part; it returns
      `{:error, :config_write_failed}` when it cannot.
    * `config_path/1` names where the document is kept, so a destination never contains it.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}

  @callback new() :: handle()
  @callback read(handle()) :: {:ok, term()} | {:error, :absent | :invalid_config | :unavailable}
  @callback write(handle(), document :: map()) :: :ok | {:error, :config_write_failed}
  @callback config_path(handle()) :: String.t()
  @callback repository_root(handle()) :: String.t()

  @spec read(handle()) :: {:ok, term()} | {:error, :absent | :invalid_config | :unavailable}
  def read(store), do: store.adapter.read(store)

  @spec write(handle(), map()) :: :ok | {:error, :config_write_failed}
  def write(store, document), do: store.adapter.write(store, document)

  @spec config_path(handle()) :: String.t()
  def config_path(store), do: store.adapter.config_path(store)

  @spec repository_root(handle()) :: String.t()
  def repository_root(store), do: store.adapter.repository_root(store)
end
