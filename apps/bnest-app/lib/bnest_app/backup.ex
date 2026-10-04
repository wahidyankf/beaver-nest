defmodule BnestApp.Backup do
  @moduledoc """
  The Backup bounded context: verified backups of the production SQLite database to an
  owned destination, their retention, and restore into an isolated root.

  This module is the context's application-service facade. The admin schedules page reads
  and saves the destination through it, and the Scheduler's backup task
  (`BnestApp.Backup.Adapters.ScheduledBackupTask`) runs each claimed backup through it, so
  the task runs no SQL of its own (`family_chat_operations.feature`'s "the handler
  delegates to the public 'BnestApp.Backup' service without direct SQL"). This module knows
  nothing about Scheduler claims or leases beyond the receipt it records for one.

  One backup run measures the destination's capacity, snapshots the live database on a
  connection of its own with a cooperative timeout, proves the copy independently, and only
  then promotes it. Every effect goes through a port in `BnestApp.Backup.Ports`, whose
  adapters come from `config :bnest_app, BnestApp.Backup` (`:config_store`,
  `:artifact_store`, `:database_snapshot`, `:capacity_probe`, `:ignore_check`); the rules
  are the pure `BnestApp.Backup.Domain`.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [Jason],
    exports: [{Domain, []}, {Ports, []}]

  alias BnestApp.Backup.Domain.CapacityPolicy
  alias BnestApp.Backup.Domain.Location
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.Backup.Domain.Reconciliation
  alias BnestApp.Backup.Domain.RestoreEvidence
  alias BnestApp.Backup.Domain.Retention
  alias BnestApp.Backup.Ports.ArtifactStore
  alias BnestApp.Backup.Ports.CapacityProbe
  alias BnestApp.Backup.Ports.ConfigStore
  alias BnestApp.Backup.Ports.DatabaseSnapshot
  alias BnestApp.Backup.Ports.IgnoreCheck

  @default_timeout_ms 1_800_000

  @type location :: %{directory: String.t(), destination_id: String.t()}

  @type artifact :: %{
          path: String.t(),
          basename: String.t(),
          sha256: String.t(),
          bytes: non_neg_integer(),
          quick_check: String.t(),
          schema_versions: [integer()],
          logical_proof_sha256: String.t(),
          source_generation: String.t() | nil
        }

  @doc """
  The configured adapter for a Backup port: `:config_store`, `:artifact_store`,
  `:database_snapshot`, `:capacity_probe` or `:ignore_check`.
  """
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc """
  The destination backups go to: the saved override, or else the repository's ignored
  `data/backup`. It is validated, created when missing and marked as owned, so its
  destination ID stays the same across calls.
  """
  @spec destination() :: {:ok, location()} | {:error, atom()}
  def destination do
    with {:ok, directory} <- configured_directory() do
      ensure(directory, DateTime.utc_now())
    end
  end

  @doc """
  The destination as `destination/0` names it, read and never prepared: the same
  configuration and checks, then the marker the directory already holds. It creates no
  directory, writes no marker and changes no mode, so a missing directory or marker is
  `{:error, :absent}` and an unreadable marker `{:error, :invalid_marker}`.
  """
  @spec read_destination() :: {:ok, location()} | {:error, atom()}
  def read_destination do
    with {:ok, directory} <- configured_directory(),
         {:ok, directory} <- validate(directory, config_store()),
         {:ok, marker} <- read_marker(artifact_store(), directory) do
      {:ok, %{directory: directory, destination_id: marker["destinationId"]}}
    end
  end

  @doc """
  Saves `directory` as the destination override once it is validated, created and marked
  as owned, and returns the destination.
  """
  @spec save_destination(term()) :: {:ok, location()} | {:error, atom()}
  def save_destination(directory) do
    now = DateTime.utc_now()

    with {:ok, location} <- ensure(directory, now),
         :ok <- ConfigStore.write(config_store(), Location.config_document(location.directory)) do
      {:ok, location}
    end
  end

  @doc "The repository's default destination, used when no override is saved."
  @spec default_directory() :: String.t()
  def default_directory,
    do: Location.default_directory(ConfigStore.repository_root(config_store()))

  @doc "Validates `directory` as a destination without creating or saving anything."
  @spec validate_destination(term()) :: {:ok, String.t()} | {:error, atom()}
  def validate_destination(directory), do: validate(directory, config_store())

  @doc """
  Runs one full backup into the configured destination, or into
  `opts[:destination_directory]`, a destination already resolved.

  Options:
    * `:deadline` -- the `DateTime` to treat as "now" for the artifact's
      timestamp-derived basename. Defaults to `DateTime.utc_now/0`; production
      callers never need to pass this.
    * `:destination_directory` -- a destination the caller already resolved.
    * `:before_promote` -- run right before the proved candidate is promoted; an
      `{:error, category}` discards it as a retryable failure of that category.
  """
  @spec run(keyword()) ::
          {:ok, map()} | {:error, {:retryable, atom(), artifact() | nil}} | {:error, atom()}
  def run(opts \\ []) do
    now = Keyword.get(opts, :deadline, DateTime.utc_now())
    started_at = System.monotonic_time(:millisecond)
    :telemetry.execute([:bnest_app, :backup, :start], %{system_time: System.system_time()}, %{})

    result =
      with {:ok, directory} <- resolve_directory(opts),
           :ok <- check_capacity(directory) do
        create_backup(directory, now, opts)
      end

    :telemetry.execute(
      [:bnest_app, :backup, :stop],
      %{duration_ms: System.monotonic_time(:millisecond) - started_at},
      %{outcome: outcome_tag(result)}
    )

    result
  end

  @doc """
  Writes the receipt of `claim`'s run beside its verified `artifact` in `location`, and
  returns it.
  """
  @spec record_receipt(map(), location(), DateTime.t(), artifact()) :: {:ok, map()}
  def record_receipt(claim, location, %DateTime{} = now, artifact) do
    receipt = Receipt.build(claim, location, now, artifact)
    :ok = ArtifactStore.write_receipt(artifact_store(), Receipt.path(artifact.path), receipt)
    {:ok, receipt}
  end

  @doc """
  The receipts `directory` owns, newest first: valid receipts of its marked destination
  whose artifact is present and unchanged.
  """
  @spec owned_receipts(String.t()) :: [map()]
  def owned_receipts(directory) do
    artifacts = artifact_store()

    case read_marker(artifacts, directory) do
      {:ok, marker} ->
        artifacts
        |> ArtifactStore.receipts(directory)
        |> Enum.filter(&owned?(artifacts, &1, directory, marker["destinationId"]))
        |> Retention.newest_first()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Removes every owned pair in `directory` that retention does not keep, and returns the
  run IDs of those it keeps. Unknown files are never touched.
  """
  @spec retain_owned(String.t()) :: {:ok, MapSet.t(String.t())}
  def retain_owned(directory) do
    artifacts = artifact_store()
    receipts = owned_receipts(directory)
    kept = Retention.retained_run_ids(receipts)

    Enum.each(receipts, fn receipt ->
      unless MapSet.member?(kept, receipt["runId"]) do
        artifact_path = Path.join(directory, receipt["artifactBasename"])
        :ok = ArtifactStore.remove(artifacts, artifact_path)
        :ok = ArtifactStore.remove(artifacts, Receipt.path(artifact_path))
      end
    end)

    {:ok, kept}
  end

  @doc """
  Checks the verified ledger `runs` (see `BnestApp.Backup.Domain.Reconciliation`) against the
  artifacts `directory` holds, and returns each run's outcome, oldest first: `:present`,
  `:missing`, `:changed`, or `:not_expected` when retention would legitimately have removed
  it. The runs are data, so this context knows nothing of the Scheduler that recorded them.

  Read-only: it asks only whether an expected run's artifact is a regular file and, when it
  is, for its digest and size; it writes and removes nothing, and it reads no file the ledger
  does not list. A read the artifact store cannot make raises, so the caller decides how an
  unreadable destination is reported. `directory` must be an absolute path.
  """
  @spec reconcile(term(), [Reconciliation.run()]) ::
          {:ok, [Reconciliation.result()]} | {:error, :not_absolute | :invalid_directory}
  def reconcile(directory, runs) when is_list(runs) do
    with {:ok, directory} <- Location.absolute(directory) do
      observed = observe(artifact_store(), directory, Reconciliation.expected(runs))
      {:ok, Reconciliation.classify(runs, observed)}
    end
  end

  @doc """
  Restores an artifact (as returned in `run/1`'s success map) into a fresh,
  function-owned, ownership-marked temporary root -- never the caller's
  choice of path, so restore can never target (or be mistaken for) a live
  database. Returns redacted `evidence` (structural counts/ids/states only,
  never a message body or push credential) proving the room, ordered
  messages, subscription structure, and delivery states are all readable
  back out of the restored copy.
  """
  @spec restore(map()) :: {:ok, map()} | {:error, atom()}
  def restore(%{path: artifact_path}) when is_binary(artifact_path) do
    case DatabaseSnapshot.restore(database_snapshot(), artifact_path) do
      {:ok, facts} -> {:ok, %{evidence: Jason.encode!(RestoreEvidence.document(facts))}}
      {:error, :restore_failed} -> {:error, :restore_failed}
    end
  end

  def restore(_invalid_artifact), do: {:error, :invalid_artifact}

  @doc """
  The artifact a restore may act on, from what an operator typed: `argument` must be the bare
  name of a regular file directly inside `directory`, and the result names it as
  `restore/1` takes it. Anything else is `{:error, :refused}`: a path of any kind, a name that
  climbs (`..`) or stays (`.`, empty), a file the directory does not hold, a directory, and a
  symbolic link, which a test for a regular file alone would follow out of the destination.
  `directory` must be a destination already resolved (`read_destination/0`).
  """
  @spec restore_target(String.t(), term()) :: {:ok, %{path: String.t()}} | {:error, :refused}
  def restore_target(directory, argument) when is_binary(directory) do
    with true <- bare_name?(argument),
         path = Path.join(directory, argument),
         artifacts = artifact_store(),
         false <- ArtifactStore.symlink_in_path?(artifacts, path),
         true <- ArtifactStore.regular?(artifacts, path) do
      {:ok, %{path: path}}
    else
      _refused -> {:error, :refused}
    end
  end

  @doc """
  The restore roots the operating system's temporary directory holds now, in order. A restore
  creates one and removes it; a root present after a restore that was absent before it is one
  the restore failed to remove.
  """
  @spec restore_roots() :: [String.t()]
  def restore_roots, do: DatabaseSnapshot.restore_roots(database_snapshot())

  # `:destination_directory`, when given, is already a validated/created
  # directory (`ScheduledBackupTask`'s own `destination/0` result) --
  # resolving it again here would be redundant.
  defp resolve_directory(opts) do
    case Keyword.get(opts, :destination_directory) do
      nil ->
        case destination() do
          {:ok, location} -> {:ok, location.directory}
          {:error, reason} -> {:error, reason}
        end

      directory ->
        {:ok, directory}
    end
  end

  # A capacity preflight that cannot even measure (destination or source
  # unreadable) fails closed as insufficient, never past the caller's
  # retryable-failure contract.
  defp check_capacity(directory) do
    with {:ok, measurement} <- CapacityProbe.measure(capacity_probe(), directory),
         true <- CapacityPolicy.sufficient?(measurement) do
      :ok
    else
      _insufficient_or_unmeasurable -> {:error, {:retryable, :insufficient_capacity, nil}}
    end
  end

  defp create_backup(directory, now, opts) do
    artifacts = artifact_store()
    snapshot = database_snapshot()
    timestamp = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    run_id = Base.url_encode64(:crypto.strong_rand_bytes(15), padding: false)
    artifact_basename = "bnest-prod-#{timestamp}-#{run_id}.sqlite3"
    artifact_path = Path.join(directory, artifact_basename)
    partial_path = artifact_path <> ".partial"
    :ok = ArtifactStore.remove(artifacts, partial_path)

    before_promote = Keyword.get(opts, :before_promote, fn -> :ok end)

    case DatabaseSnapshot.vacuum_into(snapshot, partial_path, timeout_ms()) do
      :ok ->
        candidate = %{
          partial_path: partial_path,
          path: artifact_path,
          basename: artifact_basename
        }

        finalize_artifact(artifacts, snapshot, candidate, before_promote)

      {:error, category} ->
        :ok = ArtifactStore.remove(artifacts, partial_path)
        {:error, {:retryable, category, nil}}
    end
  end

  defp finalize_artifact(artifacts, snapshot, candidate, before_promote) do
    :ok = ArtifactStore.restrict(artifacts, candidate.partial_path)

    case DatabaseSnapshot.prove(snapshot, candidate.partial_path) do
      {:ok, proof} ->
        :ok = ArtifactStore.sync(artifacts, candidate.partial_path)
        promote(artifacts, snapshot, candidate, proof, before_promote)

      {:error, :corrupt} ->
        :ok = ArtifactStore.remove(artifacts, candidate.partial_path)
        # `integrity_failed`: tech-doc 009's documented category name for this case, from its
        # closed, safe retryable-category vocabulary ("insufficient_capacity, busy, timeout,
        # cancelled, integrity_failed, stale_claim, or io_failed").
        {:error, {:retryable, :integrity_failed, nil}}
    end
  end

  # `before_promote` runs as late as possible -- right before the rename
  # that makes this artifact the canonical, retained one -- to keep the
  # race window between "are we still the owner of this run" and "commit
  # the result" as small as possible. The Scheduler's backup task uses this
  # to re-check its claim's lease without this module ever needing to know
  # what a Scheduler claim is.
  defp promote(artifacts, snapshot, candidate, proof, before_promote) do
    case before_promote.() do
      :ok ->
        :ok = ArtifactStore.promote(artifacts, candidate.partial_path, candidate.path)

        {:ok,
         %{
           path: candidate.path,
           basename: candidate.basename,
           sha256: ArtifactStore.digest(artifacts, candidate.path),
           bytes: ArtifactStore.size(artifacts, candidate.path),
           quick_check: "ok",
           schema_versions: proof.schema_versions,
           logical_proof_sha256: proof.logical_sha256,
           source_generation: DatabaseSnapshot.source_generation(snapshot)
         }}

      {:error, reason} ->
        :ok = ArtifactStore.remove(artifacts, candidate.partial_path)
        {:error, {:retryable, reason, nil}}
    end
  end

  # The destination checks run in this order, each only after the one before passed, so a
  # refusal always names the first rule a directory breaks.
  defp validate(directory, config) do
    with {:ok, expanded} <- Location.absolute(directory),
         :ok <- reject_symlink(expanded),
         :ok <-
           Location.outside_source(expanded, DatabaseSnapshot.source_path(database_snapshot())),
         :ok <- Location.outside_config(expanded, ConfigStore.config_path(config)),
         repository_root = ConfigStore.repository_root(config),
         :ok <- Location.repository_placement(expanded, repository_root),
         :ok <- require_ignored_default(expanded, repository_root) do
      {:ok, expanded}
    end
  end

  defp reject_symlink(directory) do
    if ArtifactStore.symlink_in_path?(artifact_store(), directory),
      do: {:error, :symlink},
      else: :ok
  end

  defp require_ignored_default(directory, repository_root) do
    cond do
      not Location.default?(directory, repository_root) ->
        :ok

      IgnoreCheck.ignored?(ignore_check(), repository_root, Location.default_relative_path()) ->
        :ok

      true ->
        {:error, :default_not_ignored}
    end
  end

  # The directory the configuration names, or else the repository's default, before any check.
  defp configured_directory do
    config = config_store()

    case ConfigStore.read(config) do
      {:ok, document} -> Location.configured_directory(document)
      {:error, :absent} -> {:ok, Location.default_directory(ConfigStore.repository_root(config))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure(directory, %DateTime{} = now) do
    artifacts = artifact_store()

    with {:ok, directory} <- validate(directory, config_store()),
         :ok <- ArtifactStore.prepare_directory(artifacts, directory),
         {:ok, marker} <- read_or_create_marker(artifacts, directory, now) do
      {:ok, %{directory: directory, destination_id: marker["destinationId"]}}
    end
  end

  defp read_or_create_marker(artifacts, directory, now) do
    case read_marker(artifacts, directory) do
      {:ok, marker} ->
        {:ok, marker}

      {:error, :absent} ->
        marker = Location.new_marker(random_id(16), now)
        :ok = ArtifactStore.write_marker(artifacts, directory, marker)
        {:ok, marker}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_marker(artifacts, directory) do
    with {:ok, marker} <- ArtifactStore.read_marker(artifacts, directory),
         true <- Location.valid_marker?(marker) do
      {:ok, marker}
    else
      {:error, :absent} -> {:error, :absent}
      _invalid -> {:error, :invalid_marker}
    end
  end

  # What `directory` holds of each run's artifact: its digest and size, for the runs whose
  # artifact exists, so a missing file is never digested.
  defp observe(artifacts, directory, runs) do
    for run <- runs,
        path = Path.join(directory, run.artifact_basename),
        ArtifactStore.regular?(artifacts, path),
        into: %{} do
      {run.artifact_basename,
       %{
         sha256: ArtifactStore.digest(artifacts, path),
         bytes: ArtifactStore.size(artifacts, path)
       }}
    end
  end

  defp bare_name?(argument) when is_binary(argument),
    do: argument not in ["", ".", ".."] and Path.basename(argument) == argument

  defp bare_name?(_argument), do: false

  defp owned?(artifacts, receipt, directory, destination_id) do
    with true <- Receipt.valid?(receipt, destination_id),
         artifact_path = Path.join(directory, receipt["artifactBasename"]),
         true <- ArtifactStore.regular?(artifacts, artifact_path) do
      ArtifactStore.digest(artifacts, artifact_path) == receipt["artifactSha256"]
    end
  end

  defp timeout_ms, do: Application.get_env(:bnest_app, :backup_timeout_ms, @default_timeout_ms)

  defp outcome_tag({:ok, _artifact}), do: :ok
  defp outcome_tag({:error, {:retryable, category, _artifact}}), do: category
  defp outcome_tag({:error, category}), do: category

  defp random_id(bytes), do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  defp config_store, do: adapter(:config_store).new()
  defp artifact_store, do: adapter(:artifact_store).new()
  defp database_snapshot, do: adapter(:database_snapshot).new()
  defp capacity_probe, do: adapter(:capacity_probe).new()
  defp ignore_check, do: adapter(:ignore_check).new()
end
