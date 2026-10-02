defmodule BnestApp.Backup.Ports.DatabaseSnapshot do
  @moduledoc """
  The live database a backup snapshots, and the restore of a snapshot. Family Chat's room,
  messages, push subscriptions and deliveries are what a restore reads back.

  Every callback except `new/0` takes the snapshot's handle first. The handle is a map whose
  `:adapter` key names the implementing module.

  Semantics every implementation keeps:

    * `source_path/1` names the live database, so a destination never overlaps its
      directory, and `source_generation/1` its storage generation (nil before one is
      recorded).
    * `vacuum_into/3` writes a consistent copy of the live database to `path` on a
      connection of its own, without holding up ordinary traffic. Past `timeout_ms` it
      cancels the copy and returns `{:error, :timeout}`; any other failure is
      `{:error, :io_failed}`. A failed copy may leave a partial file at `path`.
    * `prove/2` checks a copy independently: its integrity, the schema versions it holds and
      a digest of its logical schema, or `{:error, :corrupt}`.
    * `restore/2` restores a copy into a fresh, ownership-marked root of its own, never the
      caller's choice of path, reads back what it holds, then removes that root. It returns
      `{:error, :restore_failed}` when the copy cannot be restored or read.
  """

  alias BnestApp.Backup.Domain.RestoreEvidence

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type proof :: %{schema_versions: [integer()], logical_sha256: String.t()}

  @callback new() :: handle()
  @callback source_path(handle()) :: String.t()
  @callback source_generation(handle()) :: String.t() | nil
  @callback vacuum_into(handle(), path :: String.t(), timeout_ms :: pos_integer()) ::
              :ok | {:error, :io_failed | :timeout}
  @callback prove(handle(), path :: String.t()) :: {:ok, proof()} | {:error, :corrupt}
  @callback restore(handle(), artifact_path :: String.t()) ::
              {:ok, RestoreEvidence.facts()} | {:error, :restore_failed}

  @spec source_path(handle()) :: String.t()
  def source_path(snapshot), do: snapshot.adapter.source_path(snapshot)

  @spec source_generation(handle()) :: String.t() | nil
  def source_generation(snapshot), do: snapshot.adapter.source_generation(snapshot)

  @spec vacuum_into(handle(), String.t(), pos_integer()) :: :ok | {:error, :io_failed | :timeout}
  def vacuum_into(snapshot, path, timeout_ms),
    do: snapshot.adapter.vacuum_into(snapshot, path, timeout_ms)

  @spec prove(handle(), String.t()) :: {:ok, proof()} | {:error, :corrupt}
  def prove(snapshot, path), do: snapshot.adapter.prove(snapshot, path)

  @spec restore(handle(), String.t()) ::
          {:ok, RestoreEvidence.facts()} | {:error, :restore_failed}
  def restore(snapshot, artifact_path), do: snapshot.adapter.restore(snapshot, artifact_path)
end
