defmodule BnestApp.Test.UnreadableArtifactStore do
  @moduledoc """
  Test-only `BnestApp.Backup.Ports.ArtifactStore` that wraps the layer's configured store and
  raises when a file's state is read at one named path (`regular?/2`, `digest/2` and
  `size/2`), as a disk read error would. Every other call, and every other path, is the
  wrapped store's own.

  A scenario names a path that nothing but reconciliation reads: an artifact its ledger lists
  but that no valid receipt owns, which backup, receipt writing and retention never touch. A
  post-run reconciliation then raises while the run itself succeeds, with no hook in
  production code: the only seam is the `:artifact_store` adapter configuration.

  `install!/1` makes it Backup's configured store until the calling test exits.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour BnestApp.Backup.Ports.ArtifactStore

  alias BnestApp.Backup
  alias BnestApp.Backup.Ports.ArtifactStore

  @spec install!(String.t()) :: :ok
  def install!(unreadable_path) when is_binary(unreadable_path) do
    previous_backup = Application.fetch_env!(:bnest_app, Backup)

    Application.put_env(:bnest_app, __MODULE__,
      wrapped: Keyword.fetch!(previous_backup, :artifact_store),
      unreadable_path: unreadable_path
    )

    Application.put_env(
      :bnest_app,
      Backup,
      Keyword.put(previous_backup, :artifact_store, __MODULE__)
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, Backup, previous_backup)
      Application.delete_env(:bnest_app, __MODULE__)
    end)
  end

  @impl true
  def new do
    settings = Application.fetch_env!(:bnest_app, __MODULE__)
    wrapped = Keyword.fetch!(settings, :wrapped)

    %{
      adapter: __MODULE__,
      wrapped: wrapped.new(),
      unreadable_path: Keyword.fetch!(settings, :unreadable_path)
    }
  end

  @impl true
  def symlink_in_path?(%{wrapped: wrapped}, path),
    do: ArtifactStore.symlink_in_path?(wrapped, path)

  @impl true
  def prepare_directory(%{wrapped: wrapped}, directory),
    do: ArtifactStore.prepare_directory(wrapped, directory)

  @impl true
  def read_marker(%{wrapped: wrapped}, directory),
    do: ArtifactStore.read_marker(wrapped, directory)

  @impl true
  def write_marker(%{wrapped: wrapped}, directory, marker),
    do: ArtifactStore.write_marker(wrapped, directory, marker)

  @impl true
  def remove(%{wrapped: wrapped}, path), do: ArtifactStore.remove(wrapped, path)

  @impl true
  def restrict(%{wrapped: wrapped}, path), do: ArtifactStore.restrict(wrapped, path)

  @impl true
  def sync(%{wrapped: wrapped}, path), do: ArtifactStore.sync(wrapped, path)

  @impl true
  def promote(%{wrapped: wrapped}, from, to), do: ArtifactStore.promote(wrapped, from, to)

  @impl true
  def digest(store, path), do: ArtifactStore.digest(readable!(store, path), path)

  @impl true
  def size(store, path), do: ArtifactStore.size(readable!(store, path), path)

  @impl true
  def regular?(store, path), do: ArtifactStore.regular?(readable!(store, path), path)

  @impl true
  def write_receipt(%{wrapped: wrapped}, path, receipt),
    do: ArtifactStore.write_receipt(wrapped, path, receipt)

  @impl true
  def receipts(%{wrapped: wrapped}, directory), do: ArtifactStore.receipts(wrapped, directory)

  defp readable!(%{unreadable_path: path}, path),
    do: raise(RuntimeError, "the synthetic artifact cannot be read")

  defp readable!(%{wrapped: wrapped}, _path), do: wrapped
end
