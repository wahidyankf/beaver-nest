defmodule BnestApp.Behaviour.IntegrationFamilyChatDriver do
  @moduledoc """
  Generic prepare/perform/outcome dispatch for `family_chat_graphql.feature` and
  `family_chat_operations.feature` at the integration layer. Delegated to from
  `BnestApp.Behaviour.IntegrationHomePageDriver` for every atom this module recognizes.

  GraphQL/socket/CSRF/GraphiQL scenarios cross the real Phoenix HTTP and channel boundary
  through `Phoenix.ConnTest`/`Phoenix.ChannelTest` against the isolated test endpoint. Internal
  scheduler/backup/retention/migration scenarios call the public service/context modules directly,
  matching how `scheduled_backup_steps.exs` is already bound at this layer. During RED, every path
  through a not-yet-implemented route, module, or function fails for the correct reason (the
  feature is genuinely absent), not a harness/identity/port/cleanup defect.
  """

  # `connect/2,3` is excluded from Phoenix.ConnTest because it collides with
  # Phoenix.ChannelTest's `connect/3` (socket handshake); this driver never
  # exercises the HTTP CONNECT verb, so ChannelTest's definition wins.
  import Phoenix.ConnTest, except: [connect: 2, connect: 3]
  import Phoenix.ChannelTest

  alias Absinthe.Subscription.Proxy, as: SubscriptionProxy
  alias BnestApp.Backup
  alias BnestApp.FamilyChat.Adapters.SqliteRoomStore
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.Identity
  alias BnestApp.Identity.Adapters.RecordIdentityStore
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.PushNotifications.Domain.Policy, as: PushPolicy
  alias BnestApp.Release.Migrations
  alias BnestApp.Scheduler
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Records
  alias BnestApp.Test.IndependentSlot
  alias BnestApp.Test.InMemory.CapacityProbe, as: InMemoryCapacityProbe
  alias BnestApp.Test.InMemory.PushSender, as: InMemoryPushSender
  alias BnestApp.Test.PublicMutationProbe
  alias BnestApp.Test.SchedulerDispatch
  alias BnestApp.Test.Seeds.Schedules
  alias BnestApp.TestBackupDestination
  alias BnestApp.TestRuntimeRoot

  # See the identical attribute on BnestApp.Behaviour.UnitFamilyChatDriver for
  # why this is required during RED (`mix compile --warnings-as-errors`
  # otherwise fails to compile at all, not just the tests that use these
  # not-yet-implemented modules/functions).
  @compile {:no_warn_undefined,
            [
              BnestApp.Release.Migrations,
              BnestApp.Backup,
              BnestAppWeb.Schema
            ]}

  @endpoint BnestAppWeb.Endpoint
  @behaviour_now ~U[2026-09-18 00:00:00Z]
  @graphql_path "/api/graphql"

  # Item 5 (Phase 5 delivery.md): "isolated concurrent-write load proof for
  # the full backup interval." `@load_proof_padding_rows` synthetic
  # `web_push_subscriptions` rows (never `family_chat_messages`, which is
  # trigger-enforced append-only/undeletable -- see the migration -- so
  # padding there would permanently grow the shared test database on every
  # suite run) give `VACUUM INTO` enough real bytes to take measurable,
  # non-instantaneous time, both so the load scenario's routed probes
  # genuinely overlap it and so the cancellation scenario's forced
  # `backup_timeout_ms` reliably exceeds the snapshot's real duration
  # instead of racing a near-empty database. Cleaned up in `on_exit`.
  @load_proof_padding_rows 1800
  @load_proof_probe_count 20
  @load_proof_room_slug "ruang-keluarga"

  # The last schema version the release before Family Chat shipped, and the tables Family
  # Chat's migrations added to that database.
  @prior_release_schema_version 20_260_830_000_000
  @family_chat_tables ~w(family_chat_push_deliveries web_push_subscriptions family_chat_messages family_chat_rooms)

  # The deployment tool's reverse-proxy configuration generator, run with Node as the tool
  # runs it.
  @caddy_config_tool Path.expand("../../../tools/caddy-config.mjs", __DIR__)

  # --- prepare ---

  # Commits five messages through the facade into the run's shared room, which may already
  # hold other scenarios' messages; the known IDs are the middle three, so a page before the
  # first and a page after the last both have a message of this history to return.
  def prepare_behaviour(context, :room_has_known_history, _args) do
    ids =
      for n <- 1..5 do
        {:ok, message} =
          BnestApp.FamilyChat.send_message(
            "test-user-family-chat-history-" <> unique_uuid(),
            BnestApp.FamilyChat.canonical_room_slug(),
            unique_uuid(),
            "history #{n}"
          )

        message.id
      end

    Map.merge(context, %{
      family_chat_history_ids: ids,
      family_chat_known_ids: Enum.slice(ids, 1..3)
    })
  end

  # Genuinely commits the first message through the real boundary (adapter
  # fix; see the unit driver's identical clause and learnings.md's Phase 3
  # entry): this used to record an ID and a body without ever sending them, so
  # the "retry" that followed was the first commit for that ID.
  def prepare_behaviour(context, :sent_message_with_known_id, [body]) do
    context = send_family_chat_message(context, unique_uuid(), body)
    original = sent_message(context)

    Map.merge(context, %{
      family_chat_known_body: original["body"],
      family_chat_original_message_id: original["id"]
    })
  end

  # Live-resolution proof (sender display name reflects the current account,
  # not the value stamped into `family_chat_messages` at commit time -- that
  # column is DB-trigger-enforced immutable, so the only correct fix is
  # resolving the display name live at read time; see
  # `BnestApp.FamilyChat.live_sender_display_name/2`). A real send through the
  # authenticated HTTP boundary captures the message's server-assigned ID so
  # the later requery can find this exact message.
  def prepare_behaviour(context, :sent_and_committed_message, [body]) do
    context = send_family_chat_message(context, unique_uuid(), body)

    %{"data" => %{"sendFamilyChatMessage" => %{"id" => message_id}}} = context.family_chat_result

    Map.put(context, :family_chat_renamed_sender_message_id, message_id)
  end

  # System messages have no underlying account (`sender_id` is a stable
  # producer key, not a user id), so live resolution must never touch them --
  # proves `FamilyChat.live_sender_display_name/2`'s `sender_kind: "system"`
  # short-circuit clause, not just the "user" branch above.
  def prepare_behaviour(context, :system_message_posted_to_room, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    {:ok, message} =
      BnestApp.FamilyChat.post_system_message(slug, "system:producer-" <> unique_uuid(), "Notice")

    Map.put(context, :family_chat_system_message_id, to_string(message.id))
  end

  def prepare_behaviour(context, :user_without_family_chat_capability, _args) do
    # `Identity.Domain.Authorization.allow?/3` grants `use_family_chat` to any
    # non-empty valid role, and the shared account schema
    # (`data_repository/schema.ex`'s `roles?/1`) forbids ever persisting an
    # account with an empty roles list — so a genuinely capability-denied
    # *persisted* identity cannot exist (the PRD defines every approved
    # child/parent/admin as a full "family member"). `graphql/3` reads this
    # flag and, when set, runs the query through the real
    # schema/resolver/authorization code with a synthetic forbidden context
    # instead of a real HTTP/session round trip — see its own comment.
    Map.put(context, :family_chat_capability, false)
  end

  # Joins the real `UserSocket` through `Phoenix.ChannelTest` with the session a page
  # load wrote for the scenario's member, and pushes the `familyChatMessageCommitted`
  # document on Absinthe's control channel, exactly as the browser client does. Every
  # commit is then pushed to this process as the socket's transport.
  def prepare_behaviour(context, :holds_subscription, [_name, slug]),
    do: subscribe_over_socket(context, slug)

  def prepare_behaviour(context, :message_committed_before_subscription, _args) do
    # See the unit driver's identical clause: a fixed `1` only worked by luck
    # for the very first message in the shared database; this captures the
    # real server-assigned ID instead. Also captures a genuine baseline ID
    # *before* sending, since the later afterId query must cursor from a
    # point strictly before this message (afterId is exclusive-after) for
    # this very message to appear in its own catch-up results.
    baseline_id = latest_room_message_id()

    {:ok, message} =
      BnestApp.FamilyChat.send_message(
        context.user_id,
        "ruang-keluarga",
        unique_uuid(),
        "Pre-subscription message"
      )

    context
    |> Map.put(:family_chat_last_id, baseline_id)
    |> Map.put(:family_chat_pre_subscription_id, message.id)
  end

  # Mirrors `:message_committed_before_subscription`: the baseline is read before the
  # target and its reply are sent, so the catch-up query cursors from before both.
  def prepare_behaviour(context, :reply_committed_before_subscription, _args) do
    baseline_id = latest_room_message_id()
    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    target_id = sent_message(context)["id"]

    context =
      send_family_chat_message(context, unique_uuid(), "Oke, aku siapin", reply_to: target_id)

    Map.merge(context, %{
      family_chat_last_id: baseline_id,
      family_chat_reply_target_id: target_id,
      family_chat_pre_subscription_reply_id: sent_message(context)["id"]
    })
  end

  # A real subscription of the session, stored through the GraphQL mutation, so disabling
  # it acts on something.
  def prepare_behaviour(context, :has_enabled_subscription, _args) do
    upserted = perform_behaviour(context, :upsert_valid_subscription, [])

    %{"data" => %{"upsertWebPushSubscription" => %{"enabled" => true}}} =
      upserted.family_chat_result

    Map.put(context, :family_chat_push_endpoint, upserted.family_chat_push_endpoint)
  end

  # The `:dev_routes` value a production build compiles with, read out of the real
  # `config/prod.exs` (see `configured_prod_dev_routes_flag/0`).
  def prepare_behaviour(context, :endpoint_configured_production, _args),
    do: Map.put(context, :family_chat_production_dev_routes, configured_prod_dev_routes_flag())

  # A database of its own, migrated to the schema the release before Family Chat left, so
  # it holds no Family Chat table yet: the migration under test is the first to add one.
  def prepare_behaviour(context, :fresh_migrated_database, _args) do
    database_path = isolated_family_chat_database!("family-chat-fresh")
    :ok = Storage.ensure_started!(database_path)

    Ecto.Migrator.run(SqliteRepo, migrations_path(), :up,
      to: @prior_release_schema_version,
      log: false
    )

    %{rows: []} =
      SqliteRepo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'family_chat_rooms'"
      )

    Map.put(context, :family_chat_migration_state, :fresh)
  end

  # On a database of its own: the schema exactly as the release before Family
  # Chat left it, holding a schedule of that release; its reads are taken once
  # there, then the real Family Chat migration runs on the same database.
  def prepare_behaviour(context, :migration_applied, _args) do
    database_path = isolated_family_chat_database!("family-chat-prior-release")
    :ok = Storage.ensure_started!(database_path)

    Ecto.Migrator.run(SqliteRepo, migrations_path(), :up,
      to: @prior_release_schema_version,
      log: false
    )

    schedule_key = "test-prior-release-" <> unique_uuid()
    :ok = Schedules.put_test_schedule(schedule_key, "family", "fixture", @behaviour_now)
    before_migration = prior_release_reads(schedule_key)

    {:ok, _room} = BnestApp.FamilyChat.migrate!()

    Map.merge(context, %{
      family_chat_migration_state: :applied,
      family_chat_prior_release: %{
        database_path: database_path,
        schedule_key: schedule_key,
        before_migration: before_migration
      }
    })
  end

  def prepare_behaviour(context, :trusted_producer, _args),
    do:
      Map.put(context, :family_chat_producer_key, "system:integration-producer-" <> unique_uuid())

  def prepare_behaviour(context, :three_members_with_subscriptions, [slug]) do
    # Real active subscriptions, stored through the PushNotifications facade.
    # `context.user_id` is always real here (`before_scenario` logs in every
    # scenario), and is also given a subscription of its own so "sender
    # excluded from delivery" is a genuine, non-vacuous assertion.
    # On a database of its own, so the active subscriptions are exactly these four.
    context = push_database!(context)

    other_subscribers =
      for suffix <- ~w(a b c), do: "test-user-family-chat-#{suffix}-" <> unique_uuid()

    other_subscription_ids =
      Enum.map(other_subscribers, &subscribe_through_facade!(&1, "accepted").id)

    sender_subscription_id = subscribe_through_facade!(context.user_id, "accepted").id

    # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see
    # its own comment): `ExUnit.Callbacks.on_exit/1` fires exactly once at
    # the true end of the underlying ExUnit test (after every ExBdd-internal
    # retry attempt, win or lose) and accumulates one callback per call, so
    # each attempt's own rows get retired regardless of which attempt (if
    # any) ultimately passes -- unlike relying on this scenario's own last
    # `Then` step, which never fires when an earlier step's attempt fails
    # first.
    ExUnit.Callbacks.on_exit(fn ->
      disable_subscriptions_for_users!([context.user_id | other_subscribers])
    end)

    Map.merge(context, %{
      family_chat_room_slug: slug,
      family_chat_other_subscribers: other_subscribers,
      family_chat_other_subscription_ids: other_subscription_ids,
      family_chat_sender_subscription_id: sender_subscription_id
    })
  end

  # --- replying (family_chat_graphql.feature / family_chat_operations.feature) ---

  def prepare_behaviour(context, :other_member_message_committed, [slug]) do
    # A genuinely different member, committed through the domain rather than
    # this session's mutation: the scenario is about replying to someone
    # else's message, and the logged-in conn can only ever send as itself.
    other_member = "test-user-family-chat-other-" <> unique_uuid()

    {:ok, target} =
      BnestApp.FamilyChat.send_message(
        other_member,
        slug,
        unique_uuid(),
        "Nanti aku jemput jam 5",
        "Ayah"
      )

    context
    |> Map.put(:family_chat_room_slug, slug)
    |> capture_reply_target(target)
  end

  def prepare_behaviour(context, :committed_long_message, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    {:ok, target} =
      BnestApp.FamilyChat.send_message(
        context.user_id,
        slug,
        unique_uuid(),
        String.duplicate("a", 400),
        context.identity_username
      )

    capture_reply_target(context, target)
  end

  def prepare_behaviour(context, :committed_message, [body]) do
    context = send_family_chat_message(context, unique_uuid(), body)
    capture_reply_target(context, sent_message(context))
  end

  def prepare_behaviour(context, :committed_reply_to_previous, [body]) do
    context =
      send_family_chat_message(context, unique_uuid(), body,
        reply_to: context.family_chat_reply_target_id
      )

    Map.put(context, :family_chat_previous_reply_id, sent_message(context)["id"])
  end

  # Commits two candidate targets so the retry can name a genuinely different
  # one -- a retry naming the same target would prove nothing about which
  # commit wins.
  def prepare_behaviour(context, :sent_reply_with_known_id, _args) do
    context = send_family_chat_message(context, unique_uuid(), "first target")
    first_id = sent_message(context)["id"]
    context = send_family_chat_message(context, unique_uuid(), "second target")
    second_id = sent_message(context)["id"]

    context =
      context
      |> Map.merge(%{
        family_chat_first_target_id: first_id,
        family_chat_second_target_id: second_id,
        family_chat_known_body: "Oke, aku siapin"
      })
      |> send_family_chat_message(unique_uuid(), "Oke, aku siapin", reply_to: first_id)

    Map.put(context, :family_chat_original_message_id, sent_message(context)["id"])
  end

  def prepare_behaviour(context, :replied_under_earlier_display_name, _args) do
    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    quoted_id = sent_message(context)["id"]

    context =
      send_family_chat_message(context, unique_uuid(), "Oke, aku siapin", reply_to: quoted_id)

    Map.merge(context, %{
      family_chat_quoted_message_id: quoted_id,
      family_chat_reply_message_id: sent_message(context)["id"]
    })
  end

  # Same shape as `:migration_applied`: genuinely runs the migration rather
  # than storing a sentinel, because the scenario then re-reads and re-writes
  # the real table through the pre-reply call shape.
  def prepare_behaviour(context, :reply_migration_applied, _args) do
    {:ok, _room} = BnestApp.FamilyChat.migrate!()
    Map.put(context, :family_chat_migration_state, :applied)
  end

  # One other subscriber (not three): this scenario counts delivery rows for a
  # reply, so a single expected row makes "exactly one" an exact assertion.
  # The sender also gets a subscription so their own exclusion stays genuine.
  # In a Family Chat database of the scenario's own, so dispatching sends only its rows.
  def prepare_behaviour(context, :one_other_active_subscription, [slug]) do
    context = push_database!(context)
    sender_id = durable_sender(context)
    other_subscriber = "test-user-family-chat-other-" <> unique_uuid()
    other_subscription_id = subscribe_through_facade!(other_subscriber, "accepted").id
    sender_subscription_id = subscribe_through_facade!(sender_id, "accepted").id

    ExUnit.Callbacks.on_exit(fn ->
      disable_subscriptions_for_users!([sender_id, other_subscriber])
    end)

    {:ok, target} =
      BnestApp.FamilyChat.send_message(
        other_subscriber,
        slug,
        unique_uuid(),
        "Nanti aku jemput jam 5",
        "Ayah"
      )

    Map.merge(context, %{
      family_chat_room_slug: slug,
      family_chat_user_id: sender_id,
      family_chat_other_subscription_id: other_subscription_id,
      family_chat_sender_subscription_id: sender_subscription_id,
      family_chat_reply_target_id: target.id,
      family_chat_reply_target_body: target.body
    })
  end

  # A real delivery, in a Family Chat database of the scenario's own, owed to a
  # subscription whose provider the push-client double answers with a retryable 503 (or
  # 410 Gone below): the recipient subscribes through the facade and another member's
  # commit fans the one pending delivery out to it.
  def prepare_behaviour(context, :delivery_will_fail_retryable, _args),
    do: owe_push_delivery!(context, 503)

  def prepare_behaviour(context, :delivery_targets_gone_subscription, _args),
    do: owe_push_delivery!(context, 410)

  # Real deliveries, one per named state, last stamped eight days before the retention
  # run, in a Family Chat database of the scenario's own.
  def prepare_behaviour(context, :final_rows_older_than_7_days, _args),
    do: seed_aged_deliveries!(context, :final, ~w(delivered terminal))

  def prepare_behaviour(context, :nonfinal_rows_same_age, _args),
    do: seed_aged_deliveries!(context, :nonfinal, ~w(pending claimed retryable))

  def prepare_behaviour(context, :soft_deleted_rows_older_than_7_days, _args),
    do: seed_aged_deliveries!(context, :soft_deleted, ~w(terminal))

  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see its
  # own comment): these two clauses previously only recorded the schedule
  # key, never actually seeding/forcing a due state -- "prod-sqlite-backup-
  # daily" is seeded only by real release/migration code (at real wall-clock
  # boot time, never necessarily due relative to `@behaviour_now`), and the
  # family-chat retention seed ships `enabled = 0` (tech-doc 002), so neither
  # schedule was ever genuinely claimable without this. The backup task the
  # Scheduler runs for it resolves its destination itself, so the Given also
  # configures an isolated one.
  def prepare_behaviour(context, :schedule_due, [key]) do
    # Started first: this may be the run's first scenario to reach the database.
    :ok = BnestApp.FamilyChat.ensure_ready!()
    _location = prepare_isolated_backup_config!()
    Schedules.reset_schedule!(key, "19:00", true, @behaviour_now)
    Schedules.force_due!(key, @behaviour_now)

    # After its run this shared row's next slot is still behind the wall clock, which the
    # Scheduler coordinator's catch-up uses: a later boot tick or reconcile would run a real
    # backup for it into whatever destination resolves then. A day past the wall clock it is
    # never due again in this run.
    ExUnit.Callbacks.on_exit(fn -> :ok = Schedules.force_not_due!(key, DateTime.utc_now()) end)
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  def prepare_behaviour(context, :schedule_due_and_enabled, [key]) do
    BnestApp.FamilyChat.ensure_ready!()
    Schedules.force_due!(key, @behaviour_now)
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix on all
  # three clauses below: none previously seeded the real "prod-sqlite-
  # backup-daily" row these convergence scenarios need -- it does not exist
  # at all in a fresh integration test database (only real release/migration
  # code seeds it, at "19:00", never "23:00"), so `Scheduler.converge_backup_time!/2`
  # would raise "unknown schedule" instead of genuinely exercising the CAS
  # convergence logic under test.
  def prepare_behaviour(context, :schedule_different_time, [key]) do
    Schedules.reset_schedule!(key, "23:00", true, @behaviour_now)

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_prior_daily_at_utc: "23:00"
    })
  end

  # Mirrors `prepare_behaviour/3, :schedule_different_time` above: forces the
  # real "family-chat-push-retention-daily" row (never present in a fresh
  # integration test database otherwise) into the exact pristine
  # precondition -- disabled, revision 1, at its real seed time (tech-doc
  # 002/`SqliteRoomStore`'s own insert: "17:15" UTC, i.e. 00:15 WIB) -- the
  # activation-CAS scenario's `Given` describes.
  def prepare_behaviour(context, :schedule_disabled_seed, [key]) do
    Schedules.reset_schedule!(key, "17:15", false, @behaviour_now)
    Map.put(context, :family_chat_activation_key, key)
  end

  def prepare_behaviour(context, :convergence_already_ran, _args) do
    Schedules.reset_schedule!(
      "prod-sqlite-backup-daily",
      "19:00",
      true,
      @behaviour_now
    )

    {:ok, _schedule} = Scheduler.converge_backup_time!("prod-sqlite-backup-daily", "18:00")
    Map.put(context, :family_chat_convergence_ran, true)
  end

  def prepare_behaviour(context, :operator_changed_schedule_time, [key]) do
    Schedules.force_operator_edit!(key, "20:00", @behaviour_now)

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_operator_daily_at_utc: "20:00"
    })
  end

  # The destination's free space cannot be made insufficient on a real disk, so Backup
  # measures it through the in-memory capacity probe, which reports none at all, until the
  # scenario exits. The context key tells the home page driver's shared "the backup handler
  # runs" step which scenario it serves.
  def prepare_behaviour(context, :insufficient_capacity, _args) do
    adapters = Application.fetch_env!(:bnest_app, BnestApp.Backup)

    Application.put_env(
      :bnest_app,
      BnestApp.Backup,
      Keyword.put(adapters, :capacity_probe, InMemoryCapacityProbe)
    )

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:bnest_app, BnestApp.Backup, adapters) end)
    :ok = InMemoryCapacityProbe.put_available_bytes(InMemoryCapacityProbe.install(), 0)
    Map.put(context, :family_chat_backup_capacity, :insufficient)
  end

  # The room already holds a message, so a snapshot taken before the first probe commits
  # still has history to restore: on a fresh run database it would otherwise hold none.
  # The database is started first, since this may be the run's first scenario to reach it.
  def prepare_behaviour(context, :continuous_probes_running, _args) do
    :ok = BnestApp.FamilyChat.ensure_ready!()
    seed_backup_load_padding!()

    {:ok, _history} =
      BnestApp.FamilyChat.send_message(
        "test-user-family-chat-history-" <> unique_uuid(),
        BnestApp.FamilyChat.canonical_room_slug(),
        unique_uuid(),
        "history before the backup"
      )

    Map.put(context, :family_chat_probes_running, true)
  end

  # Test-only seam, mirroring `push_notifications_test.exs`'s identical
  # `:web_push, :vapid` Application-env override technique: forces
  # `BnestApp.Backup`'s own `timeout_ms/0` read down to a value no real
  # `VACUUM INTO` over `@load_proof_padding_rows` of real bytes can finish
  # inside, so the cooperative `Exqlite.Sqlite3.cancel/1` path (tech-doc
  # 009's Timeout/Cancellation/Retry section) is exercised deterministically
  # rather than left provable only by code inspection. `on_exit` always
  # restores the previous value first, regardless of which value (or none)
  # was present, so a later scenario in this same suite run never inherits a
  # forced 1 ms timeout.
  def prepare_behaviour(context, :backup_timeout_forced, _args) do
    previous = Application.get_env(:bnest_app, :backup_timeout_ms)
    Application.put_env(:bnest_app, :backup_timeout_ms, 1)

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:bnest_app, :backup_timeout_ms, previous),
        else: Application.delete_env(:bnest_app, :backup_timeout_ms)
    end)

    context
  end

  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see
  # its own comment): a bare `:verified_fixture` sentinel is not something
  # `BnestApp.Backup.restore/1` can act on, and there is no separate "run a
  # backup" step before "the artifact is restored" in this scenario -- this
  # Given step itself seeds real fixture data and runs a real `Backup.run/1`
  # to produce a genuine artifact.
  def prepare_behaviour(context, :verified_backup_artifact, _args) do
    BnestApp.FamilyChat.ensure_ready!()
    destination = TestBackupDestination.create!("verified-backup-artifact-integration")
    known_body = "restore-fixture-secret-" <> unique_uuid()

    subscription =
      create_active_subscription!("test-user-family-chat-restore-" <> unique_uuid())

    ExUnit.Callbacks.on_exit(fn -> disable_subscription_row!(subscription.id) end)

    room =
      RoomStore.get_active_room(SqliteRoomStore.new(), BnestApp.FamilyChat.canonical_room_slug())

    {:ok, message} =
      BnestApp.FamilyChat.insert_message!(
        room.id,
        "user",
        "test-user-family-chat-restore-sender-" <> unique_uuid(),
        "Restore Fixture",
        unique_uuid(),
        known_body
      )

    {:ok, artifact} =
      Backup.run(deadline: @behaviour_now, destination_directory: destination.directory)

    Map.merge(context, %{
      family_chat_backup_artifact: artifact,
      family_chat_backup_destination: destination,
      family_chat_known_body: known_body,
      family_chat_fixture_message_id: message.id,
      family_chat_fixture_secrets: [subscription.endpoint, subscription.p256dh, subscription.auth]
    })
  end

  # Two slots started independently: this test's runtime, whose PubSub server is the
  # application's own, and a second runtime in an OS process of its own with no
  # distribution, running a PubSub server under the same name (`IndependentSlot`). A real
  # `familyChatMessageCommitted` subscription document is registered through the
  # application's endpoint. On each slot a listener subscribes to that document's topic,
  # the room's topic and every Absinthe proxy shard a publish is relayed through.
  def prepare_behaviour(context, :two_independent_slots, _args) do
    # A retried attempt starts its slots afresh and drops what the last one forwarded.
    drain_slot_messages(0)
    document_topic = subscribe_room_document!(context.user_id)

    room_topic =
      BnestApp.FamilyChat.subscription_topic(BnestApp.FamilyChat.canonical_room().id)

    topics = [document_topic, room_topic | absinthe_proxy_topics()]
    application_pubsub = Application.fetch_env!(:bnest_app, BnestAppWeb.Endpoint)[:pubsub_server]
    start_slot_listener!(:this_slot, application_pubsub, [document_topic, room_topic])
    other_slot = IndependentSlot.start!(topics)
    ExUnit.Callbacks.on_exit(fn -> IndependentSlot.stop(other_slot) end)

    Map.merge(context, %{family_chat_other_slot: other_slot, family_chat_slot_topics: topics})
  end

  # --- perform ---

  def perform_behaviour(context, :query_room_list, _args) do
    graphql(
      context,
      "query { familyChatRooms { id slug name roomKind memberPostingEnabled } }",
      %{}
    )
  end

  def perform_behaviour(context, :query_room_by_slug, [slug]) do
    graphql(
      context,
      "query($slug: String!) { familyChatRoom(slug: $slug) { id slug name roomKind memberPostingEnabled } }",
      %{"slug" => slug}
    )
  end

  def perform_behaviour(context, :visitor_query_room_list, _args) do
    graphql(anonymize(context), "query { familyChatRooms { id slug } }", %{})
  end

  def perform_behaviour(context, :query_messages_no_cursor, _args),
    do: query_messages(context, %{})

  # `IdentityStore.replace_account/2` writes directly to the real account store
  # used by `establish_identity/2` (`Records`) -- the same account the
  # earlier send authenticated as, now renamed to prove the later requery
  # reflects the account as it stands *now*, not as it stood at commit time.
  def perform_behaviour(context, :rename_sender_account, [new_name]) do
    store = RecordIdentityStore.new(Records)
    {:ok, account} = IdentityStore.read_account(store, context.user_id)
    updated = Map.put(account, "displayUsername", new_name)
    {:ok, ^updated} = IdentityStore.replace_account(store, updated)
    context
  end

  def perform_behaviour(context, :requery_after_rename, _args),
    do: query_messages(context, %{})

  def perform_behaviour(context, :query_messages_before_known_id, _args) do
    query_messages(context, %{"beforeId" => List.first(context[:family_chat_known_ids] || [1])})
  end

  def perform_behaviour(context, :query_messages_after_known_id, _args) do
    query_messages(context, %{"afterId" => List.last(context[:family_chat_known_ids] || [1])})
  end

  def perform_behaviour(context, :query_after_last_known_id, _args) do
    # Cursors from the pre-send baseline, not the pre-subscription message's
    # own ID — see that clause's comment for why.
    query_messages(context, %{"afterId" => context[:family_chat_last_id] || 0})
  end

  def perform_behaviour(context, :query_messages_both_cursors, _args),
    do: query_messages(context, %{"beforeId" => 5, "afterId" => 1})

  def perform_behaviour(context, :query_messages_with_limit, [limit]),
    do: query_messages(context, %{"limit" => limit})

  def perform_behaviour(context, :send_message_fresh_id, [body]),
    do: send_family_chat_message(context, unique_uuid(), body)

  def perform_behaviour(context, :resend_same_client_id, _args) do
    send_family_chat_message(
      context,
      context.family_chat_client_message_id,
      "a different body than " <> (context[:family_chat_known_body] || "")
    )
  end

  def perform_behaviour(context, :other_member_sends, [body]),
    do: send_as_other_member(context, unique_uuid(), body)

  def perform_behaviour(context, :establish_subscription, [_name, slug]),
    do: subscribe_over_socket(context, slug)

  # The user's own message first, so the reply has something of theirs to answer; then
  # another member's reply to it from that member's own session. Both commits push to the
  # subscriber, and every push that arrived is kept for the outcomes.
  def perform_behaviour(context, :other_member_replies_to_user, _args) do
    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    target_id = sent_message(context)["id"]

    context =
      context
      |> Map.put(:family_chat_reply_target_id, target_id)
      |> send_as_other_member(unique_uuid(), "Oke, aku siapin", reply_to: target_id)

    Map.put(context, :family_chat_subscription_pushes, subscription_pushes(context, 1_000))
  end

  def perform_behaviour(context, :query_web_push_configuration, _args) do
    # Tech-doc 004: "`webPushConfiguration` returns only the public
    # application key and supported/unavailable state" -- `publicKey` is
    # that key's actual GraphQL field name (`BnestAppWeb.Schema.Types.WebPushTypes`);
    # neither an `applicationServerKey` nor an `unavailableReason` field was
    # ever added to the schema, so querying them errored this scenario
    # before "available" could ever be read.
    graphql(context, "query { webPushConfiguration { available publicKey } }", %{})
  end

  def perform_behaviour(context, :query_current_subscription, _args) do
    graphql(context, "query { currentWebPushSubscription { enabled expirationTime } }", %{})
  end

  def perform_behaviour(context, :upsert_valid_subscription, _args) do
    input = valid_subscription_input()

    result =
      context
      |> upsert_subscription(input)
      |> Map.put(:family_chat_push_endpoint, input["endpoint"])

    # See `:three_members_with_subscriptions`'s own `on_exit` comment for the
    # full mechanism: this scenario's Background logs in with a fixed
    # sentinel user id, so a genuine active row this call stores would
    # otherwise inflate any LATER scenario's fan-out count for the rest of
    # the shared test database's run. Registering here, right after the row
    # is created, fires exactly once at the true end of the underlying
    # ExUnit test regardless of which ExBdd retry attempt (if any) passes.
    ExUnit.Callbacks.on_exit(fn -> disable_subscriptions_for_users!([context.user_id]) end)
    result
  end

  def perform_behaviour(context, :disable_subscription, _args), do: disable_subscription(context)

  def perform_behaviour(context, :disable_subscription_again, _args),
    do: disable_subscription(context)

  def perform_behaviour(context, :upsert_subscription_with_endpoint, [endpoint]) do
    result =
      context
      |> upsert_subscription(Map.put(valid_subscription_input(), "endpoint", endpoint))
      |> Map.put(:family_chat_push_endpoint, endpoint)

    # Same fixed-sentinel-user pollution risk as `:upsert_valid_subscription`
    # -- see its own `on_exit` comment.
    ExUnit.Callbacks.on_exit(fn -> disable_subscriptions_for_users!([context.user_id]) end)
    result
  end

  def perform_behaviour(context, :send_mutation_missing_csrf, _args) do
    # `Phoenix.ConnTest.build_conn/0` sets `plug_skip_csrf_protection: true`
    # on every test conn (a deliberate ConnTest convenience so ordinary
    # requests need no real token pair — confirmed empirically: every other
    # GraphQL scenario relies on this same default). Left as-is, this
    # scenario would never actually reach `Plug.CSRFProtection`'s rejection
    # path; forcing it back off reproduces a real (non-test) request, where
    # the flag is never set at all.
    body =
      Jason.encode!(%{
        "query" =>
          "mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) { sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id } }",
        "variables" => %{
          "roomSlug" => "ruang-keluarga",
          "clientMessageId" => unique_uuid(),
          "body" => "no csrf"
        }
      })

    conn =
      context.conn
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.delete_req_header("x-csrf-token")
      |> post(@graphql_path, body)

    Map.merge(context, %{
      family_chat_result: decode(conn),
      family_chat_http_status: conn.status
    })
  end

  # Genuine negative-input proof: connects with a spoofed `userId`/`role` in
  # the socket CONNECT PARAMS alongside the real, authenticated session
  # already on `context.conn`, so a regression that started trusting
  # client-supplied params for identity would actually be caught (the prior
  # binding always sent `%{}`, so no such regression could ever fail it).
  #
  # The session is the one a page load through the endpoint wrote for the member, which
  # the endpoint's `connect_info: [session: ...]` decodes from the handshake's cookie.
  def perform_behaviour(context, :open_socket_authenticated, _args) do
    spoofed_user_id = "test-user-family-chat-spoofed-" <> unique_uuid()

    spoofed_params = %{
      "userId" => spoofed_user_id,
      "role" => "admin",
      "roles" => ["admin", "children", "parents"]
    }

    session = page_session(context.conn)

    Map.merge(context, %{
      family_chat_spoofed_user_id: spoofed_user_id,
      family_chat_spoofed_params: spoofed_params,
      family_chat_socket_session: session,
      family_chat_result:
        connect(BnestAppWeb.UserSocket, spoofed_params, connect_info: %{session: session})
    })
  end

  def perform_behaviour(context, :visitor_opens_socket, _args) do
    Map.put(
      context,
      :family_chat_result,
      connect_family_chat_socket(anonymize(context), %{})
    )
  end

  def perform_behaviour(context, :run_family_chat_migration, _args),
    do: Map.put(context, :family_chat_result, BnestApp.FamilyChat.migrate!())

  # Re-runs the prior release's reads on the migrated database, then again with
  # every Family Chat table renamed away, so a read that reached one fails.
  def perform_behaviour(context, :old_code_opens_database, _args) do
    %{database_path: database_path, schedule_key: schedule_key} =
      context.family_chat_prior_release

    after_migration = prior_release_reads(schedule_key)

    without_family_chat =
      with_family_chat_tables_hidden(database_path, fn -> prior_release_reads(schedule_key) end)

    Map.merge(context, %{
      family_chat_result: after_migration,
      family_chat_reads_without_family_chat_tables: without_family_chat
    })
  end

  # The first post's result is kept apart, so the retry's can be compared with it.
  def perform_behaviour(context, :producer_posts_system_message, [slug]) do
    result =
      BnestApp.FamilyChat.post_system_message(
        slug,
        context.family_chat_producer_key,
        "system notice"
      )

    context
    |> Map.put(:family_chat_result, result)
    |> Map.put_new(:family_chat_first_system_result, result)
  end

  def perform_behaviour(context, :producer_retries_same_key, _args),
    do: perform_behaviour(context, :producer_posts_system_message, ["ruang-keluarga"])

  # The public schema answers its introspection query over HTTP, as any client asks it, and
  # every mutation field it declares is then sent over HTTP by the logged-in member, on a
  # database of its own so what the store holds afterwards is what these requests wrote.
  def perform_behaviour(context, :inspect_public_schema, _args) do
    context = push_database!(context)

    %{"data" => data} =
      graphql(context, PublicMutationProbe.introspection(), %{}).family_chat_result

    fields = PublicMutationProbe.fields(data)

    Map.merge(context, %{
      family_chat_schema_fields: fields,
      family_chat_schema_runs: Enum.map(fields, &run_public_mutation(context, &1))
    })
  end

  def perform_behaviour(context, :member_sends_durable_message, _args) do
    # Unlike the other "member sends a message" steps, this one's own
    # Gherkin Exemption frames it as "an internal SQLite boundary" (one
    # transaction committing a message and its delivery rows) — GraphQL's
    # `family_chat_message` type has no `deliveries` field (delivery rows are
    # an internal mechanism, never user-facing), so that boundary is only
    # observable by calling the domain function directly, matching the unit
    # driver's identical clause and this driver's own stated convention for
    # internal-boundary scenarios.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    result =
      BnestApp.FamilyChat.send_message(context.user_id, slug, unique_uuid(), "Dinner is ready")

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :send_reply_to_known_target, args) do
    body = List.first(args) || "Oke, aku siapin"

    send_family_chat_message(context, unique_uuid(), body,
      reply_to: context.family_chat_reply_target_id
    )
  end

  def perform_behaviour(context, :reply_target_unknown_id, _args),
    do: send_family_chat_message(context, unique_uuid(), "answer", reply_to: 999_999_999)

  def perform_behaviour(context, :reply_target_other_room, _args),
    do:
      send_family_chat_message(context, unique_uuid(), "answer",
        reply_to: archived_room_message_id()
      )

  def perform_behaviour(context, :reply_target_not_positive_integer, _args),
    do: send_family_chat_message(context, unique_uuid(), "answer", reply_to: "not-a-number")

  def perform_behaviour(context, :send_reply_to_previous_reply, _args),
    do:
      send_family_chat_message(context, unique_uuid(), "Siap",
        reply_to: context.family_chat_previous_reply_id
      )

  def perform_behaviour(context, :resend_same_id_other_target, _args),
    do:
      send_family_chat_message(
        context,
        context.family_chat_client_message_id,
        context.family_chat_known_body,
        reply_to: context.family_chat_second_target_id
      )

  # "Code built before that migration" is exactly code compiled against the
  # pre-reply call shape: `send_message/5`, with no reply argument at all.
  # Calling it against the migrated database is the genuine compatibility
  # proof -- a stored sentinel would prove nothing about the real column.
  def perform_behaviour(context, :pre_reply_release_opens_database, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    sender = durable_sender(context)

    {:ok, committed} =
      BnestApp.FamilyChat.send_message(
        sender,
        slug,
        unique_uuid(),
        "Dinner is ready",
        display_name_for(context, sender)
      )

    room = RoomStore.get_active_room(SqliteRoomStore.new(), slug)

    Map.merge(context, %{
      family_chat_result: {:ok, committed},
      family_chat_pre_reply_readback:
        RoomStore.message_by_id(SqliteRoomStore.new(), room.id, committed.id)
    })
  end

  # Called through the domain, not GraphQL: delivery rows are an internal
  # mechanism with no GraphQL field at all (see `:member_sends_durable_message`
  # above for the same reasoning).
  def perform_behaviour(context, :send_durable_reply, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    sender = durable_sender(context)

    result =
      BnestApp.FamilyChat.send_message(
        sender,
        slug,
        unique_uuid(),
        "Oke, aku siapin",
        display_name_for(context, sender),
        context.family_chat_reply_target_id
      )

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :dispatcher_attempts_delivery, _args),
    do: Map.put(context, :family_chat_result, Dispatcher.attempt())

  def perform_behaviour(context, :retention_job_runs, _args),
    do: Map.put(context, :family_chat_result, PushNotifications.retain_deliveries(@behaviour_now))

  def perform_behaviour(context, :retention_job_runs_again, _args) do
    # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical clause
    # (see its own comment, and learnings.md's Phase 5 entry). Genuinely
    # calls `retain_deliveries/1` twice against real SQLite. The first
    # call's result stays in `family_chat_result`, read by this scenario's
    # primary, scenario-titling assertion (`:rows_purged`, "those rows are
    # purged from SQLite"), which needs a positive count. The SECOND call's
    # result -- necessarily zero/zero since the first call already purged
    # every eligible row -- is stored under its own distinct key so the
    # companion `:retention_run_idempotent` outcome check reads independent
    # evidence instead of re-reading the first call's map.
    context = perform_behaviour(context, :retention_job_runs, [])
    second_result = PushNotifications.retain_deliveries(@behaviour_now)
    Map.put(context, :family_chat_idempotent_result, second_result)
  end

  # Claims through the Scheduler facade and runs the claimed run through it, as
  # the coordinator's tick does, recording which registered task ran and what it
  # called (see `BnestApp.Test.SchedulerDispatch`).
  def perform_behaviour(context, :scheduler_claims_and_dispatches, _args) do
    key = context.family_chat_due_schedule_key

    Map.put(
      context,
      :family_chat_dispatch,
      SchedulerDispatch.claim_and_dispatch(key, @behaviour_now)
    )
  end

  def perform_behaviour(context, :call_convergence_operation, _args) do
    Map.put(
      context,
      :family_chat_result,
      Scheduler.converge_backup_time!(context.family_chat_convergence_key, "18:00")
    )
  end

  def perform_behaviour(context, :call_activation_operation, _args) do
    key = context.family_chat_activation_key
    :ok = Scheduler.activate_if_pristine!(key, @behaviour_now)
    # See `BnestApp.Test.Seeds.Schedules.force_not_due!/2`'s own comment: this
    # scenario never claims the row, so it must not leave it due for a
    # later, unrelated scenario's broad `claim_due/1` sweep to steal.
    :ok = Schedules.force_not_due!(key, @behaviour_now)
    Map.put(context, :family_chat_result, Scheduler.get_schedule(key))
  end

  def perform_behaviour(context, :bnest_starts_again, _args) do
    # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix:
    # `apply_and_verify!/0`'s own `@spec` is `:: :ok`, but every outcome
    # check reading `family_chat_result` here expects `{:ok, schedule}`.
    :ok = Migrations.apply_and_verify!()

    Map.put(
      context,
      :family_chat_result,
      {:ok, Scheduler.get_schedule("prod-sqlite-backup-daily")}
    )
  end

  # Always injects its own isolated destination, never the configured default, and keeps it
  # until the scenario exits so a Then can read what the destination holds afterwards.
  def perform_behaviour(context, :backup_runs_full_duration, _args) do
    destination = TestBackupDestination.create!("capacity-" <> unique_uuid())
    ExUnit.Callbacks.on_exit(fn -> TestBackupDestination.cleanup!(destination) end)

    Map.merge(context, %{
      family_chat_result:
        Backup.run(deadline: @behaviour_now, destination_directory: destination.directory),
      family_chat_backup_directory: destination.directory
    })
  end

  def perform_behaviour(context, :restore_artifact_isolated_root, _args) do
    Map.put(
      context,
      :family_chat_result,
      BnestApp.Backup.restore(context[:family_chat_backup_artifact])
    )
  end

  # Genuinely routed probes (real GraphQL HTTP via `graphql/3`, the same helper
  # every other family-chat send/read scenario in this file uses -- never a
  # direct `FamilyChat.send_message/list_messages` call) run in a task of their
  # own while the backup does. Also genuinely "through Scheduler->handler-
  # >service" (tech-doc 009's Concurrent-write Proof step 3): claims a real
  # setup claim through the `Scheduler` facade and dispatches through its generic
  # `execute/2`, which resolves Backup's `ScheduledBackupTask` from the configured
  # `Scheduler.TaskRegistry` exactly as the 60s production tick does --
  # never `BnestApp.Backup.run/1` called directly.
  def perform_behaviour(context, :routed_backup_runs_full_duration, _args) do
    location = prepare_isolated_backup_config!()
    key = "bdd-routed-backup-" <> unique_uuid()

    :ok =
      Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)

    probe_task =
      if context[:family_chat_probes_running] do
        conn = context.conn
        Task.async(fn -> run_routed_probes(conn) end)
      end

    :ok = Scheduler.execute(claim, @behaviour_now)

    probes =
      if probe_task,
        do: Task.await(probe_task, 30_000),
        else: %{sent_ids: [], samples: [], failures: 0}

    Map.merge(context, %{
      family_chat_load_probes: probes,
      family_chat_load_receipts: Backup.owned_receipts(location.directory),
      family_chat_load_directory: location.directory
    })
  end

  # First half of the cancellation proof (tech-doc 009's Concurrent-write
  # Proof step 6): a direct `BnestApp.Backup.run/1` call (same technique the
  # capacity scenario above already uses) so the exact returned category and
  # artifact absence are directly assertable through the existing
  # `:retryable_failure`/`:no_partial_or_final_artifact` outcome checks. The
  # companion routed probes prove ordinary traffic is not blocked while this
  # attempt is cancelled.
  def perform_behaviour(context, :timed_out_backup_direct, _args) do
    destination = TestBackupDestination.create!("timed-out-direct-" <> unique_uuid())

    probe_task =
      if context[:family_chat_probes_running] do
        conn = context.conn
        Task.async(fn -> run_routed_probes(conn) end)
      end

    result = Backup.run(deadline: @behaviour_now, destination_directory: destination.directory)

    probes =
      if probe_task,
        do: Task.await(probe_task, 30_000),
        else: %{sent_ids: [], samples: [], failures: 0}

    ExUnit.Callbacks.on_exit(fn -> TestBackupDestination.cleanup!(destination) end)

    Map.merge(context, %{
      family_chat_result: result,
      family_chat_load_probes: probes,
      family_chat_backup_directory: destination.directory
    })
  end

  # Second half: the SAME forced-timeout condition, driven through the real
  # `Scheduler` claim -> `Scheduler.execute/2` -> registered-
  # handler chain (never a hand-crafted `Store.fail_attempt` call), so
  # "Scheduler state remains retryable" is proven from the real retry
  # bookkeeping `Scheduler.Run`'s failure recording performs, not asserted by
  # construction. `Scheduler.Domain.Policy.retry_at(1, now)` schedules the retry
  # five minutes out; advancing the deterministic clock past that and
  # re-querying `claim_due/1` is the same technique `reconcile_overlap`
  # already uses above.
  def perform_behaviour(context, :timed_out_backup_via_scheduler, _args) do
    location = prepare_isolated_backup_config!()
    key = "bdd-timed-out-backup-" <> unique_uuid()

    :ok =
      Schedules.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)

    :ok = Scheduler.execute(claim, @behaviour_now)

    later = DateTime.add(@behaviour_now, 6 * 60)
    retried = Enum.find(Scheduler.claim_due(later), &(&1.run_id == claim.run_id))

    Map.put(context, :family_chat_retry_claim, retried)
  end

  # Commits through the facade on this slot, whose configured publisher is the
  # production Absinthe one, then collects what each slot's listener received:
  # until this slot's event arrives, then for a settle window, since the other
  # slot is expected to receive nothing at all.
  def perform_behaviour(context, :message_commits_on_one_slot, _args) do
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    result =
      BnestApp.FamilyChat.send_message(context.user_id, slug, unique_uuid(), "slot-local publish")

    first = receive_slot_message(2_000)
    received = Enum.reject([first | drain_slot_messages(300)], &is_nil/1)

    context
    |> Map.put(:family_chat_result, result)
    |> Map.put(:family_chat_slot_received, received)
  end

  # Every configuration the deployment tool writes: for each slot, with and without the
  # upstream health check.
  def perform_behaviour(context, :generate_reverse_proxy_config, _args),
    do: Map.put(context, :family_chat_generated_configs, generated_caddyfiles())

  # The configuration a promotion writes, for each slot promoted over the other one.
  def perform_behaviour(context, :generate_promotion_config, _args) do
    configs = generated_caddyfiles()
    ports = Map.new(configs, &{&1["slot"], &1["port"]})

    promotions =
      for %{"slot" => slot, "healthChecked" => true, "config" => config} <- configs,
          {prior, prior_port} <- ports,
          prior != slot,
          do: %{promoted_port: ports[slot], prior_port: prior_port, config: config}

    Map.put(context, :family_chat_promotions, promotions)
  end

  # The router's own mounting decision (`BnestAppWeb.DevRoutes.mounted?/1`, which its
  # compile-time branch calls) taken for the production configuration, beside the routes
  # this build's router compiled from its own configuration.
  def perform_behaviour(context, :inspect_router_routes, _args) do
    Map.merge(context, %{
      family_chat_production_mounts_dev_routes:
        BnestAppWeb.DevRoutes.mounted?(context.family_chat_production_dev_routes),
      family_chat_graphiql_routes:
        Enum.filter(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))
    })
  end

  # --- outcome (same evidence shape as the unit driver; independently checked from HTTP/GraphQL results) ---

  def behaviour_outcome?(context, :room_list_lists_exactly, [name]),
    do:
      match?(
        %{"data" => %{"familyChatRooms" => [%{"name" => ^name}]}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :room_returned, [name]),
    do: match?(%{"data" => %{"familyChatRoom" => %{"name" => ^name}}}, context.family_chat_result)

  # Each page must be exactly the slice of the room's whole history its cursor
  # names, read back through the SQLite room store (the shared room may hold
  # other scenarios' messages too), and must reach the history the Given made.
  def behaviour_outcome?(context, :messages_ascending_max_50, _args) do
    history = context.family_chat_history_ids
    ids = page_ids(context)

    ids == Enum.take(room_message_ids(context), -50) and List.last(ids) == List.last(history) and
      Enum.all?(history, &(&1 in ids))
  end

  def behaviour_outcome?(context, :older_messages_ascending, _args) do
    first_known = hd(context.family_chat_known_ids)
    older = context |> room_message_ids() |> Enum.filter(&(&1 < first_known))
    ids = page_ids(context)

    ids == Enum.take(older, -50) and List.last(ids) == hd(context.family_chat_history_ids)
  end

  def behaviour_outcome?(context, :newer_messages_ascending, _args) do
    last_known = List.last(context.family_chat_known_ids)
    newer = context |> room_message_ids() |> Enum.filter(&(&1 > last_known))
    ids = page_ids(context)

    ids == Enum.take(newer, 50) and hd(ids) == List.last(context.family_chat_history_ids)
  end

  def behaviour_outcome?(context, :has_older_correct, _args) do
    has_older = get_in(context.family_chat_result, ["data", "familyChatMessages", "hasOlder"])
    has_older == Enum.any?(room_message_ids(context), &(&1 < hd(page_ids(context))))
  end

  def behaviour_outcome?(context, :has_newer_correct, _args) do
    has_newer = get_in(context.family_chat_result, ["data", "familyChatMessages", "hasNewer"])
    has_newer == Enum.any?(room_message_ids(context), &(&1 > List.last(page_ids(context))))
  end

  def behaviour_outcome?(context, :safe_error, [code]), do: error_code?(context, code)

  def behaviour_outcome?(context, :transport_safe_error, [code]) do
    context[:family_chat_http_status] == 403 and error_code?(context, code)
  end

  def behaviour_outcome?(context, :message_committed_with_id_and_time, _args) do
    match?(
      %{"data" => %{"sendFamilyChatMessage" => %{"id" => id, "committedAt" => at}}}
      when is_binary(id) and is_binary(at),
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :room_has_one_message_for_client_id, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 1

  def behaviour_outcome?(context, :message_reports_real_display_name, _args) do
    match?(
      %{"data" => %{"sendFamilyChatMessage" => %{"senderDisplayName" => name}}}
      when name == context.identity_username and name != context.user_id,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :message_shows_current_sender_display_name, [expected_name]) do
    message_id = context.family_chat_renamed_sender_message_id

    case context.family_chat_result do
      %{"data" => %{"familyChatMessages" => %{"nodes" => nodes}}} ->
        Enum.find(nodes, &(&1["id"] == message_id))["senderDisplayName"] == expected_name

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :system_message_display_name_unaffected, _args) do
    system_message_id = context.family_chat_system_message_id

    case context.family_chat_result do
      %{"data" => %{"familyChatMessages" => %{"nodes" => nodes}}} ->
        Enum.find(nodes, &(&1["id"] == system_message_id))["senderDisplayName"] == "System"

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :room_still_one_message, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 1

  # Compares against the FIRST commit, by server ID and body both -- see the
  # unit driver's identical clause for why the previous body-differs check
  # passed for a fresh commit too.
  def behaviour_outcome?(context, :original_message_unchanged, _args) do
    original = sent_message(context)

    original["id"] == context.family_chat_original_message_id and
      original["body"] == context.family_chat_known_body
  end

  def behaviour_outcome?(context, :quote_names_target_id, _args),
    do: sent_quote(context)["id"] == to_string(context.family_chat_reply_target_id)

  def behaviour_outcome?(context, :quote_reports_sender_and_preview, _args) do
    quoted = sent_quote(context)

    quoted["senderDisplayName"] == context.family_chat_reply_target_display_name and
      quoted["bodyPreview"] == context.family_chat_reply_target_body
  end

  def behaviour_outcome?(context, :message_has_no_quote, _args),
    do: match?(%{"replyTo" => nil}, sent_message(context))

  # The graphemes the preview keeps before the ellipsis that marks the cut.
  def behaviour_outcome?(context, :quote_preview_within_budget, [budget]) do
    sent_quote(context)["bodyPreview"] |> String.trim_trailing("…") |> String.length() <=
      budget
  end

  def behaviour_outcome?(context, :quote_preview_elided, _args),
    do: String.ends_with?(sent_quote(context)["bodyPreview"], "…")

  # Reads the quoted message back through the GraphQL page a client gets, and compares it
  # with the 400-grapheme body the Given wrote, not with anything the commit echoed.
  def behaviour_outcome?(context, :quoted_body_unshortened, _args) do
    target_id = to_string(context.family_chat_reply_target_id)
    after_id = to_message_id(context.family_chat_reply_target_id) - 1
    page = query_messages(context, %{"afterId" => after_id, "limit" => 1}).family_chat_result

    case get_in(page, ["data", "familyChatMessages", "nodes"]) do
      [%{"id" => ^target_id, "body" => body}] -> body == String.duplicate("a", 400)
      _other -> false
    end
  end

  def behaviour_outcome?(context, :room_has_no_message_for_client_id, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 0

  def behaviour_outcome?(context, :quote_names_previous_reply, _args),
    do: sent_quote(context)["id"] == to_string(context.family_chat_previous_reply_id)

  # The quote object has no reply field in the schema at all, so a quote of a
  # quote is unrepresentable rather than merely absent this once. Asking for
  # one is a document error, which is what this checks.
  def behaviour_outcome?(context, :quote_is_flat, _args) do
    not Map.has_key?(sent_quote(context), "replyTo") and
      match?(
        %{"errors" => [_ | _]},
        graphql_result(
          context,
          """
          query($roomSlug: String!) {
            familyChatMessages(roomSlug: $roomSlug) {
              nodes { replyTo { replyTo { id } } }
            }
          }
          """,
          %{"roomSlug" => context[:family_chat_room_slug] || "ruang-keluarga"}
        )
      )
  end

  def behaviour_outcome?(context, :quote_names_first_target, _args),
    do: sent_quote(context)["id"] == to_string(context.family_chat_first_target_id)

  def behaviour_outcome?(context, :quote_reports_live_display_name, [expected_name]) do
    case quoted_of_reply(context) do
      nil -> false
      quoted -> quoted["senderDisplayName"] == expected_name
    end
  end

  def behaviour_outcome?(context, :quote_name_matches_original, _args) do
    quoted = quoted_of_reply(context)
    original = node_by_id(context, context.family_chat_quoted_message_id)

    quoted != nil and original != nil and
      quoted["senderDisplayName"] == original["senderDisplayName"]
  end

  def behaviour_outcome?(context, :pre_reply_columns_unchanged, _args) do
    {:ok, committed} = context.family_chat_result
    readback = context.family_chat_pre_reply_readback

    readback != nil and
      Enum.all?(
        [:id, :room_id, :sender_kind, :sender_id, :sender_display_name, :idempotency_key, :body],
        &(Map.fetch!(readback, &1) == Map.fetch!(committed, &1))
      )
  end

  def behaviour_outcome?(context, :pre_reply_commits_have_no_target, _args) do
    readback = context.family_chat_pre_reply_readback

    readback != nil and readback.reply_to_message_id == nil and
      match?({:ok, %{reply_to: nil}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :one_pending_delivery_row, _args) do
    {:ok, %{deliveries: deliveries}} = context.family_chat_result

    match?(
      [%{subscription_id: id, state: "pending"}]
      when id == context.family_chat_other_subscription_id,
      deliveries
    )
  end

  # The dispatcher sends the reply's owed deliveries through the recording push sender,
  # and no payload it received for the reply may carry the quoted text; nor may any
  # stored delivery column, read back in full so a future payload column cannot quietly
  # start carrying it. The commit must owe at least one delivery, or there is no payload
  # to check.
  def behaviour_outcome?(context, :delivery_payload_excludes_quote, _args) do
    {:ok, %{id: message_id}} = context.family_chat_result
    quoted_body = context.family_chat_reply_target_body

    %{rows: rows} =
      SqliteRepo.query!("SELECT * FROM family_chat_push_deliveries WHERE message_id = ?", [
        message_id
      ])

    :ok = PushNotifications.dispatch_all_due!()

    payloads =
      for {_endpoint, %{"messageId" => ^message_id} = payload} <- push_requests(), do: payload

    rows != [] and length(payloads) == length(rows) and
      not Enum.any?(payloads, &String.contains?(Jason.encode!(&1), quoted_body)) and
      Enum.all?(rows, fn row ->
        Enum.all?(row, fn value ->
          not (is_binary(value) and String.contains?(value, quoted_body))
        end)
      end)
  end

  # The refusal carries no room: no data for the operation, and nothing anywhere in the
  # response names the room, its slug, or any room field.
  def behaviour_outcome?(context, :no_hidden_room_state, _args) do
    rendered = Jason.encode!(context.family_chat_result)

    error_code?(context, "FORBIDDEN") and
      get_in(context.family_chat_result, ["data", "familyChatRoom"]) == nil and
      not String.contains?(rendered, [
        "ruang-keluarga",
        "Ruang Keluarga",
        ~s("id"),
        "roomKind",
        "memberPostingEnabled"
      ])
  end

  def behaviour_outcome?(context, :room_gains_no_message, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 0

  # Every push the socket received for the subscription is the one message the other
  # member committed.
  def behaviour_outcome?(context, :subscriber_received_one_event, _args) do
    committed_id = sent_message(context)["id"]

    is_binary(committed_id) and
      match?([%{"id" => ^committed_id}], subscription_pushes(context, 1_000))
  end

  # The other member retries the same client message ID from the same session: the
  # response is the original commit, and the socket receives nothing more.
  def behaviour_outcome?(context, :no_duplicate_publish, _args) do
    original_id = sent_message(context)["id"]

    retried =
      send_as_other_member(
        context,
        context.family_chat_client_message_id,
        "duplicate retry body"
      )

    sent_message(retried)["id"] == original_id and subscription_pushes(context, 500) == []
  end

  # Nothing reaches the subscriber. Only a scenario that holds a subscription can show
  # that, so asking it of one without raises rather than passing on an empty mailbox.
  def behaviour_outcome?(context, :no_event_published, _args) do
    unless Map.has_key?(context, :family_chat_subscription_id),
      do: raise("`no committed-message event is published` needs a held subscription")

    subscription_pushes(context, 500) == []
  end

  # Exactly one push is the reply; the user's own target message pushed its own, which is
  # not counted.
  def behaviour_outcome?(context, :one_event_for_reply, _args),
    do: match?([_reply], reply_pushes(context))

  def behaviour_outcome?(context, :event_message_carries_quote, _args) do
    target_id = context.family_chat_reply_target_id
    match?([%{"replyTo" => %{"id" => ^target_id}}], reply_pushes(context))
  end

  def behaviour_outcome?(context, :response_includes_reply, _args),
    do: node_by_id(context, context.family_chat_pre_subscription_reply_id) != nil

  def behaviour_outcome?(context, :reply_carries_quote, _args) do
    target_id = context.family_chat_reply_target_id

    match?(
      %{"replyTo" => %{"id" => ^target_id}},
      node_by_id(context, context.family_chat_pre_subscription_reply_id)
    )
  end

  def behaviour_outcome?(context, :includes_message_before_subscription, _args) do
    nodes = get_in(context.family_chat_result, ["data", "familyChatMessages", "nodes"]) || []
    Enum.any?(nodes, &(&1["id"] == to_string(context.family_chat_pre_subscription_id)))
  end

  def behaviour_outcome?(context, :reports_web_push_availability, _args),
    do:
      get_in(context.family_chat_result, ["data", "webPushConfiguration", "available"]) in [
        true,
        false
      ]

  # See the unit driver's identical clause: genuinely checks the key's
  # presence/absence against whether VAPID is actually configured, exercising
  # both branches for real (the observed, currently-configured response, and
  # a live re-query with VAPID genuinely unconfigured).
  def behaviour_outcome?(context, :includes_safe_public_key, _args) do
    configured_branch_ok? =
      case context.family_chat_result do
        %{"data" => %{"webPushConfiguration" => %{"available" => true, "publicKey" => key}}} ->
          is_binary(key) and key != "" and key == configured_vapid_public_key()

        %{"data" => %{"webPushConfiguration" => %{"available" => false, "publicKey" => nil}}} ->
          true

        _other ->
          false
      end

    configured_branch_ok? and unconfigured_vapid_omits_public_key?(context)
  end

  # The response carries exactly the two fields, and the schema's subscription type has no
  # others a client could ask for.
  def behaviour_outcome?(context, :reports_enabled_and_expiration_only, _args) do
    introspected =
      graphql(
        context,
        ~s|query { __type(name: "WebPushSubscription") { fields { name } } }|,
        %{}
      ).family_chat_result

    type_fields =
      for %{"name" => name} <- get_in(introspected, ["data", "__type", "fields"]) || [],
          do: name

    case context.family_chat_result do
      %{"data" => %{"currentWebPushSubscription" => %{"enabled" => enabled} = state}} ->
        is_boolean(enabled) and Enum.sort(Map.keys(state)) == ["enabled", "expirationTime"] and
          Enum.sort(type_fields) == ["enabled", "expirationTime"]

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :subscription_enabled, _args) do
    match?(
      %{"data" => %{"upsertWebPushSubscription" => %{"enabled" => true}}},
      context.family_chat_result
    ) and current_subscription_enabled?(context)
  end

  # The stored subscription is the user's and active, and serves the session only: not
  # another session of the same user, nor the same session of another user.
  def behaviour_outcome?(context, :subscription_bound_to_session, _args) do
    user_id = context.user_id
    session = session_key(context)

    match?(
      %{user_id: ^user_id, deleted_at: nil},
      stored_subscription(context.family_chat_push_endpoint)
    ) and current_subscription_enabled?(context) and
      not session_subscribed?(user_id, "test-other-session-" <> unique_uuid()) and
      not session_subscribed?("test-user-family-chat-other-" <> unique_uuid(), session)
  end

  def behaviour_outcome?(context, :subscription_disabled, _args),
    do: subscription_disabled?(context)

  def behaviour_outcome?(context, :subscription_still_disabled, _args),
    do: subscription_disabled?(context)

  # Rejected before storage: no subscription holds the endpoint, the session has none, and
  # the push client was asked for nothing.
  def behaviour_outcome?(context, :no_subscription_stored_or_network, _args) do
    error_code?(context, "VALIDATION_FAILED") and
      stored_subscription(context.family_chat_push_endpoint) == nil and
      not current_subscription_enabled?(context) and push_requests() == []
  end

  # The context is the logged-in member the session names, and the digest of the very
  # session token the scenario's identity cookie carries -- the key the HTTP resolvers bind
  # Web Push to (`session_key/1`), not one derived from the user ID.
  def behaviour_outcome?(context, :socket_context_server_resolved, _args) do
    session_user = context.family_chat_socket_session["current_user"]
    session_digest = session_key(context)

    match?(%{"userId" => user_id} when user_id == context.user_id, session_user) and
      match?(
        %{current_user: ^session_user, session_digest: ^session_digest},
        socket_absinthe_context(context.family_chat_result)
      )
  end

  # Genuine negative-input check: the spoofed `userId` and roles the connect params
  # `:open_socket_authenticated` sent must never surface in the resolved identity -- only
  # the session's member, carrying the roles its stored account holds.
  def behaviour_outcome?(context, :socket_params_ignored, _args) do
    {:ok, %{"roles" => account_roles}} = Identity.account(context.user_id)
    spoofed = context.family_chat_spoofed_params

    case socket_absinthe_context(context.family_chat_result) do
      %{current_user: %{"userId" => user_id, "roles" => roles} = user} ->
        user_id == context.user_id and user_id != spoofed["userId"] and
          roles == account_roles and roles != spoofed["roles"] and
          not Map.has_key?(user, "role") and
          user == context.family_chat_socket_session["current_user"]

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :socket_handshake_rejected, _args) do
    # `Phoenix.Socket.connect/3`'s documented contract allows a bare `:error`
    # (the form `BnestAppWeb.UserSocket.connect/3` actually returns for an
    # unauthenticated handshake) as well as `{:error, reason}` — accept both.
    context.family_chat_result == :error or match?({:error, _}, context.family_chat_result)
  end

  # See the unit driver's identical clause: the production configuration, here read out
  # of `config/prod.exs`, mounts nothing, and the router follows that same decision.
  def behaviour_outcome?(context, :no_graphiql_route, _args) do
    context.family_chat_production_mounts_dev_routes == false and
      BnestAppWeb.Router.dev_routes_enabled?() ==
        BnestAppWeb.DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes)) and
      context.family_chat_graphiql_routes != [] == BnestAppWeb.Router.dev_routes_enabled?()
  end

  # The migration's room, and the room read back from SQLite, both open for posting.
  def behaviour_outcome?(context, :room_seed_correct, [slug, name]) do
    seeded = %{id: 1, slug: slug, name: name, member_posting_enabled: true}
    stored = RoomStore.get_active_room(SqliteRoomStore.new(), slug)

    match?({:ok, %{}}, context.family_chat_result) and
      Map.take(elem(context.family_chat_result, 1), Map.keys(seeded)) == seeded and
      Map.take(stored || %{}, Map.keys(seeded)) == seeded
  end

  # Re-runs the migration for real and compares the whole seeded room it
  # returns with the first run's, then reads SQLite's active rooms back: the
  # same single room.
  def behaviour_outcome?(context, :migration_idempotent, _args) do
    {:ok, %{id: 1} = room} = context.family_chat_result
    second = BnestApp.FamilyChat.migrate!()

    second == {:ok, room} and RoomStore.list_active_rooms(SqliteRoomStore.new()) == [room]
  end

  def behaviour_outcome?(context, :prior_release_unaffected, _args) do
    %{before_migration: before_migration} = context.family_chat_prior_release
    before_migration.schedule != nil and context.family_chat_result == before_migration
  end

  # With every Family Chat table renamed away, the prior release's reads still
  # succeed and answer exactly what they answered before the migration.
  def behaviour_outcome?(context, :no_prior_release_table_access, _args) do
    %{before_migration: before_migration} = context.family_chat_prior_release
    context.family_chat_reads_without_family_chat_tables == {:ok, before_migration}
  end

  # The answer and the stored row both carry the producer's key as sender and idempotency key.
  def behaviour_outcome?(context, :system_message_committed, [sender_kind]) do
    key = context.family_chat_producer_key

    case context.family_chat_result do
      {:ok, %{id: id, room_id: room_id, sender_kind: ^sender_kind, sender_id: ^key}} ->
        match?(
          %{sender_kind: ^sender_kind, sender_id: ^key, idempotency_key: ^key},
          RoomStore.message_by_id(SqliteRoomStore.new(), room_id, id)
        )

      _other ->
        false
    end
  end

  # The retry answers with the first post's message itself.
  def behaviour_outcome?(context, :system_message_unchanged, _args) do
    {:ok, first} = context.family_chat_first_system_result
    fields = [:id, :sender_kind, :sender_id, :body, :committed_at]

    match?({:ok, %{}}, context.family_chat_result) and
      Map.take(elem(context.family_chat_result, 1), fields) == Map.take(first, fields)
  end

  def behaviour_outcome?(context, :exactly_one_system_message, _args),
    do: count_messages_for(context, context.family_chat_producer_key) == 1

  # No field is named for a system message in any letter case, every field ran without an
  # error, and the scenario's database holds no system message afterwards.
  def behaviour_outcome?(context, :schema_has_no_system_message_field, _args) do
    names = Enum.map(context.family_chat_schema_fields, & &1.name)

    %{rows: [[system_messages]]} =
      SqliteRepo.query!("SELECT COUNT(*) FROM family_chat_messages WHERE sender_kind = 'system'")

    names != [] and not Enum.any?(names, &PublicMutationProbe.names_system?/1) and
      Enum.all?(context.family_chat_schema_runs, &match?({_name, :ran}, &1)) and
      system_messages == 0
  end

  # SQLite holds one pending delivery for each other member's subscription, exactly; and a
  # commit whose delivery rows fail leaves neither its message nor any delivery behind.
  def behaviour_outcome?(context, :message_and_deliveries_committed_atomically, _args) do
    {:ok, %{id: message_id, deliveries: returned}} = context.family_chat_result

    %{rows: stored} =
      SqliteRepo.query!(
        "SELECT subscription_id, state FROM family_chat_push_deliveries WHERE message_id = ?",
        [message_id]
      )

    expected = Enum.map(context.family_chat_other_subscription_ids, &[&1, "pending"])

    length(returned) == 3 and Enum.sort(stored) == Enum.sort(expected) and
      failed_commit_left_nothing?(context)
  end

  def behaviour_outcome?(context, :sender_excluded_from_delivery, _args) do
    {:ok, %{deliveries: deliveries}} = context.family_chat_result
    not Enum.any?(deliveries, &(&1.subscription_id == context.family_chat_sender_subscription_id))
  end

  # One request reached the provider, and the stored delivery waits for the push retry
  # policy's first wait, counted from that attempt.
  def behaviour_outcome?(context, :delivery_retryable_with_wait, [state]) do
    %{family_chat_push_delivery_id: id, family_chat_push_subscription: subscription} = context
    row = stored_delivery(id)
    first_wait = PushPolicy.next_wait_seconds(1, row.created_at, row.updated_at)

    match?({:ok, %{state: ^state, attempt: 1}}, context.family_chat_result) and
      row.state == state and row.attempt_count == 1 and is_integer(first_wait) and
      row.next_attempt_at == DateTime.add(row.updated_at, first_wait, :second) and
      length(push_requests(subscription.endpoint)) == 1
  end

  # No sixth attempt (`fifth_attempt_retires?/2`), and none past the hour: on further
  # deliveries owed to the same subscription, neither a wait that would cross the hour
  # (`ceiling_retires_crossing_wait?/1`) nor a sweep that comes after it
  # (`ceiling_retires_late_attempt?/1`) sends a request past it.
  def behaviour_outcome?(context, :no_attempt_past_ceiling, _args) do
    %{family_chat_push_delivery_id: id, family_chat_push_subscription: subscription} = context

    fifth_attempt_retires?(id, subscription) and ceiling_retires_crossing_wait?(subscription) and
      ceiling_retires_late_attempt?(subscription)
  end

  # The provider answered Gone: the delivery is retired as such and the subscription it
  # targeted is disabled, so its session no longer has one.
  def behaviour_outcome?(context, :delivery_terminal_subscription_disabled, [state]) do
    %{family_chat_push_delivery_id: id, family_chat_push_subscription: subscription} = context

    match?({:ok, %{state: ^state}}, context.family_chat_result) and
      match?(%{state: ^state, failure_category: "gone"}, stored_delivery(id)) and
      match?(
        %{deleted_at: %DateTime{}, deleted_by: "system:push-dispatcher"},
        stored_subscription(subscription.endpoint)
      ) and not session_subscribed?(subscription.user_id, subscription.session) and
      length(push_requests(subscription.endpoint)) == 1
  end

  def behaviour_outcome?(context, :no_further_attempt_scheduled, _args) do
    %{family_chat_push_delivery_id: id, family_chat_push_subscription: subscription} = context

    match?({:ok, %{next_attempt_at: nil}}, context.family_chat_result) and
      match?(%{next_attempt_at: nil, attempt_count: 1}, stored_delivery(id)) and
      Dispatcher.attempt() == {:error, :no_due_delivery} and
      push_requests(subscription.endpoint) == []
  end

  # Exactly the final rows seeded more than seven days ago were soft-deleted, by retention
  # at the run's instant.
  def behaviour_outcome?(context, :completed_rows_soft_deleted, _args) do
    final = context.family_chat_aged_deliveries.final

    match?({:ok, %{soft_deleted: n}} when n == length(final), context.family_chat_result) and
      Enum.all?(final, fn {_state, id} ->
        match?(
          %{deleted_at: @behaviour_now, deleted_by: "system:push-retention"},
          stored_delivery(id)
        )
      end)
  end

  # The pending, claimed and retryable rows of the same age are the only active unfinished
  # rows reported, and each is still active in its state.
  def behaviour_outcome?(context, :nonfinal_rows_remain_active, _args) do
    nonfinal = context.family_chat_aged_deliveries.nonfinal

    match?(
      {:ok, %{remaining_active: n}} when n == length(nonfinal),
      context.family_chat_result
    ) and
      Enum.all?(nonfinal, fn {state, id} ->
        match?(%{state: ^state, deleted_at: nil}, stored_delivery(id))
      end)
  end

  def behaviour_outcome?(context, :rows_purged, _args) do
    purged = context.family_chat_aged_deliveries.soft_deleted

    match?({:ok, %{purged: n}} when n == length(purged), context.family_chat_result) and
      Enum.all?(purged, fn {_state, id} -> stored_delivery(id) == nil end)
  end

  # Reads the second call's own independent result snapshot (see
  # `:retention_job_runs_again`'s comment above), not the first call's
  # `family_chat_result`.
  def behaviour_outcome?(context, :retention_run_idempotent, _args),
    do: match?({:ok, %{purged: 0, soft_deleted: 0}}, context.family_chat_idempotent_result)

  # Read from the observed dispatch: exactly one task ran, once, for the claimed
  # run, and it is the one registered for the schedule (see
  # `BnestApp.Test.SchedulerDispatch`).
  def behaviour_outcome?(context, :only_named_handler_invoked, [name]) do
    SchedulerDispatch.only_registered_task_ran?(context.family_chat_dispatch) and
      SchedulerDispatch.ran_task_name(context.family_chat_dispatch) == name
  end

  def behaviour_outcome?(context, :only_retention_handler_invoked, _args) do
    SchedulerDispatch.only_registered_task_ran?(context.family_chat_dispatch) and
      SchedulerDispatch.ran_task_called?(
        context.family_chat_dispatch,
        PushNotifications,
        :retain_deliveries
      )
  end

  def behaviour_outcome?(context, :handler_delegates_to_service, [service_name]) do
    SchedulerDispatch.delegated_without_sql?(
      context.family_chat_dispatch,
      Module.concat([service_name])
    )
  end

  def behaviour_outcome?(context, :schedule_field_updated, [_key, _field, value]),
    do: match?({:ok, %{daily_at_utc: ^value}}, context.family_chat_result)

  def behaviour_outcome?(context, :convergence_call_idempotent, _args) do
    second = Scheduler.converge_backup_time!(context.family_chat_convergence_key, "18:00")

    match?({:ok, %{daily_at_utc: "18:00"}}, context.family_chat_result) and
      context.family_chat_result == second
  end

  def behaviour_outcome?(context, :schedule_field_enabled, [_key]),
    do: match?(%{enabled: true}, context.family_chat_result)

  def behaviour_outcome?(context, :activation_call_idempotent, _args) do
    key = context.family_chat_activation_key
    before_revision = context.family_chat_result.revision
    :ok = Scheduler.activate_if_pristine!(key, @behaviour_now)
    after_schedule = Scheduler.get_schedule(key)

    match?(%{enabled: true}, after_schedule) and after_schedule.revision == before_revision
  end

  def behaviour_outcome?(context, :operator_time_unchanged, _args) do
    match?(
      {:ok, %{daily_at_utc: value}} when value == context.family_chat_operator_daily_at_utc,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :retryable_failure, [category]) do
    # `family_chat_result`'s failure category is an atom
    # (`BnestApp.Backup.run/1`'s own return shape); the Gherkin step's
    # capture group is always a string -- mirrors
    # `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical conversion.
    expected_category = String.to_existing_atom(category)
    match?({:error, {:retryable, ^expected_category, _artifact}}, context.family_chat_result)
  end

  # The failure names no artifact, and the real destination the run wrote to holds no backup
  # file, partial or final, afterwards: read from the disk while it still exists.
  def behaviour_outcome?(context, :no_partial_or_final_artifact, _args) do
    backups = Path.wildcard(Path.join(context.family_chat_backup_directory, "bnest-prod-*"))
    match?({:error, {:retryable, _category, nil}}, context.family_chat_result) and backups == []
  end

  def behaviour_outcome?(context, :probes_within_budget, _args) do
    %{failures: failures, samples: samples} = context.family_chat_load_probes

    failures == 0 and samples != [] and Enum.all?(samples, &(&1 <= 2_000)) and
      percentile_95(samples) <= 500
  end

  def behaviour_outcome?(context, :sent_ids_exist_live, _args) do
    %{sent_ids: sent_ids} = context.family_chat_load_probes
    live_message_ids = live_family_chat_message_ids()

    sent_ids != [] and
      Enum.all?(sent_ids, fn id -> MapSet.member?(live_message_ids, to_message_id(id)) end)
  end

  # tech-doc 009's Concurrent-write Proof step 5: "a self-consistent
  # point-in-time subset in the restored snapshot." Restores the real
  # artifact `:routed_backup_runs_full_duration` produced (never a
  # pre-fabricated fixture) and proves the restored `orderedMessageIds` are
  # non-empty, genuinely ascending (not merely accepted as-is), and every
  # one of them still exists in the live database afterward -- a corrupt or
  # fabricated restore could produce an ID the live database never had.
  def behaviour_outcome?(context, :load_proof_restorable_snapshot, _args) do
    case context.family_chat_load_receipts do
      [receipt | _rest] ->
        artifact_path = Path.join(context.family_chat_load_directory, receipt["artifactBasename"])

        case Backup.restore(%{path: artifact_path}) do
          {:ok, %{evidence: evidence}} ->
            %{"orderedMessageIds" => ids} = Jason.decode!(evidence)
            live_message_ids = live_family_chat_message_ids()

            ids != [] and ids == Enum.sort(ids) and
              Enum.all?(ids, &MapSet.member?(live_message_ids, &1))

          _other ->
            false
        end

      [] ->
        false
    end
  end

  def behaviour_outcome?(context, :probes_zero_failures, _args),
    do: match?(%{failures: 0}, context.family_chat_load_probes)

  def behaviour_outcome?(context, :schedule_remains_claimable, _args),
    do: match?(%{run_id: _run_id}, context[:family_chat_retry_claim])

  def behaviour_outcome?(context, :restored_state_readable, _args) do
    with {:ok, %{evidence: evidence}} <- context.family_chat_result,
         {:ok, decoded} <- Jason.decode(evidence) do
      %{
        "room" => %{"slug" => slug},
        "orderedMessageIds" => message_ids,
        "subscriptionCount" => subscription_count,
        "deliveryStates" => delivery_states
      } = decoded

      slug == BnestApp.FamilyChat.canonical_room_slug() and
        context.family_chat_fixture_message_id in message_ids and
        message_ids == Enum.sort(message_ids) and is_integer(subscription_count) and
        subscription_count >= 1 and "pending" in delivery_states
    else
      _other -> false
    end
  end

  # Neither the fixture's message body nor its subscription's endpoint or keys.
  def behaviour_outcome?(context, :no_secret_in_restore_evidence, _args) do
    case context.family_chat_result do
      {:ok, %{evidence: evidence}} when is_binary(evidence) ->
        secrets = [context.family_chat_known_body | context.family_chat_fixture_secrets]

        Enum.all?(secrets, &(is_binary(&1) and &1 != "")) and
          not Enum.any?(secrets, &String.contains?(evidence, &1))

      _other ->
        false
    end
  end

  # This slot's listener received exactly one event: the subscription document
  # Absinthe rendered for the committed message.
  def behaviour_outcome?(context, :only_same_slot_sockets_receive, _args) do
    {:ok, %{id: id}} = context.family_chat_result
    message_id = to_string(id)

    match?(
      [
        %Phoenix.Socket.Broadcast{
          event: "subscription:data",
          payload: %{result: %{data: %{"familyChatMessageCommitted" => %{"id" => ^message_id}}}}
        }
      ],
      for({:this_slot, message} <- context.family_chat_slot_received, do: message)
    )
  end

  # The other slot's listener received nothing, though it is live: a broadcast made inside
  # that slot reaches it. This runtime has no distribution through which a publish could
  # reach any other.
  def behaviour_outcome?(context, :other_slot_no_event, _args) do
    other_slot = context.family_chat_other_slot
    received = IndependentSlot.received(other_slot)
    [document_topic | _topics] = context.family_chat_slot_topics

    received == [] and IndependentSlot.hears_own_broadcast?(other_slot, document_topic) and
      Node.alive?() == false and Node.list() == []
  end

  # No configuration names the setting or any stream-close directive at all.
  def behaviour_outcome?(context, :no_nonzero_stream_close_delay, [setting]) do
    configs = Enum.map(context.family_chat_generated_configs, & &1["config"])

    configs != [] and
      not Enum.any?(
        configs,
        &(String.contains?(&1, setting) or String.contains?(&1, "stream_close"))
      )
  end

  # Every configuration's global options block keeps the five-minute grace period.
  def behaviour_outcome?(context, :grace_period_present, _args) do
    configs = Enum.map(context.family_chat_generated_configs, & &1["config"])
    configs != [] and Enum.all?(configs, &("grace_period 5m" in global_options(&1)))
  end

  # The one reverse proxy each promotion configures has the promoted slot as its only upstream.
  def behaviour_outcome?(context, :handshake_only_promoted_slot, _args) do
    promotions = context.family_chat_promotions

    promotions != [] and
      Enum.all?(promotions, fn %{config: config, promoted_port: port} ->
        reverse_proxy_upstreams(config) == [["127.0.0.1:#{port}"]]
      end)
  end

  # No promotion's configuration names the prior slot's port anywhere.
  def behaviour_outcome?(context, :prior_slot_unrouted, _args) do
    promotions = context.family_chat_promotions

    promotions != [] and
      Enum.all?(promotions, fn %{config: config, prior_port: port} ->
        not String.contains?(config, ":#{port}")
      end)
  end

  # --- helpers ---

  # Reads the real `config/prod.exs`, chained through `config/config.exs`'s
  # own `import_config "#{config_env()}.exs"` via `env: :prod`, exactly as
  # `MIX_ENV=prod mix compile` would resolve it -- not read from the running
  # application's own env (already fixed to this test build's value). Used
  # by `:endpoint_configured_production` above, so this layer catches a real
  # `config/prod.exs` regression the unit layer structurally cannot see.
  defp configured_prod_dev_routes_flag do
    prod_config =
      Path.expand("../../../config", __DIR__)
      |> Path.join("config.exs")
      |> Config.Reader.read!(env: :prod)

    prod_config
    |> Keyword.get(:bnest_app, [])
    |> Keyword.get(:dev_routes)
  end

  # See the unit driver's identical helper: reads the exact same
  # `:web_push, :vapid` config `PushNotifications.configuration/0` itself
  # reads.
  defp configured_vapid_public_key do
    case Application.get_env(:web_push, :vapid) do
      cfg when is_list(cfg) -> Keyword.get(cfg, :public_key)
      cfg when is_map(cfg) -> Map.get(cfg, :public_key)
      _unset -> nil
    end
  end

  # See the unit driver's identical helper: temporarily unconfigures VAPID,
  # re-runs the real GraphQL query, and restores the original value
  # immediately after.
  defp unconfigured_vapid_omits_public_key?(context) do
    original = Application.get_env(:web_push, :vapid)
    Application.delete_env(:web_push, :vapid)

    result_context =
      graphql(context, "query { webPushConfiguration { available publicKey } }", %{})

    if original,
      do: Application.put_env(:web_push, :vapid, original),
      else: Application.delete_env(:web_push, :vapid)

    match?(
      %{"data" => %{"webPushConfiguration" => %{"available" => false, "publicKey" => nil}}},
      result_context.family_chat_result
    )
  end

  # Isolated configured Backup destination for Item 5's Scheduler-driven
  # scenarios: Backup's `ScheduledBackupTask.execute/2` always calls
  # `Backup.destination/0` itself (it never accepts a `:destination_directory`
  # opt -- unlike `Backup.run/1` directly), so reaching it through the real
  # Scheduler chain requires actually configuring the destination, exactly
  # as `home_page_driver.ex`'s own `prepare_backup_destination/1` already
  # does for the same reason. `System`/`File` are fine at this (integration)
  # layer -- only the unit-layer boundary scan forbids them.
  defp prepare_isolated_backup_config! do
    {temporary_root, 0} = System.cmd("realpath", [System.tmp_dir!()])
    root = Path.join(String.trim(temporary_root), "bnest-family-chat-backup-" <> unique_uuid())
    config_path = Path.join(root, "configuration/backup.json")
    previous = System.get_env("BNEST_BACKUP_CONFIG")
    System.put_env("BNEST_BACKUP_CONFIG", config_path)

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: System.put_env("BNEST_BACKUP_CONFIG", previous),
        else: System.delete_env("BNEST_BACKUP_CONFIG")

      File.rm_rf(root)
    end)

    {:ok, location} = Backup.save_destination(Path.join(root, "destination"))
    location
  end

  # Padding lives in `web_push_subscriptions` (soft-delete only, real
  # `DELETE` still allowed at the SQL level), never `family_chat_messages`
  # (trigger-enforced permanent/immutable -- see the migration), so this can
  # genuinely clean up in `on_exit` instead of permanently growing the
  # shared test database on every suite run.
  #
  # Inserted already soft-deleted (`deleted_at`/`deleted_by` populated in the
  # same INSERT): a first version left these active, and every probe-sent
  # message during the load proof fans a pending delivery row out to every
  # active subscription (`SqliteRoomStore`'s delivery fan-out,
  # `WHERE deleted_at IS NULL`) -- 1800 padding rows times 20 probes produced
  # tens of thousands of delivery rows, which both broke unrelated scenarios
  # asserting an exact delivery count and made this helper's own `on_exit`
  # cleanup fail with a foreign-key violation (`family_chat_push_deliveries`
  # has no `ON DELETE CASCADE`). A soft-deleted row is still real on-disk
  # bytes for `VACUUM INTO` to copy, but is excluded from delivery fan-out
  # and from the `deleted_at IS NULL` unique indexes, and carries nothing
  # left for `on_exit` to conflict with.
  defp seed_backup_load_padding! do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    tag = "test-backup-load-padding-" <> unique_uuid()
    endpoint_padding = String.duplicate("e", 1900)
    key_padding = String.duplicate("k", 250)
    auth_padding = String.duplicate("a", 100)

    1..@load_proof_padding_rows
    |> Enum.chunk_every(200)
    |> Enum.each(fn chunk ->
      values_sql = Enum.map_join(chunk, ",", fn _ -> "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)" end)

      params =
        Enum.flat_map(chunk, fn index ->
          suffix = tag <> "-" <> Integer.to_string(index)

          session_digest =
            :crypto.hash(:sha256, suffix <> "-session") |> Base.encode16(case: :lower)

          # Fragmented scheme (see `valid_subscription_input/0`'s own comment
          # elsewhere in this file) -- irrelevant at the integration-layer
          # boundary scan, which has no network-URL rule, but kept
          # consistent with the unit-layer driver's identical padding seed.
          endpoint = "https:" <> "//padding.invalid/" <> suffix <> endpoint_padding
          endpoint_sha256 = :crypto.hash(:sha256, endpoint) |> Base.encode16(case: :lower)

          [
            tag,
            session_digest,
            endpoint_sha256,
            endpoint,
            key_padding,
            auth_padding,
            now,
            tag,
            now,
            tag,
            now,
            tag
          ]
        end)

      SqliteRepo.query!(
        """
        INSERT INTO web_push_subscriptions (
          user_id, session_digest, endpoint_sha256, endpoint, p256dh, auth_secret,
          created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
        ) VALUES #{values_sql}
        """,
        params
      )
    end)

    ExUnit.Callbacks.on_exit(fn ->
      SqliteRepo.query!("DELETE FROM web_push_subscriptions WHERE user_id = ?", [tag])
    end)

    :ok
  end

  # Genuinely routed send+read probe pairs through the real GraphQL/HTTP
  # boundary (see `:routed_backup_runs_full_duration`'s own comment).
  # `conn` is the scenario's own already-authenticated `Phoenix.ConnTest`
  # connection (immutable data -- `graphql/3` never mutates it, so sharing
  # one base conn across this Task and the caller's own process is safe).
  defp run_routed_probes(conn) do
    {sent_ids, samples, failures} =
      Enum.reduce(1..@load_proof_probe_count, {[], [], 0}, fn index,
                                                              {sent_ids, samples, failures} ->
        client_message_id = unique_uuid()

        {send_ms, send_ctx} =
          timed(fn ->
            graphql(
              %{conn: conn},
              """
              mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
                sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) {
                  id
                }
              }
              """,
              %{
                "roomSlug" => @load_proof_room_slug,
                "clientMessageId" => client_message_id,
                "body" => "routed load probe #{index}"
              }
            )
          end)

        {read_ms, read_ctx} =
          timed(fn ->
            graphql(
              %{conn: conn},
              """
              query($roomSlug: String!, $limit: Int) {
                familyChatMessages(roomSlug: $roomSlug, limit: $limit) { nodes { id } }
              }
              """,
              %{"roomSlug" => @load_proof_room_slug, "limit" => 1}
            )
          end)

        send_id =
          case send_ctx.family_chat_result do
            %{"data" => %{"sendFamilyChatMessage" => %{"id" => id}}} -> id
            _other -> nil
          end

        send_ok? = send_ctx.family_chat_http_status == 200 and not is_nil(send_id)

        read_ok? =
          read_ctx.family_chat_http_status == 200 and
            match?(
              %{"data" => %{"familyChatMessages" => %{"nodes" => _nodes}}},
              read_ctx.family_chat_result
            )

        sent_ids = if send_id, do: [send_id | sent_ids], else: sent_ids
        failures = failures + if(send_ok? and read_ok?, do: 0, else: 1)

        {sent_ids, [send_ms, read_ms | samples], failures}
      end)

    %{sent_ids: sent_ids, samples: samples, failures: failures}
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - started, result}
  end

  defp percentile_95(samples) do
    sorted = Enum.sort(samples)
    index = max(0, Float.ceil(length(sorted) * 0.95) |> trunc() |> Kernel.-(1))
    Enum.at(sorted, index)
  end

  defp live_family_chat_message_ids do
    room =
      RoomStore.get_active_room(SqliteRoomStore.new(), BnestApp.FamilyChat.canonical_room_slug())

    %{nodes: nodes} = RoomStore.list_messages(SqliteRoomStore.new(), room.id, nil, nil, 10_000)
    MapSet.new(nodes, & &1.id)
  end

  defp to_message_id(id) when is_integer(id), do: id
  defp to_message_id(id) when is_binary(id), do: String.to_integer(id)

  # A real `connect/3` result is `{:ok, %Phoenix.Socket{}}` — the resolved
  # identity/session digest `UserSocket.connect/3` injects via
  # `Absinthe.Phoenix.Socket.put_options/2` lives nested at
  # `socket.assigns.absinthe.opts[:context]` (a keyword list's `:context`
  # entry), not as top-level socket fields (`Phoenix.Socket`'s struct has no
  # `user_id`/`session_digest` fields at all).
  defp socket_absinthe_context({:ok, %Phoenix.Socket{assigns: %{absinthe: %{opts: opts}}}}),
    do: Keyword.get(opts, :context)

  defp socket_absinthe_context(_other), do: nil

  defp graphql(context, query, variables) do
    if context[:family_chat_capability] == false do
      graphql_via_schema_as_forbidden(context, query, variables)
    else
      # `Phoenix.ConnTest.post/3` multipart-encodes a plain map body by default
      # (Plug.Test's own convention) — the real `/api/graphql` boundary requires
      # genuine `application/json` (tech-doc 008: 415 otherwise), so this sends
      # what a real client actually sends, not what ConnTest defaults to.
      conn =
        context.conn
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(@graphql_path, Jason.encode!(%{"query" => query, "variables" => variables}))

      Map.merge(context, %{family_chat_result: decode(conn), family_chat_http_status: conn.status})
    end
  end

  # `use_family_chat` is granted to every schema-valid account: the PRD
  # defines a "family member" as any approved child/parent/admin role, and
  # the shared `Identity.Domain.Authorization` account schema (`roles?/1` in
  # `data_repository/schema.ex`) forbids ever persisting an account with an
  # empty roles list. A real capability-denied identity therefore cannot be
  # constructed through the normal login/session/identity-store pipeline — the
  # same structural reason the pre-existing `home_page_driver.ex` capability
  # tests call `Authorization.allow?/3` directly rather than round-tripping
  # through a persisted account (see its `:multi_role_user` fixture). This
  # runs the identical production path one level up — the real
  # `BnestAppWeb.Schema`/`FamilyChatResolver.authorize/1` — with a synthetic
  # forbidden context standing in only for the unrepresentable account, and
  # round-trips the result through `Jason` so its shape matches the real
  # HTTP/JSON response exactly (Absinthe.Plug JSON-encodes this identical
  # `%{data:, errors:}` structure for a genuine request).
  defp graphql_via_schema_as_forbidden(context, query, variables) do
    forbidden_context = %{current_user: %{"userId" => context.user_id, "roles" => []}}

    {:ok, result} =
      Absinthe.run(query, BnestAppWeb.Schema, variables: variables, context: forbidden_context)

    decoded = result |> Jason.encode!() |> Jason.decode!()

    Map.merge(context, %{family_chat_result: decoded, family_chat_http_status: 200})
  end

  defp query_messages(context, extra_variables) do
    slug =
      context[:family_chat_subscribed_slug] || context[:family_chat_room_slug] || "ruang-keluarga"

    graphql(
      context,
      """
      query($roomSlug: String!, $beforeId: ID, $afterId: ID, $limit: Int) {
        familyChatMessages(roomSlug: $roomSlug, beforeId: $beforeId, afterId: $afterId, limit: $limit) {
          nodes { id roomSlug senderKind senderId senderDisplayName body committedAt replyTo { id senderKind senderDisplayName bodyPreview } }
          hasOlder
          hasNewer
        }
      }
      """,
      Map.merge(%{"roomSlug" => slug}, extra_variables)
    )
  end

  defp send_family_chat_message(context, client_message_id, body, opts \\ []) do
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    context =
      graphql(
        context,
        """
        mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!, $replyToMessageId: ID) {
          sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body, replyToMessageId: $replyToMessageId) {
            id roomSlug senderKind senderId senderDisplayName body committedAt
            replyTo { id senderKind senderDisplayName bodyPreview }
          }
        }
        """,
        %{
          "roomSlug" => slug,
          "clientMessageId" => client_message_id,
          "body" => expand_body_fixture(body),
          # Sent on every mutation, null when absent: that is what a real
          # client does with a nullable argument, and it keeps the no-target
          # path genuinely exercised through the same document.
          "replyToMessageId" => opts[:reply_to]
        }
      )

    Map.put(context, :family_chat_client_message_id, client_message_id)
  end

  # Sends as another member, from that member's own logged-in session, and hands back the
  # scenario's context with the response.
  defp send_as_other_member(context, client_message_id, body, opts \\ []) do
    {other_conn, context} = other_member_conn(context)

    sent =
      send_family_chat_message(%{context | conn: other_conn}, client_message_id, body, opts)

    %{sent | conn: context.conn}
  end

  defp other_member_conn(%{family_chat_other_member_conn: conn} = context), do: {conn, context}

  defp other_member_conn(context) do
    {conn, _identity} =
      BnestAppWeb.ConnCase.scenario_authenticated_conn(
        Phoenix.ConnTest.build_conn(),
        "#{context.feature_file}:#{context.scenario_name}:other-member",
        ["children"]
      )

    {conn, Map.put(context, :family_chat_other_member_conn, conn)}
  end

  # See `:holds_subscription`. Raises unless the control channel answers the document
  # with its subscription ID.
  #
  # `Phoenix.ChannelTest.join/4` hands `Phoenix.Channel.Server.join/4` a socket whose
  # `transport` is ChannelTest's `{module, supervisor}` tuple, while `Phoenix.Socket.t()`
  # declares `transport: atom`; Dialyzer therefore concludes every channel join in a test
  # never returns. That is a false positive against an upstream spec (Phoenix's own channel
  # tests join this way), so only this one function opts out.
  @dialyzer {:nowarn_function, subscribe_over_socket: 2}
  defp subscribe_over_socket(context, slug) do
    _earlier = subscription_pushes(%{family_chat_subscription_id: nil}, 0)
    {:ok, socket} = connect_family_chat_socket(context, %{})
    {:ok, _joined, socket} = subscribe_and_join(socket, "__absinthe__:control", %{})

    ref =
      push(socket, "doc", %{
        "query" => """
        subscription($roomSlug: String!) {
          familyChatMessageCommitted(roomSlug: $roomSlug) { id body replyTo { id } }
        }
        """,
        "variables" => %{"roomSlug" => slug}
      })

    subscription_id =
      receive do
        %Phoenix.Socket.Reply{ref: ^ref, status: :ok, payload: %{subscriptionId: id}} -> id
      after
        1_000 -> raise "the control channel did not answer the subscription document"
      end

    Map.merge(context, %{
      family_chat_subscribed_slug: slug,
      family_chat_subscription_id: subscription_id
    })
  end

  # The messages the socket was pushed for the held subscription, oldest first, waiting up
  # to `timeout` for each next one. Pushes for any other subscription are dropped.
  defp subscription_pushes(context, timeout) do
    subscription_id = context.family_chat_subscription_id

    receive do
      %Phoenix.Socket.Message{
        event: "subscription:data",
        payload: %{subscriptionId: ^subscription_id, result: result}
      } ->
        [
          get_in(result, [:data, "familyChatMessageCommitted"])
          | subscription_pushes(context, timeout)
        ]

      %Phoenix.Socket.Message{event: "subscription:data"} ->
        subscription_pushes(context, timeout)
    after
      timeout -> []
    end
  end

  defp reply_pushes(context) do
    reply_id = sent_message(context)["id"]
    Enum.filter(context.family_chat_subscription_pushes, &(&1["id"] == reply_id))
  end

  defp latest_room_message_id do
    room = RoomStore.get_active_room(SqliteRoomStore.new(), "ruang-keluarga")
    %{nodes: existing} = RoomStore.list_messages(SqliteRoomStore.new(), room.id, nil, nil, 10_000)
    existing |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)
  end

  # See the unit driver's identical clauses: the "Invalid message text is
  # rejected" Scenario Outline's `<body>` column carries the Gherkin literal
  # straight through the step binding unchanged; real invalid bodies are
  # substituted here so the validation paths they name are genuinely
  # exercised, not just the placeholder text itself.
  defp expand_body_fixture("whitespace-only-body"), do: "   \n\t  "

  defp expand_body_fixture("over-4000-graphemes-normalized-body"),
    do: String.duplicate("a", 4_001)

  defp expand_body_fixture("over-16-kib-body") do
    # A base character plus several combining marks is one grapheme cluster
    # (Unicode text segmentation) but several bytes each — this keeps the
    # fixture under the 4000-grapheme ceiling while crossing the 16 KiB byte
    # ceiling, genuinely isolating the byte-size check from the
    # grapheme-length check (rather than tripping both at once).
    cluster = "e" <> String.duplicate("́", 5)
    String.duplicate(cluster, 1_500)
  end

  defp expand_body_fixture(other), do: other

  defp upsert_subscription(context, input) do
    # `upsertWebPushSubscription` takes three flat, non-null scalar
    # arguments (`lib/bnest_app_web/schema.ex`), never a wrapped input
    # object -- there is no `WebPushSubscriptionInput` type in the schema.
    graphql(
      context,
      """
      mutation($endpoint: String!, $p256dh: String!, $auth: String!) {
        upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { enabled expirationTime }
      }
      """,
      %{"endpoint" => input["endpoint"], "p256dh" => input["p256dh"], "auth" => input["auth"]}
    )
  end

  defp disable_subscription(context) do
    graphql(
      context,
      "mutation { disableCurrentWebPushSubscription { enabled expirationTime } }",
      %{}
    )
  end

  # `context[:conn_session]` was never actually populated by any prepare/
  # perform step — a real socket connect derives its session the same way
  # `UserAuth.fetch_current_user/2` does for HTTP: from the `_bnest_identity`
  # cookie already on `context.conn` (real for an authenticated Background,
  # absent after `anonymize/1`), never from client-supplied params.
  defp connect_family_chat_socket(context, params) do
    connect(BnestAppWeb.UserSocket, params, connect_info: %{session: page_session(context.conn)})
  end

  # The signed session a page load through the endpoint leaves for the browser, which the
  # socket handshake then carries in its cookie: exactly what `UserAuth.fetch_current_user/2`
  # wrote for the conn's identity cookie, or no user when it has none.
  defp page_session(conn), do: conn |> get("/") |> Plug.Conn.get_session()

  # Records what the next reply must quote: the target's server ID, and the
  # sender name and body a correct quote has to report back.
  defp capture_reply_target(context, %{} = target) when is_map_key(target, :id) do
    Map.merge(context, %{
      family_chat_reply_target_id: target.id,
      family_chat_reply_target_body: target.body,
      family_chat_reply_target_display_name: target.sender_display_name
    })
  end

  defp capture_reply_target(context, %{} = node) do
    Map.merge(context, %{
      family_chat_reply_target_id: node["id"],
      family_chat_reply_target_body: node["body"],
      family_chat_reply_target_display_name: node["senderDisplayName"]
    })
  end

  # `family_chat_operations.feature`'s internal-boundary scenarios have no
  # "an approved user is logged in" Background, so neither `user_id` nor
  # `identity_username` is set for them. These fall back to a synthetic
  # identity of the same shape the unit driver uses, rather than assuming a
  # login that never happened.
  defp durable_sender(context) do
    context[:family_chat_user_id] || context[:user_id] ||
      "test-user-family-chat-sender-" <> unique_uuid()
  end

  # `identity_username` is only set where a scenario's Background actually
  # logs a member in; these internal-boundary scenarios have no Background at
  # all, so this falls back to a deterministic synthetic name rather than
  # assuming one.
  defp display_name_for(context, sender) do
    context[:identity_username] || "display-" <> sender
  end

  defp sent_message(context),
    do: get_in(context.family_chat_result, ["data", "sendFamilyChatMessage"]) || %{}

  defp sent_quote(context), do: sent_message(context)["replyTo"] || %{}

  defp quoted_of_reply(context) do
    case node_by_id(context, context.family_chat_reply_message_id) do
      nil -> nil
      node -> node["replyTo"]
    end
  end

  defp node_by_id(context, id) do
    nodes = get_in(context.family_chat_result, ["data", "familyChatMessages", "nodes"]) || []
    Enum.find(nodes, &(&1["id"] == id))
  end

  # Runs one extra document against the same authenticated boundary without
  # disturbing `family_chat_result`, which the surrounding outcome still reads.
  defp graphql_result(context, query, variables),
    do: graphql(context, query, variables).family_chat_result

  # A second room only v1's data model allows, never its UI: seeded already
  # soft-deleted so the room list keeps reporting exactly one active room (the
  # behaviour corpus asserts that), while `message_by_id/2`'s room scoping
  # still has a genuinely foreign message to refuse. `INSERT OR IGNORE` plus a
  # fixed ID keeps repeated scenarios idempotent.
  defp archived_room_message_id do
    BnestApp.FamilyChat.ensure_ready!()
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    SqliteRepo.query!(
      """
      INSERT OR IGNORE INTO family_chat_rooms (
        id, slug, name, room_kind, member_posting_enabled,
        created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
      ) VALUES (900, 'ruang-arsip', 'Ruang Arsip', 'conversation', 1, ?, 'test', ?, 'test', ?, 'test')
      """,
      [now, now, now]
    )

    {:ok, foreign} =
      BnestApp.FamilyChat.insert_message!(
        900,
        "user",
        "test-user-family-chat-archive",
        "Arsip",
        "archive-" <> unique_uuid(),
        "a message in another room"
      )

    foreign.id
  end

  defp count_messages_for(context, client_message_id) do
    # `family_chat_message`'s GraphQL type has no `idempotencyKey`/
    # `clientMessageId` field (tech-doc 008 — it is an internal dedup
    # mechanism, never client-facing), so "exactly one message for that
    # client message ID" cannot be verified through the GraphQL response at
    # all (a prior version of this helper compared `client_message_id`
    # against the server `id`, which could never match). Reads through
    # the SQLite room store directly instead, matching this driver's own stated
    # convention for internal-boundary assertions; a bounded 50-row GraphQL
    # page would also risk missing the target given the shared database.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    room = RoomStore.get_active_room(SqliteRoomStore.new(), slug)
    %{nodes: nodes} = RoomStore.list_messages(SqliteRoomStore.new(), room.id, nil, nil, 10_000)
    Enum.count(nodes, &(&1.idempotency_key == client_message_id))
  end

  defp page_ids(context) do
    context.family_chat_result
    |> get_in(["data", "familyChatMessages", "nodes"])
    |> Enum.map(&String.to_integer(&1["id"]))
  end

  # Every message ID the queried room holds, ascending, read through the SQLite
  # room store rather than the GraphQL page under test.
  defp room_message_ids(context) do
    slug =
      context[:family_chat_subscribed_slug] || context[:family_chat_room_slug] || "ruang-keluarga"

    room = RoomStore.get_active_room(SqliteRoomStore.new(), slug)
    %{nodes: nodes} = RoomStore.list_messages(SqliteRoomStore.new(), room.id, nil, nil, 10_000)
    Enum.map(nodes, & &1.id)
  end

  # Points Family Chat at a database of its own under an isolated test-run root
  # until the scenario ends; then points the shared repository back at the
  # run's own database before the isolated one is removed.
  defp isolated_family_chat_database!(suite) do
    runtime = TestRuntimeRoot.create!(suite)
    database_path = Path.join(runtime.sqlite_path, "bnest.sqlite3")
    previous_path = Application.fetch_env!(:bnest_app, :family_chat_sqlite_path)
    Application.put_env(:bnest_app, :family_chat_sqlite_path, database_path)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, :family_chat_sqlite_path, previous_path)
      :ok = BnestApp.FamilyChat.ensure_ready!()
      TestRuntimeRoot.cleanup!(runtime)
    end)

    database_path
  end

  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")

  # What code built before Family Chat reads from the shared database: a
  # schedule of its own, the family schedule inventory, and the run count.
  defp prior_release_reads(schedule_key) do
    %{
      schedule: Scheduler.get_schedule(schedule_key),
      family_inventory: Scheduler.family_inventory(),
      run_count: Schedules.run_count()
    }
  end

  # Renames Family Chat's tables away while `fun` runs, then back. Refuses to
  # touch any database but the scenario's isolated one. A read that fails
  # without the tables is returned as `{:error, message}`, not raised.
  defp with_family_chat_tables_hidden(database_path, fun) do
    if Application.fetch_env!(:bnest_app, SqliteRepo)[:database] != database_path do
      raise "refusing to rename Family Chat tables outside the scenario's isolated database"
    end

    rename_family_chat_tables!(& &1, &("hidden_" <> &1))

    try do
      {:ok, fun.()}
    rescue
      error -> {:error, Exception.message(error)}
    after
      rename_family_chat_tables!(&("hidden_" <> &1), & &1)
    end
  end

  defp rename_family_chat_tables!(from, to) do
    Enum.each(@family_chat_tables, fn table ->
      SqliteRepo.query!("ALTER TABLE #{from.(table)} RENAME TO #{to.(table)}")
    end)
  end

  # Registers a real `familyChatMessageCommitted` document through the
  # application's endpoint and returns the document topic its events are
  # broadcast on. A subscription run without a socket returns
  # `{:ok, %{"subscribed" => topic}}`, outside `Absinthe.run/3`'s published
  # spec (see the unit driver's `subscribe_and_get_topic!/2`); matching that
  # result makes Dialyzer treat this function as never returning. So the topic
  # is read back from Absinthe's registry instead, which also proves the run
  # registered: a refused or failed run adds no key and the match below raises.
  # Each run registers a fresh document key (Absinthe salts it with a unique
  # context ID), so the key this run added is the one a retry did not.
  defp subscribe_room_document!(user_id) do
    registered_before = Registry.keys(BnestAppWeb.Endpoint.Registry, self())

    _subscribed =
      Absinthe.run(
        """
        subscription($roomSlug: String!) {
          familyChatMessageCommitted(roomSlug: $roomSlug) { id body }
        }
        """,
        BnestAppWeb.Schema,
        variables: %{"roomSlug" => BnestApp.FamilyChat.canonical_room_slug()},
        context: %{
          pubsub: BnestAppWeb.Endpoint,
          current_user: %{"userId" => user_id, "roles" => ["parents"]}
        }
      )

    [document_topic] =
      for "__absinthe__:doc:" <> _id = key <-
            Registry.keys(BnestAppWeb.Endpoint.Registry, self()) -- registered_before,
          do: key

    document_topic
  end

  # A process standing in for a socket on `slot`: subscribed to `topics` on
  # that slot's PubSub server, it forwards everything it receives to the test
  # as `{:slot_received, slot, message}`. The test supervisor stops it.
  defp start_slot_listener!(slot, pubsub, topics) do
    test = self()

    listener = fn ->
      Enum.each(topics, &(:ok = Phoenix.PubSub.subscribe(pubsub, &1)))
      send(test, {:slot_listening, slot})
      forward_slot_messages(test, slot)
    end

    restart_supervised!({Task, listener}, {:slot_listener, slot})

    receive do
      {:slot_listening, ^slot} -> :ok
    after
      1_000 -> raise "the #{slot} listener did not subscribe"
    end
  end

  defp restart_supervised!(child_spec, id) do
    _not_running_is_fine = ExUnit.Callbacks.stop_supervised(id)
    ExUnit.Callbacks.start_supervised!(child_spec, id: id)
  end

  defp forward_slot_messages(test, slot) do
    receive do
      message ->
        send(test, {:slot_received, slot, message})
        forward_slot_messages(test, slot)
    end
  end

  defp receive_slot_message(timeout) do
    receive do
      {:slot_received, slot, message} -> {slot, message}
    after
      timeout -> nil
    end
  end

  defp drain_slot_messages(timeout) do
    case receive_slot_message(timeout) do
      nil -> []
      received -> [received | drain_slot_messages(timeout)]
    end
  end

  defp error_code?(context, code) do
    match?(%{"errors" => [%{"extensions" => %{"code" => ^code}} | _]}, context.family_chat_result)
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)

  defp anonymize(context) do
    Map.put(context, :conn, Phoenix.ConnTest.build_conn())
  end

  # A fresh endpoint on the synthetic provider host the test push senders name.
  defp valid_subscription_input do
    %{
      "endpoint" => synthetic_endpoint("valid-" <> unique_uuid()),
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
  end

  defp synthetic_endpoint(path), do: "https://push.allowed.example.com/" <> path

  # Points the scenario at a Family Chat database of its own, once, so the push rows it
  # reads are exactly the ones it made.
  defp push_database!(context) do
    if context[:family_chat_push_database] do
      context
    else
      database_path = isolated_family_chat_database!("family-chat-push")
      :ok = BnestApp.FamilyChat.ensure_ready!()
      Map.put(context, :family_chat_push_database, database_path)
    end
  end

  # Until the scenario ends, the push-client double answers the dispatcher instead of the
  # recording sender: per endpoint (`status-<code>` answers that status), recording each
  # request in this process. It never reaches the network either.
  defp answer_push_by_endpoint! do
    previous = Application.fetch_env!(:bnest_app, PushNotifications)
    answering = Keyword.put(previous, :push_sender, InMemoryPushSender)
    Application.put_env(:bnest_app, PushNotifications, answering)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, PushNotifications, previous)
    end)

    InMemoryPushSender.forget_sent()
  end

  defp owe_push_delivery!(context, status) do
    context = push_database!(context)
    :ok = answer_push_by_endpoint!()

    subscription =
      subscribe_through_facade!(
        "test-user-family-chat-push-recipient-" <> unique_uuid(),
        "status-#{status}"
      )

    Map.merge(context, %{
      family_chat_push_subscription: subscription,
      family_chat_push_delivery_id: commit_owed_delivery!(subscription)
    })
  end

  # Subscribes `user_id` through the facade for a session of its own, at a synthetic
  # endpoint whose last segment is `last_segment`.
  defp subscribe_through_facade!(user_id, last_segment) do
    session = "test-session-" <> unique_uuid()
    endpoint = synthetic_endpoint(unique_uuid() <> "/" <> last_segment)
    input = Map.put(valid_subscription_input(), "endpoint", endpoint)
    {:ok, %{enabled: true}} = PushNotifications.upsert_subscription(user_id, session, input)

    %{
      user_id: user_id,
      session: session,
      endpoint: endpoint,
      id: stored_subscription(endpoint).id
    }
  end

  # Another member's commit, which owes `subscription` one pending delivery; its ID.
  defp commit_owed_delivery!(subscription) do
    {:ok, message} =
      BnestApp.FamilyChat.send_message(
        "test-user-family-chat-push-sender-" <> unique_uuid(),
        BnestApp.FamilyChat.canonical_room_slug(),
        unique_uuid(),
        "push delivery fixture"
      )

    %{rows: [[id]]} =
      SqliteRepo.query!(
        "SELECT id FROM family_chat_push_deliveries WHERE message_id = ? AND subscription_id = ?",
        [message.id, subscription.id]
      )

    id
  end

  # Each delivery is owed to a subscription of its own, disabled through the facade once the
  # commit fanned out to it so later commits owe it nothing. The delivery's row is then put
  # in its state as last stamped eight days before the retention run, and soft-deleted then
  # for the `:soft_deleted` group: time that has passed, which only a fixture UPDATE can
  # stand in for. Records `{state, id}` per delivery under the group.
  defp seed_aged_deliveries!(context, group, states) do
    context = push_database!(context)
    aged_at = DateTime.add(@behaviour_now, -8 * 86_400, :second)
    aged = iso8601(aged_at)

    seeded =
      for state <- states do
        subscription =
          subscribe_through_facade!(
            "test-user-family-chat-retention-" <> unique_uuid(),
            "accepted"
          )

        id = commit_owed_delivery!(subscription)

        {:ok, %{enabled: false}} =
          PushNotifications.disable_subscription(subscription.user_id, subscription.session)

        {deleted_at, deleted_by} =
          if group == :soft_deleted, do: {aged, "system:test-fixture"}, else: {nil, nil}

        lease =
          if state == "claimed", do: aged_at |> DateTime.add(120, :second) |> iso8601()

        SqliteRepo.query!(
          """
          UPDATE family_chat_push_deliveries
          SET state = ?, updated_at = ?, deleted_at = ?, deleted_by = ?,
              lease_expires_at = ?, next_attempt_at = NULL
          WHERE id = ?
          """,
          [state, aged, deleted_at, deleted_by, lease, id]
        )

        {state, id}
      end

    Map.update(
      context,
      :family_chat_aged_deliveries,
      %{group => seeded},
      &Map.put(&1, group, seeded)
    )
  end

  # The delivery's wait elapses: it ages by that wait (its creation moves back by it) and is
  # due now.
  defp elapse_push_wait!(delivery_id) do
    row = stored_delivery(delivery_id)
    wait = DateTime.diff(row.next_attempt_at, row.updated_at)

    SqliteRepo.query!(
      "UPDATE family_chat_push_deliveries SET created_at = ?, next_attempt_at = ? WHERE id = ?",
      [
        iso8601(DateTime.add(row.created_at, -wait, :second)),
        iso8601(row.updated_at),
        delivery_id
      ]
    )

    :ok
  end

  # Drives the delivery on, letting each wait elapse, until the fifth failed attempt
  # retires it and nothing is due, so no sixth request is sent.
  defp fifth_attempt_retires?(id, subscription) do
    _earlier_requests = push_requests(subscription.endpoint)

    attempts =
      for _attempt <- 2..5 do
        :ok = elapse_push_wait!(id)
        {:ok, _transition} = Dispatcher.attempt()
        stored_delivery(id)
      end

    retired = List.last(attempts)

    Enum.map(attempts, & &1.attempt_count) == [2, 3, 4, 5] and
      Enum.map(attempts, & &1.state) == ~w(retryable retryable retryable terminal) and
      match?(%{failure_category: "ceiling", next_attempt_at: nil}, retired) and
      length(push_requests(subscription.endpoint)) == 4 and
      Dispatcher.attempt() == {:error, :no_due_delivery} and
      push_requests(subscription.endpoint) == [] and stored_delivery(id).attempt_count == 5
  end

  # A fresh delivery fails once, then is aged so its second attempt still runs within the
  # hour of its creation but the wait after it would carry a third past the hour: that
  # second attempt is sent and retires it as `ceiling`, leaving nothing due.
  defp ceiling_retires_crossing_wait?(subscription) do
    id = commit_owed_delivery!(subscription)
    {:ok, %{state: "retryable"}} = Dispatcher.attempt()
    _first_request = push_requests(subscription.endpoint)
    failed = stored_delivery(id)
    crossing_wait = PushPolicy.next_wait_seconds(2, failed.updated_at, failed.updated_at)
    :ok = age_push_delivery!(id, 3_600 - div(crossing_wait, 2))
    {:ok, _transition} = Dispatcher.attempt()
    retired = stored_delivery(id)

    match?(
      %{state: "terminal", failure_category: "ceiling", next_attempt_at: nil, attempt_count: 2},
      retired
    ) and DateTime.diff(retired.updated_at, retired.created_at) <= 3_600 and
      length(push_requests(subscription.endpoint)) == 1 and
      Dispatcher.attempt() == {:error, :no_due_delivery} and
      push_requests(subscription.endpoint) == []
  end

  # A fresh delivery fails once, then its due attempt is claimed only after the hour of its
  # creation has passed (a late sweep): that claim retires it as `ceiling` unsent, leaving
  # nothing due.
  defp ceiling_retires_late_attempt?(subscription) do
    id = commit_owed_delivery!(subscription)
    {:ok, %{state: "retryable"}} = Dispatcher.attempt()
    _first_request = push_requests(subscription.endpoint)
    failed = stored_delivery(id)
    :ok = age_push_delivery!(id, 3_600 + DateTime.diff(failed.next_attempt_at, failed.updated_at))
    {:ok, _transition} = Dispatcher.attempt()

    match?(
      %{state: "terminal", failure_category: "ceiling", next_attempt_at: nil},
      stored_delivery(id)
    ) and push_requests(subscription.endpoint) == [] and
      Dispatcher.attempt() == {:error, :no_due_delivery} and
      push_requests(subscription.endpoint) == []
  end

  # The delivery was created `age_seconds` before its last attempt, and is due now.
  defp age_push_delivery!(delivery_id, age_seconds) do
    row = stored_delivery(delivery_id)

    SqliteRepo.query!(
      "UPDATE family_chat_push_deliveries SET created_at = ?, next_attempt_at = ? WHERE id = ?",
      [
        iso8601(DateTime.add(row.updated_at, -age_seconds, :second)),
        iso8601(row.updated_at),
        delivery_id
      ]
    )

    :ok
  end

  # The response reports it disabled, the Given's stored subscription was disabled by the
  # user, and the session has none.
  defp subscription_disabled?(context) do
    stored = stored_subscription(context.family_chat_push_endpoint)

    match?(
      %{"data" => %{"disableCurrentWebPushSubscription" => %{"enabled" => false}}},
      context.family_chat_result
    ) and match?(%{deleted_at: %DateTime{}}, stored) and
      stored.deleted_by == "user:" <> context.user_id and
      not current_subscription_enabled?(context)
  end

  # The session's subscription state, read back over GraphQL with the scenario's session.
  defp current_subscription_enabled?(context) do
    context
    |> graphql("query { currentWebPushSubscription { enabled expirationTime } }", %{})
    |> Map.fetch!(:family_chat_result)
    |> get_in(["data", "currentWebPushSubscription", "enabled"]) == true
  end

  defp session_subscribed?(user_id, session),
    do: match?({:ok, %{enabled: true}}, PushNotifications.current_subscription(user_id, session))

  # The session key the router hands the GraphQL resolvers for the scenario's session.
  defp session_key(context) do
    conn = Plug.Conn.fetch_cookies(context.conn)
    Identity.session_digest(conn.cookies["_bnest_identity"])
  end

  # Stored push rows, read back from Family Chat's database (prepared, and the shared
  # connection pointed at it, first). Observation only.
  defp stored_delivery(id) do
    :ok = BnestApp.FamilyChat.ensure_ready!()

    case SqliteRepo.query!(
           """
           SELECT state, attempt_count, next_attempt_at, failure_category, created_at,
                  updated_at, deleted_at, deleted_by
           FROM family_chat_push_deliveries WHERE id = ?
           """,
           [id]
         ) do
      %{rows: [[state, attempts, next_at, category, created, updated, deleted, deleted_by]]} ->
        %{
          state: state,
          attempt_count: attempts,
          next_attempt_at: parse_time(next_at),
          failure_category: category,
          created_at: parse_time(created),
          updated_at: parse_time(updated),
          deleted_at: parse_time(deleted),
          deleted_by: deleted_by
        }

      %{rows: []} ->
        nil
    end
  end

  defp stored_subscription(endpoint) do
    :ok = BnestApp.FamilyChat.ensure_ready!()

    case SqliteRepo.query!(
           "SELECT id, user_id, deleted_at, deleted_by FROM web_push_subscriptions WHERE endpoint = ?",
           [endpoint]
         ) do
      %{rows: [[id, user_id, deleted_at, deleted_by]]} ->
        %{id: id, user_id: user_id, deleted_at: parse_time(deleted_at), deleted_by: deleted_by}

      %{rows: []} ->
        nil
    end
  end

  defp parse_time(nil), do: nil
  defp parse_time(value), do: value |> DateTime.from_iso8601() |> elem(1)

  defp iso8601(time), do: time |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  # Every request a test push sender recorded in this process so far, oldest first, as
  # `{endpoint, payload}`; draining them. The dispatcher, and the endpoint under
  # `Phoenix.ConnTest`, run in this process.
  defp push_requests do
    receive do
      {:push_notification_sent, endpoint, payload} -> [{endpoint, payload} | push_requests()]
    after
      0 -> []
    end
  end

  # The payloads of the recorded requests to `endpoint`, oldest first; draining them.
  defp push_requests(endpoint) do
    receive do
      {:push_notification_sent, ^endpoint, payload} -> [payload | push_requests(endpoint)]
    after
      0 -> []
    end
  end

  defp unique_uuid, do: Ecto.UUID.generate()

  # Test-fixture-only raw insert of an active subscription, for the backup
  # fixture, whose rows the backup snapshots directly (U12). Its keys are fresh per call;
  # returns its ID with its endpoint and keys.
  defp create_active_subscription!(user_id) do
    BnestApp.FamilyChat.ensure_ready!()
    p256dh = Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false)
    auth = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    session_digest = :crypto.hash(:sha256, user_id <> "-session") |> Base.encode16(case: :lower)
    endpoint = "https://push.allowed.example.com/" <> user_id
    endpoint_sha256 = :crypto.hash(:sha256, endpoint) |> Base.encode16(case: :lower)
    actor = "user:" <> user_id

    SqliteRepo.query!(
      """
      INSERT INTO web_push_subscriptions (
        user_id, session_digest, endpoint_sha256, endpoint, p256dh, auth_secret,
        expiration_time, created_at, created_by, updated_at, updated_by
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
      """,
      [
        user_id,
        session_digest,
        endpoint_sha256,
        endpoint,
        p256dh,
        auth,
        now,
        actor,
        now,
        actor
      ]
    )

    # See the unit driver's identical clause: `last_insert_rowid()` is
    # connection-local, so this looks the row up by its own unique key
    # instead of trusting a second, separately-pooled `query!` call.
    %{rows: [[subscription_id]]} =
      SqliteRepo.query!("SELECT id FROM web_push_subscriptions WHERE endpoint_sha256 = ?", [
        endpoint_sha256
      ])

    %{id: subscription_id, endpoint: endpoint, p256dh: p256dh, auth: auth}
  end

  # Retires a fixture-created subscription that was only ever a vehicle for
  # producing some other row (a backup artifact's contents): left active, it
  # would silently inflate a LATER scenario's "every active subscription"
  # fan-out for the rest of this shared test database's run.
  defp disable_subscription_row!(subscription_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    SqliteRepo.query!(
      "UPDATE web_push_subscriptions SET deleted_at = ?, deleted_by = ? WHERE id = ?",
      [
        now,
        "system:test-fixture",
        subscription_id
      ]
    )

    :ok
  end

  # Same purpose as `disable_subscription_row!/1`, keyed by user id instead
  # of subscription row id -- for fixtures (like
  # `:three_members_with_subscriptions`) that only ever recorded who they
  # subscribed, not the row ids `create_active_subscription!/1` returned.
  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical helper.
  defp disable_subscriptions_for_users!(user_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Enum.each(user_ids, fn user_id ->
      SqliteRepo.query!(
        "UPDATE web_push_subscriptions SET deleted_at = ?, deleted_by = ? WHERE user_id = ? AND deleted_at IS NULL",
        [now, "system:test-fixture", user_id]
      )
    end)

    :ok
  end

  # Sends one mutation field over HTTP as the logged-in member, its arguments filled by
  # name. A field that needs an argument no value names cannot run, and is reported so.
  defp run_public_mutation(context, field) do
    values = %{
      "roomSlug" => BnestApp.FamilyChat.canonical_room_slug(),
      "clientMessageId" => unique_uuid(),
      "body" => "public schema probe",
      "endpoint" => synthetic_endpoint("schema-" <> unique_uuid()),
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    with {:ok, document, variables} <- PublicMutationProbe.invocation(field, values),
         %{"data" => data} = result when not is_map_key(result, "errors") <-
           graphql(context, document, variables).family_chat_result,
         %{} <- data[field.name] do
      {field.name, :ran}
    else
      other -> {field.name, {:failed, other}}
    end
  end

  # A commit whose delivery rows SQLite refuses (a trigger on the scenario's own database,
  # dropped again at once) raises, and leaves neither its message nor a delivery behind.
  defp failed_commit_left_nothing?(context) do
    if Application.fetch_env!(:bnest_app, SqliteRepo)[:database] !=
         context.family_chat_push_database do
      raise "refusing to add a trigger outside the scenario's isolated database"
    end

    deliveries_before = delivery_row_count()
    client_message_id = unique_uuid()

    SqliteRepo.query!("""
    CREATE TRIGGER test_refuse_delivery_rows BEFORE INSERT ON family_chat_push_deliveries
    BEGIN SELECT RAISE(ABORT, 'delivery rows refused'); END
    """)

    refused? =
      try do
        match?(
          {:error, _reason},
          BnestApp.FamilyChat.send_message(
            context.user_id,
            context.family_chat_room_slug,
            client_message_id,
            "Dinner is ready, again"
          )
        )
      rescue
        _refused -> true
      after
        SqliteRepo.query!("DROP TRIGGER IF EXISTS test_refuse_delivery_rows")
      end

    refused? and count_messages_for(context, client_message_id) == 0 and
      delivery_row_count() == deliveries_before
  end

  defp delivery_row_count do
    %{rows: [[count]]} = SqliteRepo.query!("SELECT COUNT(*) FROM family_chat_push_deliveries")
    count
  end

  # Every topic the application's Absinthe subscription relays a publish through.
  defp absinthe_proxy_topics do
    {:ok, pool_size} =
      BnestAppWeb.Endpoint
      |> Absinthe.Subscription.registry_name()
      |> Registry.meta(:pool_size)

    for shard <- 0..(pool_size - 1), do: SubscriptionProxy.topic(shard)
  end

  # Every configuration `tools/caddy-config.mjs` generates, generated by Node from the very
  # module the deployment tool imports: `slot`, `port`, `healthChecked` and `config` each.
  defp generated_caddyfiles do
    script = """
    const { caddyfile, slots } = await import(process.argv[1]);
    const configs = [];
    for (const [slot, port] of Object.entries(slots))
      for (const healthChecked of [true, false])
        configs.push({ slot, port, healthChecked, config: caddyfile(slot, healthChecked) });
    process.stdout.write(JSON.stringify(configs));
    """

    {output, 0} =
      System.cmd("node", [
        "--input-type=module",
        "-e",
        script,
        URI.to_string(%URI{scheme: "file", path: @caddy_config_tool})
      ])

    Jason.decode!(output)
  end

  # The directives of a configuration's leading global options block, trimmed.
  defp global_options("{\n" <> rest) do
    [block | _sites] = String.split(rest, "\n}\n", parts: 2)
    block |> String.split("\n") |> Enum.map(&String.trim/1)
  end

  defp global_options(_no_global_block), do: []

  # The upstreams of every `reverse_proxy` directive in a configuration.
  defp reverse_proxy_upstreams(config) do
    for [_line, upstreams] <- Regex.scan(~r/^\s*reverse_proxy\s+([^{\n]*?)\s*\{?\s*$/m, config),
        do: String.split(upstreams)
  end
end
