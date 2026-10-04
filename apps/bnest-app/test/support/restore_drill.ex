defmodule BnestApp.Test.RestoreDrill do
  @moduledoc """
  Test-only fixtures, operations and evidence for the restore-drill scenarios of
  `scheduled_backups.feature`, shared by the unit and integration behaviour drivers.

  The layer is the one the adapters in `config :bnest_app, BnestApp.Backup` select
  (`in_memory?/0`). In the unit layer the destination's files live in the in-memory artifact
  store and an artifact is the term the in-memory snapshot double restores; in the integration
  layer the destination is a real temporary directory and an artifact a real SQLite file this
  module writes, with the tables the restore reads. Neither is copied from a live database, so a
  scenario's counts are exact and a drill that reaches the live database is told apart from one
  that does not.

    * a Given puts a destination, a synthetic artifact and the entries the drill must refuse
      into place (`prepare/3`);
    * the When runs the drill task by name (`perform/3`), as the command line reaches it, while
      `BnestApp.Test.CallTrace` records the calls that could open the live database or restore
      a copy, and, in the integration layer, with the operating system's temporary directory
      redirected to an empty directory of the scenario's own, where `restore/1` creates its
      root;
    * a Then reads that evidence back (`outcome?/3`): the task's `exit_status` and `lines`, the
      traced calls and the scratch directory's listing.

  The task result is kept under `:task`, and the destination before the run under
  `:evidence_before`, which are the keys the reconcile scenarios' shared steps read.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Backup
  alias BnestApp.Backup.Ports.DatabaseSnapshot, as: SnapshotPort
  alias BnestApp.FamilyChat
  alias BnestApp.Test.BackupIntegrity
  alias BnestApp.Test.CallTrace
  alias BnestApp.Test.InMemory.ArtifactStore, as: InMemoryArtifactStore
  alias BnestApp.Test.InMemory.BackupConfigStore, as: InMemoryBackupConfigStore
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore

  @task "bnest.backup.restore_drill"
  @artifact_basename "bnest-prod-20300518T190100Z-test-restore-drill.sqlite3"
  @outside_basename "bnest-prod-20300518T190200Z-test-outside.sqlite3"
  @directory_basename "bnest-prod-20300518T190300Z-test-directory.sqlite3"
  @link_target_basename "bnest-prod-20300518T190400Z-test-link-target.sqlite3"
  @link_basename "bnest-prod-20300518T190500Z-test-link.sqlite3"

  # What can open the live database or restore a copy: every call the Snapshot port serves, a
  # connection opened by path, the repository on the live file, its start-up and, in the unit
  # layer, the room store that stands for the live database.
  @watched [
    {{SnapshotPort, :_, :_}, []},
    {{Exqlite.Sqlite3, :open, :_}, []},
    {{BnestApp.SqliteRepo, :_, :_}, []},
    {{BnestApp.Storage, :ensure_started!, :_}, []},
    {{InMemoryRoomStore, :_, :_}, []}
  ]

  @digest ~r/[0-9a-f]{64}/
  @absolute_path ~r{(?:^|[\s"'(=:])/[\w.~-]}

  # The tables and columns `restore/1` reads, and the columns that hold what the evidence must
  # never carry (a message body, a push endpoint and its keys).
  @schema [
    "CREATE TABLE family_chat_rooms (id INTEGER PRIMARY KEY, slug TEXT NOT NULL, name TEXT NOT NULL, member_posting_enabled INTEGER NOT NULL, deleted_at TEXT)",
    "CREATE TABLE family_chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, room_id INTEGER NOT NULL, body TEXT NOT NULL)",
    "CREATE TABLE web_push_subscriptions (id INTEGER PRIMARY KEY AUTOINCREMENT, endpoint TEXT NOT NULL, p256dh TEXT NOT NULL, auth_secret TEXT NOT NULL)",
    "CREATE TABLE family_chat_push_deliveries (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, subscription_id INTEGER NOT NULL, state TEXT NOT NULL)"
  ]

  @destination_prepares [:drill_artifact]
  @prepares [:drill_outside_file, :drill_directory, :drill_symlink]
  @performs [:restore_drill]
  @outcomes [
    :drill_exit_zero_first_line,
    :drill_prints_line,
    :drill_last_line,
    :drill_only_line,
    :drill_output_private_free,
    :drill_restored_once_root_gone,
    :drill_nothing_restored,
    :drill_no_root_created,
    :live_database_not_opened
  ]

  @doc "The Given states that run on a destination the driver has just established."
  @spec destination_prepares() :: [atom()]
  def destination_prepares, do: @destination_prepares

  @doc "The Given states that need no layer-specific step first."
  @spec prepares() :: [atom()]
  def prepares, do: @prepares

  @doc "The When actions, the same production calls in both layers."
  @spec performs() :: [atom()]
  def performs, do: @performs

  @doc "The Then checks."
  @spec outcomes() :: [atom()]
  def outcomes, do: @outcomes

  # ---------------------------------------------------------------------------------------
  # Given
  # ---------------------------------------------------------------------------------------

  @doc "Puts the destination, an artifact and the entries the drill must refuse into place."
  @spec prepare(map(), atom(), list()) :: map()
  def prepare(context, :drill_artifact, []),
    do: prepare(context, :drill_artifact, [3, 2, "pending", "delivered"])

  def prepare(context, :drill_artifact, [messages, subscriptions, first_state, second_state]) do
    spec = fixture(messages, subscriptions, [first_state, second_state])
    path = Path.join(context.backup_directory, @artifact_basename)
    write_artifact(path, spec)

    Map.put(context, :drill, %{
      spec: spec,
      artifact_path: path,
      scratch: scratch_temp_directory(context.backup_directory)
    })
  end

  # A restorable file next to the destination, not in it.
  def prepare(context, :drill_outside_file, []) do
    path = Path.join(Path.dirname(context.backup_directory), @outside_basename)
    write_artifact(path, context.drill.spec)
    put_in(context, [:drill, :outside_path], path)
  end

  def prepare(context, :drill_directory, []) do
    path = Path.join(context.backup_directory, @directory_basename)
    make_directory(path)
    put_in(context, [:drill, :directory_path], path)
  end

  # A link inside the destination to a restorable file outside it, which a check that only asks
  # whether the target is a file would follow out of the destination.
  def prepare(context, :drill_symlink, []) do
    target = Path.join(Path.dirname(context.backup_directory), @link_target_basename)
    link = Path.join(context.backup_directory, @link_basename)
    write_artifact(target, context.drill.spec)
    link_to(target, link, context.drill.spec)
    put_in(context, [:drill, :link_path], link)
  end

  # ---------------------------------------------------------------------------------------
  # When
  # ---------------------------------------------------------------------------------------

  @doc """
  Runs the restore drill task by name against `kind` of target, recording the destination
  before it and the watched calls during it.
  """
  @spec perform(map(), atom(), list()) :: map()
  def perform(context, :restore_drill, [kind]) do
    before = %{destination: BackupIntegrity.snapshot(context.backup_directory)}
    argument = argument(context, kind)
    {result, events} = CallTrace.record(@watched, fn -> execute(["--artifact", argument]) end)
    Map.merge(context, %{task: result, evidence_before: before, drill_events: events})
  end

  # The task is reached by name, as the command line reaches it, and its `execute/1` is the
  # entry point that returns `%{exit_status:, lines:}` without printing or exiting. Resolving it
  # when the scenario runs makes a task nobody has built a failure of the scenario instead of
  # of the project's compilation.
  defp execute(arguments), do: Mix.Task.get!(@task).execute(arguments)

  defp argument(context, "artifact"), do: Path.basename(context.drill.artifact_path)
  defp argument(context, "outside_absolute"), do: context.drill.outside_path

  defp argument(context, "outside_relative"),
    do: Path.join("..", Path.basename(context.drill.outside_path))

  defp argument(context, "directory"), do: Path.basename(context.drill.directory_path)
  defp argument(context, "symlink"), do: Path.basename(context.drill.link_path)

  # ---------------------------------------------------------------------------------------
  # Then
  # ---------------------------------------------------------------------------------------

  @doc "Whether the evidence a Then reads confirms what it states."
  @spec outcome?(map(), atom(), list()) :: boolean()
  def outcome?(context, :drill_exit_zero_first_line, [line]),
    do: context.task.exit_status == 0 and List.first(lines(context)) == line

  def outcome?(context, :drill_prints_line, [line]), do: line in lines(context)

  def outcome?(context, :drill_last_line, [line]), do: List.last(lines(context)) == line

  def outcome?(context, :drill_only_line, [line]), do: lines(context) == [line]

  # Non-empty, so that a task that printed nothing cannot pass for one that disclosed nothing.
  def outcome?(context, :drill_output_private_free, []) do
    text = Enum.join(lines(context), "\n")
    lines(context) != [] and not leaks?(text, context)
  end

  # Exactly one copy was restored, and it was the artifact the task was given. In the
  # integration layer the only database the task opened is the copy inside a `bnest-restore-`
  # root under the scratch directory, which is gone together with everything else there.
  def outcome?(context, :drill_restored_once_root_gone, []) do
    %{artifact_path: artifact, scratch: scratch} = context.drill

    case {restore_calls(context), opened_paths(context)} do
      {[{_caller, [_snapshot, ^artifact]}], opened} -> restore_root_removed?(scratch, opened)
      _not_once -> false
    end
  end

  def outcome?(context, :drill_nothing_restored, []), do: restore_calls(context) == []

  # No restore call is the only way a root comes to exist, so none was asked for; and in the
  # integration layer nothing, a root removed again included, is left in the scratch directory.
  def outcome?(context, :drill_no_root_created, []),
    do: restore_calls(context) == [] and scratch_empty?(context.drill.scratch)

  # No copy of the live database was taken or proved, no repository was started on it, no
  # in-memory stand-in for it was read, and the only connections opened were to the copy in a
  # restore root. Asking where the live database is, to keep the destination clear of it, is
  # not opening it.
  def outcome?(context, :live_database_not_opened, []) do
    touches =
      for {:call, {module, function, _arity}, _caller, _args} <- context.drill_events,
          live_access?(module, function),
          do: {module, function}

    strays =
      for path <- opened_paths(context),
          not restore_root?(context.drill.scratch, path),
          do: path

    touches == [] and strays == []
  end

  defp live_access?(SnapshotPort, function),
    do: function in [:vacuum_into, :prove, :source_generation]

  defp live_access?(Exqlite.Sqlite3, _function), do: false
  defp live_access?(_module, _function), do: true

  # ---------------------------------------------------------------------------------------
  # Fixtures and evidence
  # ---------------------------------------------------------------------------------------

  defp fixture(messages, subscriptions, delivery_states) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

    %{
      token: token,
      room: %{
        id: 1,
        slug: FamilyChat.canonical_room_slug(),
        name: "Synthetic Family Room",
        member_posting_enabled: true
      },
      messages:
        for(
          id <- 1..messages//1,
          do: %{id: id, room_id: 1, body: "restore-secret-#{id}-#{token}"}
        ),
      subscriptions:
        for id <- 1..subscriptions//1 do
          %{
            id: id,
            endpoint: "synthetic-endpoint-#{id}-#{token}",
            p256dh: "synthetic-p256dh-#{id}-#{token}",
            auth: "synthetic-auth-#{id}-#{token}"
          }
        end,
      deliveries:
        delivery_states
        |> Enum.with_index(1)
        |> Enum.map(fn {state, index} ->
          %{message_id: 1, subscription_id: min(index, subscriptions), state: state}
        end)
    }
  end

  defp write_artifact(path, spec) do
    if in_memory?() do
      database = %{
        rooms: %{spec.room.id => {spec.room, false}},
        messages: spec.messages,
        subscriptions: spec.subscriptions,
        deliveries: spec.deliveries
      }

      InMemoryArtifactStore.put_file(InMemoryArtifactStore.new(), path, %{database: database})
    else
      write_sqlite!(path, spec)
    end
  end

  defp write_sqlite!(path, spec) do
    {:ok, connection} = Exqlite.Sqlite3.open(path)

    try do
      Enum.each(@schema ++ rows(spec), &(:ok = Exqlite.Sqlite3.execute(connection, &1)))
    after
      :ok = Exqlite.Sqlite3.close(connection)
    end
  end

  # Every value is synthetic and free of quotes, so the statements carry them as literals.
  defp rows(spec) do
    room = spec.room

    [
      "INSERT INTO family_chat_rooms (id, slug, name, member_posting_enabled) VALUES (#{room.id}, '#{room.slug}', '#{room.name}', 1)"
    ] ++
      Enum.map(
        spec.messages,
        &"INSERT INTO family_chat_messages (id, room_id, body) VALUES (#{&1.id}, #{&1.room_id}, '#{&1.body}')"
      ) ++
      Enum.map(
        spec.subscriptions,
        &"INSERT INTO web_push_subscriptions (id, endpoint, p256dh, auth_secret) VALUES (#{&1.id}, '#{&1.endpoint}', '#{&1.p256dh}', '#{&1.auth}')"
      ) ++
      Enum.map(
        spec.deliveries,
        &"INSERT INTO family_chat_push_deliveries (message_id, subscription_id, state) VALUES (#{&1.message_id}, #{&1.subscription_id}, '#{&1.state}')"
      )
  end

  defp make_directory(path) do
    if in_memory?(),
      do: :ok = InMemoryArtifactStore.prepare_directory(InMemoryArtifactStore.new(), path),
      else: File.mkdir_p!(path)
  end

  # In memory a link is a file at a path the store reports as a symbolic link.
  defp link_to(target, link, spec) do
    if in_memory?() do
      write_artifact(link, spec)
      InMemoryArtifactStore.put_symlink(InMemoryArtifactStore.new(), link)
    else
      :ok = File.ln_s(target, link)
    end
  end

  # The restore root is created under the operating system's temporary directory. This one
  # starts empty and is the only place the drill is allowed to leave anything, so a root that was
  # created and not removed is a listing that is not empty. Everything is removed with the
  # destination's own parent directory; the environment is restored when the test exits.
  defp scratch_temp_directory(backup_directory) do
    if in_memory?(),
      do: nil,
      else: redirect_temp_directory(Path.join(Path.dirname(backup_directory), "restore-temp"))
  end

  defp redirect_temp_directory(scratch) do
    File.mkdir_p!(scratch)
    previous = System.get_env("TMPDIR")
    System.put_env("TMPDIR", scratch)
    ExUnit.Callbacks.on_exit(fn -> restore_temp_environment(previous) end)
    scratch
  end

  defp restore_temp_environment(nil), do: System.delete_env("TMPDIR")
  defp restore_temp_environment(previous), do: System.put_env("TMPDIR", previous)

  defp restore_calls(context), do: CallTrace.calls(context.drill_events, SnapshotPort, :restore)

  defp opened_paths(context),
    do:
      for(
        {_caller, [path | _options]} <-
          CallTrace.calls(context.drill_events, Exqlite.Sqlite3, :open),
        do: path
      )

  defp restore_root_removed?(nil, opened), do: opened == []

  defp restore_root_removed?(scratch, [restored]) do
    restore_root?(scratch, restored) and not File.exists?(Path.dirname(restored)) and
      scratch_empty?(scratch)
  end

  defp restore_root_removed?(_scratch, _opened), do: false

  # The copy a restore opens lies in a fresh `bnest-restore-` directory of the scratch directory.
  defp restore_root?(scratch, path) when is_binary(scratch) and is_binary(path) do
    root = Path.dirname(path)

    Path.dirname(root) == scratch and String.starts_with?(Path.basename(root), "bnest-restore-")
  end

  defp restore_root?(_scratch, _path), do: false

  defp scratch_empty?(nil), do: true
  defp scratch_empty?(scratch), do: File.ls!(scratch) == []

  defp lines(context), do: context.task.lines

  defp leaks?(text, context) do
    Enum.any?(private_values(context), &String.contains?(text, &1)) or
      Regex.match?(@digest, text) or Regex.match?(@absolute_path, text) or
      String.contains?(text, "bnest-restore-")
  end

  # The destination and the artifact's path and name, every message body, push endpoint and key,
  # and the scratch directory a restore root lies in: what the output must never carry.
  defp private_values(context) do
    %{spec: spec, artifact_path: artifact_path, scratch: scratch} = context.drill

    secrets =
      Enum.map(spec.messages, & &1.body) ++
        Enum.flat_map(spec.subscriptions, &[&1.endpoint, &1.p256dh, &1.auth])

    Enum.filter(
      [spec.token, context.backup_directory, artifact_path, Path.basename(artifact_path), scratch] ++
        secrets,
      &(is_binary(&1) and &1 != "")
    )
  end

  defp in_memory?, do: Backup.adapter(:config_store) == InMemoryBackupConfigStore
end
