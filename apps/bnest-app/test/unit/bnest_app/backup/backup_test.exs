defmodule BnestApp.Backup.FacadeTest do
  # `async: false`: the facade reaches the in-memory adapters the test installs under their
  # module names, as the unit layer's configuration selects them.
  use ExUnit.Case, async: false

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Receipt
  alias BnestApp.FamilyChat
  alias BnestApp.Test.InMemory.ArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore
  alias BnestApp.Test.InMemory.CapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot
  alias BnestApp.Test.InMemory.IgnoreCheck
  alias BnestApp.Test.InMemory.RoomStore
  alias BnestApp.Test.InMemory.SubscriptionStore

  @now ~U[2026-09-18 00:00:00Z]
  @wib_offset_seconds 7 * 60 * 60
  @destination "/srv/test-user-backup/destination"

  setup do
    rooms = RoomStore.install()
    timeout = Application.fetch_env!(:bnest_app, :backup_timeout_ms)
    on_exit(fn -> Application.put_env(:bnest_app, :backup_timeout_ms, timeout) end)

    %{
      rooms: rooms,
      artifacts: ArtifactStore.install(),
      snapshot: DatabaseSnapshot.install(),
      capacity: CapacityProbe.install(),
      ignore: IgnoreCheck.install(),
      config: BackupConfigStore.install()
    }
  end

  describe "destination" do
    test "resolves the repository's ignored default when no override is saved", context do
      root = BackupConfigStore.repository_root(context.config)
      default = root <> "/data/backup"

      assert Backup.default_directory() == default
      assert {:ok, %{directory: ^default, destination_id: id}} = Backup.destination()
      assert IgnoreCheck.checks(context.ignore) == [{root, "data/backup"}]
      assert %{mode: 0o700} = ArtifactStore.directory(context.artifacts, default)

      assert %{
               content: %{
                 "schemaVersion" => 1,
                 "ownershipScope" => "bnest-production-backups-v1",
                 "destinationId" => ^id,
                 "createdAt" => _created_at
               },
               mode: 0o600
             } = ArtifactStore.file(context.artifacts, default <> "/.bnest-backup-root.json")

      assert String.length(id) == 22
      assert {:ok, %{destination_id: ^id}} = Backup.destination()
    end

    test "refuses the default when the repository does not ignore it", context do
      :ok = IgnoreCheck.put_ignored(context.ignore, false)

      assert Backup.destination() == {:error, :default_not_ignored}
      assert ArtifactStore.directories(context.artifacts) == []
    end

    test "saves an override as one whole configuration document", context do
      assert {:ok, %{directory: @destination, destination_id: id} = location} =
               Backup.save_destination(@destination)

      document = %{"schemaVersion" => 1, "destinationDirectory" => @destination}
      assert BackupConfigStore.document(context.config) == document
      assert BackupConfigStore.writes(context.config) == [document]
      assert Backup.destination() == {:ok, location}
      assert {:ok, %{destination_id: ^id}} = Backup.save_destination(@destination)
      assert IgnoreCheck.checks(context.ignore) == []
    end

    test "refuses unsafe destinations before creating or saving anything", context do
      root = BackupConfigStore.repository_root(context.config)

      source =
        context.snapshot
        |> DatabaseSnapshot.source_path()
        |> String.replace_suffix("/bnest.sqlite3", "")

      config =
        context.config
        |> BackupConfigStore.config_path()
        |> String.replace_suffix("/backup.json", "")

      :ok = ArtifactStore.put_symlink(context.artifacts, "/srv/test-user-backup/link")

      for {directory, reason} <- [
            {"relative/backup", :not_absolute},
            {42, :invalid_directory},
            {"/srv/test-user-backup/link/nested", :symlink},
            {source <> "/nested", :source_overlap},
            {"/srv/test-user-backup", :source_overlap},
            {config, :config_overlap},
            {root <> "/data", :repository_path}
          ] do
        assert Backup.save_destination(directory) == {:error, reason}, inspect(directory)
      end

      assert BackupConfigStore.writes(context.config) == []
      assert ArtifactStore.directories(context.artifacts) == []
    end

    test "reports an invalid or unreadable configuration and an invalid marker", context do
      :ok = BackupConfigStore.put_document(context.config, %{"schemaVersion" => 1})
      assert Backup.destination() == {:error, :invalid_config}

      :ok = BackupConfigStore.put_document(context.config, ["not", "a", "document"])
      assert Backup.destination() == {:error, :invalid_config}

      :ok = BackupConfigStore.put_read_error(context.config, :unavailable)
      assert Backup.destination() == {:error, :unavailable}

      marked = "/srv/test-user-backup/marked"
      :ok = ArtifactStore.put_file(context.artifacts, marked <> "/.bnest-backup-root.json", %{})
      assert Backup.save_destination(marked) == {:error, :invalid_marker}
    end

    test "validates a destination without creating or saving anything", context do
      assert Backup.validate_destination(@destination <> "/./nested/..") == {:ok, @destination}
      assert Backup.validate_destination("relative/backup") == {:error, :not_absolute}
      assert BackupConfigStore.writes(context.config) == []
      assert ArtifactStore.directories(context.artifacts) == []
    end

    test "reports a configuration it could not write or a destination it could not create",
         context do
      :ok = BackupConfigStore.put_write_error(context.config)
      assert Backup.save_destination(@destination) == {:error, :config_write_failed}

      unavailable = "/srv/test-user-backup/unavailable"
      :ok = ArtifactStore.put_unavailable(context.artifacts, unavailable)
      assert Backup.save_destination(unavailable) == {:error, :unavailable}
    end
  end

  describe "run/1" do
    setup context do
      {:ok, location} = Backup.save_destination(@destination)
      Map.put(context, :location, location)
    end

    test "refuses before snapshotting when the destination lacks the free space it needs",
         context do
      measurement = CapacityProbe.measurement(context.capacity)

      required =
        measurement.page_count * measurement.page_size + measurement.wal_bytes +
          256 * 1024 * 1024

      :ok = CapacityProbe.put_available_bytes(context.capacity, required - 1)

      assert Backup.run(deadline: @now, destination_directory: @destination) ==
               {:error, {:retryable, :insufficient_capacity, nil}}

      assert CapacityProbe.measured(context.capacity) == [@destination]
      assert DatabaseSnapshot.snapshots(context.snapshot) == []
      assert backups_in(context) == []

      :ok = CapacityProbe.put_available_bytes(context.capacity, required)
      assert {:ok, _artifact} = Backup.run(deadline: @now, destination_directory: @destination)
    end

    test "refuses when the destination's free space cannot be measured", context do
      :ok = CapacityProbe.put_unmeasurable(context.capacity)

      assert Backup.run(deadline: @now, destination_directory: @destination) ==
               {:error, {:retryable, :insufficient_capacity, nil}}

      assert DatabaseSnapshot.snapshots(context.snapshot) == []
    end

    test "promotes a proved, private, synced snapshot of the live database", context do
      assert {:ok, artifact} = Backup.run(deadline: @now, destination_directory: @destination)
      assert artifact.basename =~ ~r/\Abnest-prod-20260918T000000Z-[A-Za-z0-9_-]{20}\.sqlite3\z/
      assert artifact.path == @destination <> "/" <> artifact.basename
      assert [partial] = DatabaseSnapshot.snapshots(context.snapshot)
      assert partial == artifact.path <> ".partial"
      assert DatabaseSnapshot.proofs(context.snapshot) == [partial]

      assert %{mode: 0o600, synced?: true} = ArtifactStore.file(context.artifacts, artifact.path)
      assert artifact.sha256 == ArtifactStore.digest(context.artifacts, artifact.path)
      assert artifact.bytes == ArtifactStore.size(context.artifacts, artifact.path)
      assert backups_in(context) == [artifact.path]

      assert %{
               quick_check: "ok",
               schema_versions: schema_versions,
               logical_proof_sha256: proof,
               source_generation: generation
             } = artifact

      assert schema_versions == DatabaseSnapshot.schema_versions(context.snapshot)
      assert byte_size(proof) == 64
      assert generation == DatabaseSnapshot.source_generation(context.snapshot)
    end

    test "resolves the configured destination when none is given", context do
      assert {:ok, artifact} = Backup.run(deadline: @now)
      assert artifact.path == context.location.directory <> "/" <> artifact.basename

      assert {:ok, %{path: path}} = Backup.run()
      assert String.starts_with?(path, context.location.directory <> "/bnest-prod-")

      :ok = BackupConfigStore.put_read_error(context.config, :unavailable)
      assert Backup.run(deadline: @now) == {:error, :unavailable}
    end

    test "a snapshot past its timeout is cancelled, leaves no partial file and stays retryable",
         context do
      Application.put_env(:bnest_app, :backup_timeout_ms, 1)

      assert Backup.run(deadline: @now, destination_directory: @destination) ==
               {:error, {:retryable, :timeout, nil}}

      assert [_partial] = DatabaseSnapshot.snapshots(context.snapshot)
      assert DatabaseSnapshot.cancellations(context.snapshot) == 1
      assert backups_in(context) == []
    end

    test "a failed snapshot or a failed proof leaves no partial file and stays retryable",
         context do
      :ok = DatabaseSnapshot.fail_next(context.snapshot, :vacuum_into, :io_failed)

      assert Backup.run(deadline: @now, destination_directory: @destination) ==
               {:error, {:retryable, :io_failed, nil}}

      :ok = DatabaseSnapshot.fail_next(context.snapshot, :prove, :corrupt)

      assert Backup.run(deadline: @now, destination_directory: @destination) ==
               {:error, {:retryable, :integrity_failed, nil}}

      assert backups_in(context) == []
    end

    test "a refusal right before promotion discards the proved candidate", context do
      assert Backup.run(
               deadline: @now,
               destination_directory: @destination,
               before_promote: fn -> {:error, :stale_claim} end
             ) == {:error, {:retryable, :stale_claim, nil}}

      assert [_proved] = DatabaseSnapshot.proofs(context.snapshot)
      assert backups_in(context) == []
    end

    test "probes Family Chat during the backup and reports what they observed", context do
      assert {:ok, artifact} =
               Backup.run(deadline: @now, destination_directory: @destination, probe_watch: true)

      assert %{probe_failures: 0, probe_sent_ids_missing: [], probe_p95_ms: p95} = artifact
      assert is_integer(p95) and p95 >= 0

      assert {:ok, %{nodes: nodes}} =
               FamilyChat.list_messages(
                 "test-user-backup-reader",
                 FamilyChat.canonical_room_slug(),
                 limit: 50
               )

      assert length(nodes) == 20

      assert Enum.sort(DatabaseSnapshot.message_checks(context.snapshot)) ==
               Enum.map(nodes, &{1, &1.id})

      :ok = DatabaseSnapshot.fail_next(context.snapshot, :vacuum_into, :io_failed)

      assert Backup.run(deadline: @now, destination_directory: @destination, probe_watch: true) ==
               {:error, {:retryable, :io_failed, nil}}
    end

    test "counts every probe Family Chat refuses", context do
      archived = %{FamilyChat.canonical_room() | name: "Ruang Keluarga"}
      :ok = RoomStore.put_room(context.rooms, archived, deleted?: true)

      assert {:ok, %{probe_failures: 20, probe_sent_ids_missing: []}} =
               Backup.run(deadline: @now, destination_directory: @destination, probe_watch: true)

      assert DatabaseSnapshot.message_checks(context.snapshot) == []
    end

    test "reports its start and its outcome as telemetry", context do
      handler = "backup-facade-test-#{:erlang.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler,
          [[:bnest_app, :backup, :start], [:bnest_app, :backup, :stop]],
          &__MODULE__.forward_telemetry/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      {:ok, _artifact} = Backup.run(deadline: @now, destination_directory: @destination)
      :ok = CapacityProbe.put_available_bytes(context.capacity, 0)
      {:error, _refused} = Backup.run(deadline: @now, destination_directory: @destination)
      :ok = BackupConfigStore.put_read_error(context.config, :unavailable)
      {:error, :unavailable} = Backup.run(deadline: @now)

      assert_received {:telemetry, [:bnest_app, :backup, :start], %{system_time: _}, %{}}

      for outcome <- [:ok, :insufficient_capacity, :unavailable] do
        assert_received {:telemetry, [:bnest_app, :backup, :stop], %{duration_ms: _},
                         %{outcome: ^outcome}}
      end
    end
  end

  describe "receipts and retention" do
    setup context do
      {:ok, location} = Backup.save_destination(@destination)
      Map.put(context, :location, location)
    end

    test "writes a private receipt beside the artifact that the destination then owns", context do
      %{location: location} = context
      {:ok, artifact} = Backup.run(deadline: @now, destination_directory: @destination)
      claim = claim("run-1", location)

      assert {:ok, receipt} = Backup.record_receipt(claim, location, @now, artifact)
      assert receipt == Receipt.build(claim, location, @now, artifact)
      assert Receipt.valid?(receipt, location.destination_id)

      receipt_path = String.replace_suffix(artifact.path, ".sqlite3", ".receipt.json")

      assert %{content: ^receipt, mode: 0o600, synced?: true} =
               ArtifactStore.file(context.artifacts, receipt_path)

      assert Backup.owned_receipts(@destination) == [receipt]
      assert Backup.owned_receipts("/srv/test-user-backup/unmarked") == []
    end

    test "keeps the newest owned pair of each of the latest seven WIB dates and nothing else",
         context do
      %{location: location, artifacts: artifacts} = context
      unknown = @destination <> "/keep-me.txt"
      :ok = ArtifactStore.put_file(artifacts, unknown, "synthetic-unowned")

      backups =
        for days <- 0..8, minutes <- [0, 30] do
          at = DateTime.add(@now, -days * 86_400 + minutes * 60)
          {:ok, artifact} = Backup.run(deadline: at, destination_directory: @destination)
          run_id = "run-#{days}-#{minutes}"
          {:ok, receipt} = Backup.record_receipt(claim(run_id, location), location, at, artifact)
          {receipt, artifact}
        end

      # A pair whose artifact no longer matches its receipt is not owned, so retention leaves it.
      {tampered, tampered_artifact} = List.last(backups)
      :ok = ArtifactStore.put_file(artifacts, tampered_artifact.path, "changed bytes")

      assert {:ok, kept} = Backup.retain_owned(@destination)

      newest_per_date =
        backups
        |> Enum.map(&elem(&1, 0))
        |> Enum.reject(&(&1 == tampered))
        |> Enum.group_by(&wib_date/1)
        |> Enum.sort_by(fn {date, _receipts} -> date end, {:desc, Date})
        |> Enum.take(7)
        |> Enum.map(fn {_date, receipts} -> Enum.max_by(receipts, & &1["createdAt"]) end)

      assert kept == MapSet.new(newest_per_date, & &1["runId"])

      assert Backup.owned_receipts(@destination) ==
               Enum.sort_by(newest_per_date, & &1["createdAt"], :desc)

      for {receipt, artifact} <- backups, receipt != tampered do
        receipt_path = String.replace_suffix(artifact.path, ".sqlite3", ".receipt.json")
        kept? = MapSet.member?(kept, receipt["runId"])
        assert ArtifactStore.regular?(artifacts, artifact.path) == kept?
        assert ArtifactStore.regular?(artifacts, receipt_path) == kept?
      end

      assert ArtifactStore.regular?(artifacts, unknown)
      assert ArtifactStore.regular?(artifacts, tampered_artifact.path)
    end
  end

  describe "restore/1" do
    test "reports the active room, its ordered messages, subscriptions and delivery states",
         context do
      archived = %{
        FamilyChat.canonical_room()
        | id: 900,
          slug: "ruang-arsip",
          name: "Ruang Arsip"
      }

      :ok = RoomStore.put_room(context.rooms, archived, deleted?: true)
      _subscription = SubscriptionStore.subscribe!(context.rooms, "test-user-backup-reader")
      secret = "restore-secret-#{:erlang.unique_integer([:positive])}"

      ids =
        for body <- [secret, "second"] do
          {:ok, message} =
            FamilyChat.send_message(
              "test-user-backup-sender",
              FamilyChat.canonical_room_slug(),
              Ecto.UUID.generate(),
              body
            )

          message.id
        end

      {:ok, _location} = Backup.save_destination(@destination)
      {:ok, artifact} = Backup.run(deadline: @now, destination_directory: @destination)

      assert {:ok, %{evidence: evidence}} = Backup.restore(artifact)

      assert Jason.decode!(evidence) == %{
               "room" => %{
                 "id" => 1,
                 "slug" => FamilyChat.canonical_room_slug(),
                 "name" => "Ruang Keluarga",
                 "memberPostingEnabled" => true
               },
               "orderedMessageIds" => ids,
               "subscriptionCount" => 1,
               "deliveryStates" => ["pending"]
             }

      refute evidence =~ secret
    end

    test "refuses an artifact it cannot restore" do
      assert Backup.restore(%{path: "/srv/test-user-backup/missing.sqlite3"}) ==
               {:error, :restore_failed}

      assert Backup.restore(%{}) == {:error, :invalid_artifact}
    end
  end

  @doc false
  def forward_telemetry(event, measurements, metadata, test_pid),
    do: send(test_pid, {:telemetry, event, measurements, metadata})

  defp backups_in(context) do
    context.artifacts
    |> ArtifactStore.paths(@destination)
    |> Enum.filter(&String.contains?(&1, "/bnest-prod-"))
  end

  defp claim(run_id, location) do
    %{
      schedule_key: "prod-sqlite-backup-daily",
      claim_kind: "setup",
      claim_key: "setup:" <> location.destination_id,
      scheduled_for: nil,
      run_id: run_id,
      schedule_revision: 1
    }
  end

  defp wib_date(receipt) do
    {:ok, created_at, 0} = DateTime.from_iso8601(receipt["createdAt"])
    created_at |> DateTime.add(@wib_offset_seconds) |> DateTime.to_date()
  end
end
