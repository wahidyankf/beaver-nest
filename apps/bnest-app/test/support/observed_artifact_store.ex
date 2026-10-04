defmodule BnestApp.Test.ObservedArtifactStore do
  @moduledoc """
  Test-only `BnestApp.Backup.Ports.ArtifactStore` that wraps the layer's configured store and
  records every read of an artifact's state (`regular?/2`, `digest/2` and `size/2`) made by a
  process other than the test's own, which is what a reconciliation does. Every call, and its
  result, is the wrapped store's own.

  A scenario uses it to observe the page's integrity check without a hook in production code:

    * `read_count/0` shows whether any reconciliation ran at all (a denied visitor causes none),
      and that none is still reading once the check was cancelled;
    * `install!/1` with `block: path` makes a read of that one path wait until its process is
      killed (or the test ends), standing in for a reconciliation that outlasts the page's
      ceiling; `blocked_pids/0` names the processes that are waiting, so a test can monitor
      them and see them die.

  The test's own process is never recorded and never blocked, so the oracles that read the
  destination through the same store (`BnestApp.Test.BackupIntegrity`) neither add to the
  count nor wait. The only seam is the `:artifact_store` adapter configuration, the one
  `BnestApp.Test.UnreadableArtifactStore` uses; `install!/1` makes this the configured store
  until the calling test exits.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour BnestApp.Backup.Ports.ArtifactStore

  alias BnestApp.Backup
  alias BnestApp.Backup.Ports.ArtifactStore

  @table :bnest_observed_artifact_reads

  @spec install!(keyword()) :: :ok
  def install!(options \\ []) do
    previous_backup = Application.fetch_env!(:bnest_app, Backup)
    :ets.new(@table, [:named_table, :public, :duplicate_bag])

    Application.put_env(:bnest_app, __MODULE__,
      wrapped: Keyword.fetch!(previous_backup, :artifact_store),
      owner: self(),
      block_path: Keyword.get(options, :block)
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

  @doc """
  Lets every read that starts from now on pass: a reader already waiting keeps waiting, until
  it is killed or the test ends. A test uses it to hold one check mid-read while a later one
  runs freely.
  """
  @spec unblock!() :: :ok
  def unblock! do
    settings = Application.fetch_env!(:bnest_app, __MODULE__)
    Application.put_env(:bnest_app, __MODULE__, Keyword.put(settings, :block_path, nil))
  end

  @doc "How many artifact reads processes other than the test's own have made so far."
  @spec read_count() :: non_neg_integer()
  def read_count, do: length(:ets.match_object(@table, {:read, :_, :_, :_}))

  @doc "The processes that are, or were, waiting inside the blocked read."
  @spec blocked_pids() :: [pid()]
  def blocked_pids, do: Enum.map(:ets.match_object(@table, {:blocked, :_, :_}), &elem(&1, 1))

  @impl true
  def new do
    settings = Application.fetch_env!(:bnest_app, __MODULE__)
    wrapped = Keyword.fetch!(settings, :wrapped)

    %{
      adapter: __MODULE__,
      wrapped: wrapped.new(),
      owner: Keyword.fetch!(settings, :owner),
      block_path: Keyword.fetch!(settings, :block_path)
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
  def digest(store, path), do: ArtifactStore.digest(observed(store, :digest, path), path)

  @impl true
  def size(store, path), do: ArtifactStore.size(observed(store, :size, path), path)

  @impl true
  def regular?(store, path), do: ArtifactStore.regular?(observed(store, :regular?, path), path)

  @impl true
  def write_receipt(%{wrapped: wrapped}, path, receipt),
    do: ArtifactStore.write_receipt(wrapped, path, receipt)

  @impl true
  def receipts(%{wrapped: wrapped}, directory), do: ArtifactStore.receipts(wrapped, directory)

  # Records the read of a process other than the test's, and parks that process when the read
  # is of the blocked path. The park ends when the process is killed or the test's process exits,
  # so no scenario can leave a reader behind.
  defp observed(%{owner: owner, block_path: block_path, wrapped: wrapped}, operation, path) do
    if self() != owner do
      record({:read, self(), operation, path})

      if path == block_path do
        record({:blocked, self(), path})
        park(owner)
      end
    end

    wrapped
  end

  defp park(owner) do
    reference = Process.monitor(owner)

    receive do
      {:DOWN, ^reference, :process, ^owner, _reason} -> :ok
    end
  end

  # The table belongs to the test's process, so it is gone once the test is over.
  defp record(row) do
    :ets.insert(@table, row)
  rescue
    ArgumentError -> :ok
  end
end
