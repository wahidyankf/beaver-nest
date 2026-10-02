defmodule BnestApp.Backup.Ports.ArtifactStore do
  @moduledoc """
  The files of backup destinations: each destination's directory and ownership marker, the
  artifacts a backup promotes there, and the receipts beside them.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module. Paths are absolute.

  Semantics every implementation keeps:

    * `symlink_in_path?/2` holds when `path` or any directory above it is a symbolic link.
    * `prepare_directory/2` creates the directory with its parents, readable only by its
      owner, or returns `{:error, :unavailable}`.
    * `read_marker/2` returns the decoded marker of a directory, `{:error, :absent}` without
      one, and `{:error, :invalid_marker}` when it cannot be read or decoded.
      `write_marker/3` replaces the marker at once, readable only by its owner.
    * `remove/2` deletes a file if it exists. `restrict/2` makes a file readable only by its
      owner, `sync/2` flushes it to stable storage and `promote/3` renames it over its final
      path; each raises when the file is missing.
    * `digest/2` is a file's lowercase hexadecimal SHA-256 and `size/2` its size in bytes;
      both raise when it cannot be read. `regular?/2` holds for an existing regular file.
    * `write_receipt/3` stores a receipt as JSON at its path at once: written beside it,
      readable only by its owner, flushed, then renamed over it.
    * `receipts/2` returns the decoded receipts of a directory, in path order, leaving out
      any it cannot read or decode.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}

  @callback new() :: handle()
  @callback symlink_in_path?(handle(), path :: String.t()) :: boolean()
  @callback prepare_directory(handle(), directory :: String.t()) :: :ok | {:error, :unavailable}
  @callback read_marker(handle(), directory :: String.t()) ::
              {:ok, term()} | {:error, :absent | :invalid_marker}
  @callback write_marker(handle(), directory :: String.t(), marker :: map()) :: :ok
  @callback remove(handle(), path :: String.t()) :: :ok
  @callback restrict(handle(), path :: String.t()) :: :ok
  @callback sync(handle(), path :: String.t()) :: :ok
  @callback promote(handle(), from :: String.t(), to :: String.t()) :: :ok
  @callback digest(handle(), path :: String.t()) :: String.t()
  @callback size(handle(), path :: String.t()) :: non_neg_integer()
  @callback regular?(handle(), path :: String.t()) :: boolean()
  @callback write_receipt(handle(), path :: String.t(), receipt :: map()) :: :ok
  @callback receipts(handle(), directory :: String.t()) :: [term()]

  @spec symlink_in_path?(handle(), String.t()) :: boolean()
  def symlink_in_path?(store, path), do: store.adapter.symlink_in_path?(store, path)

  @spec prepare_directory(handle(), String.t()) :: :ok | {:error, :unavailable}
  def prepare_directory(store, directory), do: store.adapter.prepare_directory(store, directory)

  @spec read_marker(handle(), String.t()) :: {:ok, term()} | {:error, :absent | :invalid_marker}
  def read_marker(store, directory), do: store.adapter.read_marker(store, directory)

  @spec write_marker(handle(), String.t(), map()) :: :ok
  def write_marker(store, directory, marker),
    do: store.adapter.write_marker(store, directory, marker)

  @spec remove(handle(), String.t()) :: :ok
  def remove(store, path), do: store.adapter.remove(store, path)

  @spec restrict(handle(), String.t()) :: :ok
  def restrict(store, path), do: store.adapter.restrict(store, path)

  @spec sync(handle(), String.t()) :: :ok
  def sync(store, path), do: store.adapter.sync(store, path)

  @spec promote(handle(), String.t(), String.t()) :: :ok
  def promote(store, from, to), do: store.adapter.promote(store, from, to)

  @spec digest(handle(), String.t()) :: String.t()
  def digest(store, path), do: store.adapter.digest(store, path)

  @spec size(handle(), String.t()) :: non_neg_integer()
  def size(store, path), do: store.adapter.size(store, path)

  @spec regular?(handle(), String.t()) :: boolean()
  def regular?(store, path), do: store.adapter.regular?(store, path)

  @spec write_receipt(handle(), String.t(), map()) :: :ok
  def write_receipt(store, path, receipt), do: store.adapter.write_receipt(store, path, receipt)

  @spec receipts(handle(), String.t()) :: [term()]
  def receipts(store, directory), do: store.adapter.receipts(store, directory)
end
