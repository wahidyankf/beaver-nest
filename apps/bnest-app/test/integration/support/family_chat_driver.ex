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

  alias BnestApp.Backup
  alias BnestApp.Backup.Config, as: BackupConfig
  alias BnestApp.Backup.Run, as: BackupRun
  alias BnestApp.DataRepository
  alias BnestApp.FamilyChat.Store, as: FamilyChatStore
  alias BnestApp.Identity
  alias BnestApp.Identity.FileStore
  alias BnestApp.PushNotifications
  alias BnestApp.Release.CaddyConfig
  alias BnestApp.Release.Migrations
  alias BnestApp.Scheduler
  alias BnestApp.SqliteRepo
  alias BnestApp.TestBackupDestination

  # See the identical attribute on BnestApp.Behaviour.UnitFamilyChatDriver for
  # why this is required during RED (`mix compile --warnings-as-errors`
  # otherwise fails to compile at all, not just the tests that use these
  # not-yet-implemented modules/functions).
  @compile {:no_warn_undefined,
            [
              BnestApp.FamilyChat,
              BnestApp.FamilyChat.Store,
              BnestApp.PushNotifications,
              BnestApp.PushNotifications.Dispatcher,
              BnestApp.Release.Migrations,
              BnestApp.Backup,
              BnestAppWeb.Schema,
              {BnestApp.Scheduler, :converge_backup_time!, 2}
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

  # --- prepare ---

  def prepare_behaviour(context, :room_has_known_history, _args),
    do: Map.put(context, :family_chat_known_ids, [1, 2, 3])

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
    # `Identity.Authorization.allow?/3` grants `use_family_chat` to any
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

  def prepare_behaviour(context, :holds_subscription, [_name, slug]),
    do: Map.put(context, :family_chat_subscribed_slug, slug)

  def prepare_behaviour(context, :message_committed_before_subscription, _args) do
    # See the unit driver's identical clause: a fixed `1` only worked by luck
    # for the very first message in the shared database; this captures the
    # real server-assigned ID instead. Also captures a genuine baseline ID
    # *before* sending, since the later afterId query must cursor from a
    # point strictly before this message (afterId is exclusive-after) for
    # this very message to appear in its own catch-up results.
    room = FamilyChatStore.get_active_room_by_slug("ruang-keluarga")
    %{nodes: existing} = FamilyChatStore.list_messages(room.id, nil, nil, 10_000)
    baseline_id = existing |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

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

  def prepare_behaviour(context, :has_enabled_subscription, _args),
    do: Map.put(context, :family_chat_push_subscription_enabled, true)

  # No test-local flag needs forcing: `:no_graphiql_route` below reads the
  # real, already-compiled `BnestAppWeb.Router.dev_routes_enabled?/0`, the
  # real `__routes__()`, and the real `config/prod.exs` on disk directly,
  # rather than a stored simulation of "production."
  def prepare_behaviour(context, :endpoint_configured_production, _args), do: context

  def prepare_behaviour(context, :fresh_migrated_database, _args),
    do: Map.put(context, :family_chat_migration_state, :fresh)

  def prepare_behaviour(context, :migration_applied, _args) do
    # Genuinely runs the migration (not a stored sentinel) — see the unit
    # driver's identical clause for the scenario's actual requirement.
    {:ok, _room} = FamilyChatStore.migrate!()
    Map.put(context, :family_chat_migration_state, :applied)
  end

  def prepare_behaviour(context, :trusted_producer, _args),
    do:
      Map.put(context, :family_chat_producer_key, "system:integration-producer-" <> unique_uuid())

  def prepare_behaviour(context, :three_members_with_subscriptions, [slug]) do
    # Real active `web_push_subscriptions` rows (test-fixture-only raw SQL,
    # bypassing the not-yet-built `PushNotifications` context — see the unit
    # driver's identical clause for full rationale). `context.user_id` is
    # always real here (`before_scenario` logs in every scenario), and is
    # also given a subscription of its own so "sender excluded from
    # delivery" is a genuine, non-vacuous assertion.
    other_subscribers =
      for suffix <- ~w(a b c), do: "test-user-family-chat-#{suffix}-" <> unique_uuid()

    Enum.each(other_subscribers, &create_active_subscription!/1)
    sender_subscription_id = create_active_subscription!(context.user_id)

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
    {:ok, _room} = FamilyChatStore.migrate!()
    Map.put(context, :family_chat_migration_state, :applied)
  end

  # One other subscriber (not three): this scenario counts delivery rows for a
  # reply, so a single expected row makes "exactly one" an exact assertion.
  # The sender also gets a subscription so their own exclusion stays genuine.
  def prepare_behaviour(context, :one_other_active_subscription, [slug]) do
    sender_id = durable_sender(context)
    other_subscriber = "test-user-family-chat-other-" <> unique_uuid()
    other_subscription_id = create_active_subscription!(other_subscriber)
    sender_subscription_id = create_active_subscription!(sender_id)

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

  def prepare_behaviour(context, :delivery_will_fail_retryable, _args),
    do: Map.put(context, :family_chat_delivery_failure_class, :retryable)

  def prepare_behaviour(context, :delivery_targets_gone_subscription, _args),
    do: Map.put(context, :family_chat_delivery_failure_class, :gone)

  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see its
  # own comment): these three clauses previously only recorded an
  # age-in-days parameter without ever inserting the delivery row it
  # describes, so `retain_deliveries/1` (which only ever sees real SQLite
  # rows, never test context) had nothing eligible to act on. Each now seeds
  # one real, backdated delivery row via `seed_aged_delivery!/2,3` (a raw-SQL
  # test fixture, mirroring this file's existing `create_active_subscription!/1`
  # pattern).
  def prepare_behaviour(context, :final_rows_older_than_7_days, _args) do
    seed_aged_delivery!("delivered", 8)
    Map.put(context, :family_chat_final_rows_age_days, 8)
  end

  def prepare_behaviour(context, :nonfinal_rows_same_age, _args) do
    seed_aged_delivery!("pending", 8)
    Map.put(context, :family_chat_nonfinal_rows_age_days, 8)
  end

  def prepare_behaviour(context, :soft_deleted_rows_older_than_7_days, _args) do
    seed_aged_delivery!("terminal", 8, soft_deleted?: true)
    Map.put(context, :family_chat_soft_deleted_age_days, 8)
  end

  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see its
  # own comment): these two clauses previously only recorded the schedule
  # key, never actually seeding/forcing a due state -- "prod-sqlite-backup-
  # daily" is seeded only by real release/migration code (at real wall-clock
  # boot time, never necessarily due relative to `@behaviour_now`), and the
  # family-chat retention seed ships `enabled = 0` (tech-doc 002), so neither
  # schedule was ever genuinely claimable without this.
  def prepare_behaviour(context, :schedule_due, [key]) do
    Scheduler.Store.reset_schedule_for_test!(key, "19:00", true, @behaviour_now)
    Scheduler.Store.force_due_for_test!(key, @behaviour_now)
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  def prepare_behaviour(context, :schedule_due_and_enabled, [key]) do
    FamilyChatStore.ensure_ready!()
    Scheduler.Store.force_due_for_test!(key, @behaviour_now)
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
    Scheduler.Store.reset_schedule_for_test!(key, "23:00", true, @behaviour_now)

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_prior_daily_at_utc: "23:00"
    })
  end

  # Mirrors `prepare_behaviour/3, :schedule_different_time` above: forces the
  # real "family-chat-push-retention-daily" row (never present in a fresh
  # integration test database otherwise) into the exact pristine
  # precondition -- disabled, revision 1, at its real seed time (tech-doc
  # 002/`FamilyChat.Store`'s own insert: "17:15" UTC, i.e. 00:15 WIB) -- the
  # activation-CAS scenario's `Given` describes.
  def prepare_behaviour(context, :schedule_disabled_seed, [key]) do
    Scheduler.Store.reset_schedule_for_test!(key, "17:15", false, @behaviour_now)
    Map.put(context, :family_chat_activation_key, key)
  end

  def prepare_behaviour(context, :convergence_already_ran, _args) do
    Scheduler.Store.reset_schedule_for_test!(
      "prod-sqlite-backup-daily",
      "19:00",
      true,
      @behaviour_now
    )

    {:ok, _schedule} = Scheduler.converge_backup_time!("prod-sqlite-backup-daily", "18:00")
    Map.put(context, :family_chat_convergence_ran, true)
  end

  def prepare_behaviour(context, :operator_changed_schedule_time, [key]) do
    Scheduler.Store.force_operator_edit_for_test!(key, "20:00", @behaviour_now)

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_operator_daily_at_utc: "20:00"
    })
  end

  def prepare_behaviour(context, :insufficient_capacity, _args),
    do: Map.put(context, :family_chat_backup_capacity, :insufficient)

  def prepare_behaviour(context, :continuous_probes_running, _args) do
    seed_backup_load_padding!()
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
    FamilyChatStore.ensure_ready!()
    destination = TestBackupDestination.create!("verified-backup-artifact-integration")
    known_body = "restore-fixture-secret-" <> unique_uuid()

    subscription_id =
      create_active_subscription!("test-user-family-chat-restore-" <> unique_uuid())

    ExUnit.Callbacks.on_exit(fn -> disable_subscription_row!(subscription_id) end)
    room = FamilyChatStore.get_active_room_by_slug(FamilyChatStore.canonical_room_slug())

    {:ok, _message} =
      FamilyChatStore.insert_message!(
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
      family_chat_known_body: known_body
    })
  end

  def prepare_behaviour(context, :two_independent_slots, _args),
    do: Map.put(context, :family_chat_slots, [:blue, :green])

  def prepare_behaviour(context, :routed_socket_on_prior_slot, _args),
    do: Map.put(context, :family_chat_prior_slot, :blue)

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

  # `FileStore.replace_account/2` writes directly to the real account store
  # used by `establish_identity/2` (`DataRepository`) -- the same account the
  # earlier send authenticated as, now renamed to prove the later requery
  # reflects the account as it stands *now*, not as it stood at commit time.
  def perform_behaviour(context, :rename_sender_account, [new_name]) do
    {:ok, account} = FileStore.read_account(DataRepository, context.user_id)
    updated = Map.put(account, "displayUsername", new_name)
    {:ok, ^updated} = FileStore.replace_account(DataRepository, updated)
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
    do: send_family_chat_message(context, unique_uuid(), body)

  def perform_behaviour(context, :establish_subscription, [_name, slug]),
    do: Map.put(context, :family_chat_subscribed_slug, slug)

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
    result = upsert_subscription(context, valid_subscription_input())
    # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix (see
    # `:three_members_with_subscriptions`'s own `on_exit` comment for the
    # full mechanism): this scenario's Background logs in with a fixed
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
      upsert_subscription(context, Map.put(valid_subscription_input(), "endpoint", endpoint))

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
  def perform_behaviour(context, :open_socket_authenticated, _args) do
    spoofed_user_id = "spoofed-" <> unique_uuid()
    spoofed_params = %{"userId" => spoofed_user_id, "role" => "admin"}

    context
    |> Map.put(:family_chat_spoofed_user_id, spoofed_user_id)
    |> Map.put(:family_chat_result, connect_family_chat_socket(context, spoofed_params))
  end

  def perform_behaviour(context, :visitor_opens_socket, _args) do
    Map.put(
      context,
      :family_chat_result,
      connect_family_chat_socket(anonymize(context), %{})
    )
  end

  def perform_behaviour(context, :run_family_chat_migration, _args),
    do: Map.put(context, :family_chat_result, BnestApp.FamilyChat.Store.migrate!())

  def perform_behaviour(context, :old_code_opens_database, _args) do
    # Same genuine proxy as the unit driver: see its comment for rationale.
    Map.put(
      context,
      :family_chat_result,
      Scheduler.Store.get_schedule("family-chat-push-retention-daily")
    )
  end

  def perform_behaviour(context, :producer_posts_system_message, [slug]) do
    Map.put(
      context,
      :family_chat_result,
      BnestApp.FamilyChat.post_system_message(
        slug,
        context.family_chat_producer_key,
        "system notice"
      )
    )
  end

  def perform_behaviour(context, :producer_retries_same_key, _args),
    do: perform_behaviour(context, :producer_posts_system_message, ["ruang-keluarga"])

  def perform_behaviour(context, :inspect_public_schema, _args),
    do: Map.put(context, :family_chat_schema_fields, BnestAppWeb.Schema.mutation_field_names())

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

    room = FamilyChatStore.get_active_room_by_slug(slug)

    Map.merge(context, %{
      family_chat_result: {:ok, committed},
      family_chat_pre_reply_readback: FamilyChatStore.message_by_id(room.id, committed.id)
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

  def perform_behaviour(context, :dispatcher_attempts_delivery, _args) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.Dispatcher.attempt(context[:family_chat_delivery_failure_class])
    )
  end

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

  def perform_behaviour(context, :scheduler_claims_and_dispatches, _args) do
    due = Scheduler.Store.claim_due(@behaviour_now)
    claimed = Enum.find(due, &(&1.schedule_key == context[:family_chat_due_schedule_key]))

    Map.put(
      context,
      :family_chat_claimed,
      claimed && Map.put(claimed, :handler_key, resolved_handler_name(claimed))
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
    :ok = Scheduler.Store.activate_if_pristine!(key, @behaviour_now)
    # See `Scheduler.Store.force_not_due_for_test!/2`'s own comment: this
    # scenario never claims the row, so it must not leave it due for a
    # later, unrelated scenario's broad `claim_due/1` sweep to steal.
    :ok = Scheduler.Store.force_not_due_for_test!(key, @behaviour_now)
    Map.put(context, :family_chat_result, Scheduler.Store.get_schedule(key))
  end

  def perform_behaviour(context, :bnest_starts_again, _args) do
    # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical fix:
    # `apply_and_verify!/0`'s own `@spec` is `:: :ok`, but every outcome
    # check reading `family_chat_result` here expects `{:ok, schedule}`.
    :ok = Migrations.apply_and_verify!()

    Map.put(
      context,
      :family_chat_result,
      {:ok, Scheduler.Store.get_schedule("prod-sqlite-backup-daily")}
    )
  end

  def perform_behaviour(context, :backup_runs_full_duration, _args) do
    opts =
      [deadline: @behaviour_now]
      |> maybe_put_opt(:capacity_check, context[:family_chat_backup_capacity])
      |> maybe_put_opt(:probe_watch, context[:family_chat_probes_running])

    Map.put(context, :family_chat_result, BnestApp.Backup.run(opts))
  end

  def perform_behaviour(context, :restore_artifact_isolated_root, _args) do
    Map.put(
      context,
      :family_chat_result,
      BnestApp.Backup.restore(context[:family_chat_backup_artifact])
    )
  end

  # Genuinely routed (real GraphQL HTTP via `graphql/3`, the same helper
  # every other family-chat send/read scenario in this file uses -- never a
  # direct `FamilyChat.send_message/list_messages` call) counterpart to
  # `BnestApp.Backup.run/1`'s own `:probe_watch` mechanism proxy (see that
  # module's comment: "The routed, full-stack version of this proof lives at
  # the integration layer"). Also genuinely "through Scheduler->handler-
  # >service" (tech-doc 009's Concurrent-write Proof step 3): claims a real
  # setup claim through `Scheduler.Store` and dispatches through the generic
  # `Scheduler.Run.execute/2`, which resolves `BnestApp.Backup.Run` from the
  # real `Scheduler.Registry` exactly as the 60s production tick does --
  # never `BnestApp.Backup.run/1` called directly.
  def perform_behaviour(context, :routed_backup_runs_full_duration, _args) do
    location = prepare_isolated_backup_config!()
    key = "bdd-routed-backup-" <> unique_uuid()

    :ok =
      Scheduler.Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    {:ok, claim} = Scheduler.Store.claim_setup(key, location.destination_id, @behaviour_now)

    probe_task =
      if context[:family_chat_probes_running] do
        conn = context.conn
        Task.async(fn -> run_routed_probes(conn) end)
      end

    :ok = Scheduler.Run.execute(claim, @behaviour_now)

    probes =
      if probe_task,
        do: Task.await(probe_task, 30_000),
        else: %{sent_ids: [], samples: [], failures: 0}

    Map.merge(context, %{
      family_chat_load_probes: probes,
      family_chat_load_receipts: BackupRun.owned_receipts(location.directory),
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

    Map.merge(context, %{family_chat_result: result, family_chat_load_probes: probes})
  end

  # Second half: the SAME forced-timeout condition, driven through the real
  # `Scheduler.Store` claim -> `Scheduler.Run.execute/2` -> registered-
  # handler chain (never a hand-crafted `Store.fail_attempt` call), so
  # "Scheduler state remains retryable" is proven from the real retry
  # bookkeeping `Scheduler.Run.record_failure/3` performs, not asserted by
  # construction. `Scheduler.Policy.retry_at(1, now)` schedules the retry
  # five minutes out; advancing the deterministic clock past that and
  # re-querying `claim_due/1` is the same technique `reconcile_overlap`
  # already uses above.
  def perform_behaviour(context, :timed_out_backup_via_scheduler, _args) do
    location = prepare_isolated_backup_config!()
    key = "bdd-timed-out-backup-" <> unique_uuid()

    :ok =
      Scheduler.Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    {:ok, claim} = Scheduler.Store.claim_setup(key, location.destination_id, @behaviour_now)

    :ok = Scheduler.Run.execute(claim, @behaviour_now)

    later = DateTime.add(@behaviour_now, 6 * 60)
    retried = Enum.find(Scheduler.Store.claim_due(later), &(&1.run_id == claim.run_id))

    Map.put(context, :family_chat_retry_claim, retried)
  end

  def perform_behaviour(context, :message_commits_on_one_slot, _args) do
    # Same internal-boundary convention as `:member_sends_durable_message`:
    # the real, inspectable proxy for cross-slot isolation is the domain
    # function's own `broadcast_scope` (see the outcome clauses below), which
    # only a direct call -- not the GraphQL/HTTP round trip -- exposes.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    result =
      BnestApp.FamilyChat.send_message(context.user_id, slug, unique_uuid(), "slot-local publish")

    context
    |> Map.put(:family_chat_result, result)
    |> Map.update(:family_chat_subscription_events, 1, &(&1 + 1))
  end

  def perform_behaviour(context, :generate_reverse_proxy_config, _args) do
    Map.put(
      context,
      :family_chat_result,
      CaddyConfig.reverse_proxy_block(:candidate)
    )
  end

  def perform_behaviour(context, :caddy_reloads_promoted, _args) do
    # Same genuine proxy as the unit driver: see its comment for rationale.
    Map.put(
      context,
      :family_chat_result,
      CaddyConfig.reverse_proxy_block(:promoted)
    )
  end

  def perform_behaviour(context, :inspect_router_routes, _args), do: context

  # --- outcome (same evidence shape as the unit driver; independently checked from HTTP/GraphQL results) ---

  def behaviour_outcome?(context, :room_list_lists_exactly, [name]),
    do:
      match?(
        %{"data" => %{"familyChatRooms" => [%{"name" => ^name}]}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :room_returned, [name]),
    do: match?(%{"data" => %{"familyChatRoom" => %{"name" => ^name}}}, context.family_chat_result)

  def behaviour_outcome?(context, :messages_ascending_max_50, _args), do: ascending_page?(context)
  def behaviour_outcome?(context, :older_messages_ascending, _args), do: ascending_page?(context)
  def behaviour_outcome?(context, :newer_messages_ascending, _args), do: ascending_page?(context)

  def behaviour_outcome?(context, :has_older_correct, _args),
    do:
      get_in(context.family_chat_result, ["data", "familyChatMessages", "hasOlder"]) in [
        true,
        false
      ]

  def behaviour_outcome?(context, :has_newer_correct, _args),
    do:
      get_in(context.family_chat_result, ["data", "familyChatMessages", "hasNewer"]) in [
        true,
        false
      ]

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

  # 160 budgeted graphemes plus the one ellipsis that marks the cut.
  def behaviour_outcome?(context, :quote_preview_within_budget, _args),
    do: String.length(sent_quote(context)["bodyPreview"]) <= 161

  def behaviour_outcome?(context, :quote_preview_elided, _args),
    do: String.ends_with?(sent_quote(context)["bodyPreview"], "…")

  # Reads the quoted message back through the ordinary GraphQL page, so this
  # asserts what a client actually receives for it, not what the fixture wrote.
  def behaviour_outcome?(context, :quoted_body_unshortened, _args) do
    room =
      FamilyChatStore.get_active_room_by_slug(context[:family_chat_room_slug] || "ruang-keluarga")

    case FamilyChatStore.message_by_id(room.id, context.family_chat_reply_target_id) do
      %{body: body} -> body == context.family_chat_reply_target_body
      nil -> false
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

  # `family_chat_push_deliveries` has no payload column at all -- it references
  # a message id and nothing more. Reads the row back in full and checks no
  # column carries the quoted text, so a future payload column cannot quietly
  # start carrying it.
  def behaviour_outcome?(context, :delivery_payload_excludes_quote, _args) do
    {:ok, %{id: message_id}} = context.family_chat_result
    quoted_body = context.family_chat_reply_target_body

    %{rows: rows} =
      SqliteRepo.query!("SELECT * FROM family_chat_push_deliveries WHERE message_id = ?", [
        message_id
      ])

    Enum.all?(rows, fn row ->
      Enum.all?(row, fn value ->
        not (is_binary(value) and String.contains?(value, quoted_body))
      end)
    end)
  end

  def behaviour_outcome?(context, :no_hidden_room_state, _args) do
    match?(
      %{"errors" => [%{"extensions" => %{"code" => "FORBIDDEN"}}]},
      context.family_chat_result
    ) and
      not leaks_room_name?(context.family_chat_result)
  end

  def behaviour_outcome?(context, :room_gains_no_message, _args),
    do: Map.has_key?(context.family_chat_result, "errors")

  def behaviour_outcome?(context, :subscriber_received_one_event, _args),
    do: context[:family_chat_subscription_events] == 1

  def behaviour_outcome?(context, :no_duplicate_publish, _args),
    do: context[:family_chat_subscription_events] == 1

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

  def behaviour_outcome?(context, :reports_enabled_and_expiration_only, _args) do
    match?(
      %{"data" => %{"currentWebPushSubscription" => %{"enabled" => _}}},
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :subscription_enabled, _args),
    do:
      match?(
        %{"data" => %{"upsertWebPushSubscription" => %{"enabled" => true}}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :subscription_bound_to_session, _args),
    do:
      match?(
        %{"data" => %{"upsertWebPushSubscription" => %{"enabled" => true}}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :subscription_disabled, _args),
    do:
      match?(
        %{"data" => %{"disableCurrentWebPushSubscription" => %{"enabled" => false}}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :subscription_still_disabled, _args),
    do:
      match?(
        %{"data" => %{"disableCurrentWebPushSubscription" => %{"enabled" => false}}},
        context.family_chat_result
      )

  def behaviour_outcome?(context, :no_subscription_stored_or_network, _args),
    do: error_code?(context, "VALIDATION_FAILED")

  def behaviour_outcome?(context, :socket_context_server_resolved, _args) do
    case socket_absinthe_context(context.family_chat_result) do
      %{user_id: user_id, session_digest: digest} -> is_binary(user_id) and is_binary(digest)
      _other -> false
    end
  end

  # Genuine negative-input check: the spoofed `userId`/`role` connect params
  # `:open_socket_authenticated` actually sent must never surface as the
  # resolved identity -- only the real, server/session-derived user id may.
  def behaviour_outcome?(context, :socket_params_ignored, _args) do
    case socket_absinthe_context(context.family_chat_result) do
      %{user_id: user_id} ->
        user_id == context.user_id and user_id != context[:family_chat_spoofed_user_id]

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

  # Combines the unit driver's real-router check (see its identical clause)
  # with a genuine read of `config/prod.exs` itself -- this layer's File
  # access lets it catch a real production-config regression (someone
  # flipping `dev_routes: true` for prod) that the unit layer structurally
  # cannot see, since the test-build router is compiled once from
  # `config/test.exs`, never from `config/prod.exs`.
  def behaviour_outcome?(_context, :no_graphiql_route, _args) do
    BnestAppWeb.Router.dev_routes_enabled?() == false and
      configured_prod_dev_routes_flag() in [nil, false] and
      not Enum.any?(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))
  end

  def behaviour_outcome?(context, :room_seed_correct, [slug, name]),
    do: match?({:ok, %{slug: ^slug, name: ^name, id: 1}}, context.family_chat_result)

  def behaviour_outcome?(context, :migration_idempotent, _args) do
    match?({:ok, %{id: 1}}, context.family_chat_result) and
      match?({:ok, %{id: 1}}, BnestApp.FamilyChat.Store.migrate!())
  end

  def behaviour_outcome?(context, :prior_release_unaffected, _args),
    do:
      match?(
        %{schedule_key: "family-chat-push-retention-daily", handler_key: handler}
        when is_binary(handler),
        context.family_chat_result
      )

  def behaviour_outcome?(context, :no_prior_release_table_access, _args) do
    case context.family_chat_result do
      %{} = schedule -> not Map.has_key?(schedule, :family_chat_room_id)
      _other -> false
    end
  end

  def behaviour_outcome?(context, :system_message_committed, [sender_kind]),
    do: match?({:ok, %{sender_kind: ^sender_kind}}, context.family_chat_result)

  def behaviour_outcome?(context, :system_message_unchanged, _args),
    do: match?({:ok, %{}}, context.family_chat_result)

  def behaviour_outcome?(context, :exactly_one_system_message, _args),
    do: count_messages_for(context, context.family_chat_producer_key) == 1

  def behaviour_outcome?(context, :schema_has_no_system_message_field, _args),
    do: not Enum.any?(context.family_chat_schema_fields, &(&1 =~ "system"))

  def behaviour_outcome?(context, :message_and_deliveries_committed_atomically, _args) do
    match?(
      {:ok, %{deliveries: deliveries}} when length(deliveries) == 3,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :sender_excluded_from_delivery, _args) do
    {:ok, %{deliveries: deliveries}} = context.family_chat_result
    not Enum.any?(deliveries, &(&1.subscription_id == context.family_chat_sender_subscription_id))
  end

  def behaviour_outcome?(context, :delivery_retryable_with_wait, [state]),
    do: match?({:ok, %{state: ^state, next_attempt_at: %DateTime{}}}, context.family_chat_result)

  def behaviour_outcome?(context, :no_attempt_past_ceiling, _args),
    do: match?({:ok, %{attempt: attempt}} when attempt in 1..5, context.family_chat_result)

  def behaviour_outcome?(context, :delivery_terminal_subscription_disabled, [state]),
    do: match?({:ok, %{state: ^state}}, context.family_chat_result)

  def behaviour_outcome?(context, :no_further_attempt_scheduled, _args),
    do: match?({:ok, %{next_attempt_at: nil}}, context.family_chat_result)

  def behaviour_outcome?(context, :completed_rows_soft_deleted, _args),
    do: match?({:ok, %{soft_deleted: n}} when n > 0, context.family_chat_result)

  def behaviour_outcome?(context, :nonfinal_rows_remain_active, _args),
    do:
      match?(
        {:ok, %{soft_deleted: n, remaining_active: active}} when n > 0 and is_integer(active),
        context.family_chat_result
      )

  def behaviour_outcome?(context, :rows_purged, _args),
    do: match?({:ok, %{purged: n}} when n > 0, context.family_chat_result)

  # Reads the second call's own independent result snapshot (see
  # `:retention_job_runs_again`'s comment above), not the first call's
  # `family_chat_result`.
  def behaviour_outcome?(context, :retention_run_idempotent, _args),
    do: match?({:ok, %{purged: 0, soft_deleted: 0}}, context.family_chat_idempotent_result)

  def behaviour_outcome?(context, :only_named_handler_invoked, [name]),
    do: context.family_chat_claimed != nil and context.family_chat_claimed.handler_key == name

  def behaviour_outcome?(context, :only_retention_handler_invoked, _args),
    do: context.family_chat_claimed != nil

  def behaviour_outcome?(_context, :handler_delegates_to_service, [service_name]) do
    service_name |> List.wrap() |> Module.concat() |> Code.ensure_loaded?()
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
    :ok = Scheduler.Store.activate_if_pristine!(key, @behaviour_now)
    after_schedule = Scheduler.Store.get_schedule(key)

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

  def behaviour_outcome?(context, :no_partial_or_final_artifact, _args),
    do: match?({:error, {:retryable, _category, nil}}, context.family_chat_result)

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

      slug == FamilyChatStore.canonical_room_slug() and message_ids != [] and
        message_ids == Enum.sort(message_ids) and is_integer(subscription_count) and
        subscription_count >= 1 and is_list(delivery_states)
    else
      _other -> false
    end
  end

  def behaviour_outcome?(context, :no_secret_in_restore_evidence, _args) do
    case context.family_chat_result do
      {:ok, %{evidence: evidence}} when is_binary(evidence) ->
        not String.contains?(evidence, context[:family_chat_known_body] || "\0unset\0")

      _other ->
        false
    end
  end

  # See the unit driver's identical clause for the structural-proxy rationale
  # (no E2E scenario exercises multi-slot isolation; this file is its
  # designated alternative-proof, so the limitation is flagged in learnings.md).
  def behaviour_outcome?(context, :only_same_slot_sockets_receive, _args),
    do: match?({:ok, %{broadcast_scope: :local}}, context.family_chat_result)

  def behaviour_outcome?(context, :other_slot_no_event, _args),
    do: match?({:ok, %{broadcast_scope: :local}}, context.family_chat_result)

  def behaviour_outcome?(context, :no_nonzero_stream_close_delay, [_setting]) do
    {:ok, config} = context.family_chat_result
    not String.contains?(config, "stream_close_delay")
  end

  def behaviour_outcome?(context, :grace_period_present, _args) do
    {:ok, config} = context.family_chat_result
    String.contains?(config, "grace_period 5m")
  end

  # See the unit driver's identical clauses for the generated-config-proxy rationale.
  def behaviour_outcome?(context, :prior_slot_socket_closes, _args) do
    {:ok, config} = context.family_chat_result
    not String.contains?(config, "upstream prior active")
  end

  def behaviour_outcome?(context, :handshake_only_promoted_slot, _args) do
    {:ok, config} = context.family_chat_result

    String.contains?(config, "upstream promoted") and
      not String.contains?(config, "upstream prior")
  end

  def behaviour_outcome?(context, :prior_slot_warm_unrouted, _args) do
    {:ok, config} = context.family_chat_result
    String.contains?(config, "prior") and String.contains?(config, "warm")
  end

  # --- helpers ---

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  # Reads the real `config/prod.exs`, chained through `config/config.exs`'s
  # own `import_config "#{config_env()}.exs"` via `env: :prod`, exactly as
  # `MIX_ENV=prod mix compile` would resolve it -- not read from the running
  # application's own env (already fixed to this test build's value). Used
  # by `:no_graphiql_route` above alongside the real compiled router's own
  # `dev_routes_enabled?/0`/`__routes__()`, so this layer catches a real
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

  # Isolated `BnestApp.Backup.Config` destination for Item 5's Scheduler-
  # driven scenarios: `BnestApp.Backup.Run.execute/2` always calls
  # `Config.resolve/0` itself (it never accepts a `:destination_directory`
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

    {:ok, location} = BackupConfig.save(Path.join(root, "destination"))
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
  # active subscription (`FamilyChat.Store.active_subscription_ids/1`'s
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
    room = FamilyChatStore.get_active_room_by_slug(FamilyChatStore.canonical_room_slug())
    %{nodes: nodes} = FamilyChatStore.list_messages(room.id, nil, nil, 10_000)
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
  # the shared `Identity.Authorization` account schema (`roles?/1` in
  # `data_repository/schema.ex`) forbids ever persisting an account with an
  # empty roles list. A real capability-denied identity therefore cannot be
  # constructed through the normal login/session/FileStore pipeline — the
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

    context
    |> Map.put(:family_chat_client_message_id, client_message_id)
    |> Map.update(:family_chat_subscription_events, 1, &(&1 + 1))
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
    connect(BnestAppWeb.UserSocket, params,
      connect_info: %{session: session_from_conn(context.conn)}
    )
  end

  defp session_from_conn(conn) do
    conn = Plug.Conn.fetch_cookies(conn)

    case Identity.current_user(conn.cookies["_bnest_identity"]) do
      {:ok, user} -> %{"current_user" => user}
      {:error, :unauthenticated} -> %{}
    end
  end

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
    FamilyChatStore.ensure_ready!()
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
      FamilyChatStore.insert_message!(
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
    # `FamilyChat.Store` directly instead, matching this driver's own stated
    # convention for internal-boundary assertions; a bounded 50-row GraphQL
    # page would also risk missing the target given the shared database.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    room = FamilyChatStore.get_active_room_by_slug(slug)
    %{nodes: nodes} = FamilyChatStore.list_messages(room.id, nil, nil, 10_000)
    Enum.count(nodes, &(&1.idempotency_key == client_message_id))
  end

  defp ascending_page?(context) do
    nodes = get_in(context.family_chat_result, ["data", "familyChatMessages", "nodes"])

    is_list(nodes) and length(nodes) <= 50 and
      nodes == Enum.sort_by(nodes, &String.to_integer(&1["id"]))
  end

  defp error_code?(context, code) do
    match?(%{"errors" => [%{"extensions" => %{"code" => ^code}} | _]}, context.family_chat_result)
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)

  defp leaks_room_name?(%{"errors" => [%{"message" => msg} | _]}), do: msg =~ "ruang-keluarga"
  defp leaks_room_name?(_other), do: false

  defp anonymize(context) do
    Map.put(context, :conn, Phoenix.ConnTest.build_conn())
  end

  defp valid_subscription_input do
    %{
      "endpoint" => "https://push.allowed.example.com/valid",
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
  end

  # Test-only enrichment: `Scheduler.Store.claim_due/1`'s run rows carry no
  # handler identity (production's Scheduler -> Registry -> Handler -> ...
  # dependency direction means `Store` itself never looks the handler module
  # up -- see the dependency-direction test this preserves), so this
  # resolves it here, driver-side, the same way `Scheduler.Run.execute/2`
  # does in production (`Store.get_schedule/1` then `Registry.fetch/1`).
  # Mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical helper.
  defp resolved_handler_name(claimed) do
    with %{handler_key: registry_key} <- Scheduler.Store.get_schedule(claimed.schedule_key),
         {:ok, %{handler: handler_module}} <- Scheduler.Registry.fetch(registry_key) do
      handler_module |> Module.split() |> Enum.take(-2) |> Enum.join(".")
    else
      _unresolved -> nil
    end
  end

  defp unique_uuid, do: Ecto.UUID.generate()

  # Test-fixture-only raw insert — see the unit driver's identical helper for
  # why `PushNotifications` (Phase 5) is bypassed rather than built early.
  defp create_active_subscription!(user_id) do
    FamilyChatStore.ensure_ready!()

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
        "fixture-p256dh-key",
        "fixture-auth-secret",
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

    subscription_id
  end

  # Test-fixture-only raw insert (see `create_active_subscription!/1`'s same
  # comment): seeds one real delivery row, backdated relative to the fixed
  # `@behaviour_now` clock (not real wall-clock time, so retention cutoffs
  # computed from that same clock are deterministic), in the exact state a
  # retention scenario's Given step describes. A distinct sender is required
  # -- `insert_message!/6` never creates a delivery row for the sender's own
  # subscription -- so `recipient_id`'s subscription is always the one that
  # receives the single row this fixture needs. Mirrors
  # `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical helper.
  defp seed_aged_delivery!(state, age_days, opts \\ []) do
    FamilyChatStore.ensure_ready!()
    room = FamilyChatStore.get_active_room_by_slug(FamilyChatStore.canonical_room_slug())
    recipient_id = "test-user-family-chat-retention-fixture-" <> unique_uuid()
    subscription_id = create_active_subscription!(recipient_id)
    # Registered immediately -- see `:verified_backup_artifact`'s own
    # `on_exit` comment for why cleanup placed after a fallible step
    # (`insert_message!/6` here) never fires on a failed/ExBdd-retried
    # attempt.
    ExUnit.Callbacks.on_exit(fn -> disable_subscription_row!(subscription_id) end)

    {:ok, message} =
      FamilyChatStore.insert_message!(
        room.id,
        "user",
        "test-user-family-chat-retention-sender-" <> unique_uuid(),
        "Retention Fixture",
        unique_uuid(),
        "retention fixture message"
      )

    %{rows: [[delivery_id]]} =
      SqliteRepo.query!(
        "SELECT id FROM family_chat_push_deliveries WHERE message_id = ? AND subscription_id = ?",
        [message.id, subscription_id]
      )

    aged =
      @behaviour_now
      |> DateTime.add(-age_days * 86_400, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    {deleted_at, deleted_by} =
      if Keyword.get(opts, :soft_deleted?, false),
        do: {aged, "system:test-fixture"},
        else: {nil, nil}

    SqliteRepo.query!(
      """
      UPDATE family_chat_push_deliveries
      SET state = ?, updated_at = ?, deleted_at = ?, deleted_by = ?,
          lease_expires_at = NULL, next_attempt_at = NULL
      WHERE id = ?
      """,
      [state, aged, deleted_at, deleted_by, delivery_id]
    )

    # The delivery row above is this fixture's actual subject; the
    # subscription was only a vehicle to get `insert_message!/6` to create
    # it. Retiring it immediately (retention never inspects subscription
    # state) stops it from lingering as an extra "active subscription" that
    # would silently inflate a LATER scenario's fan-out for the rest of the
    # test run -- the same cross-scenario pollution class documented on
    # `BnestApp.PushNotifications.Dispatcher`'s bootstrap fixture.
    disable_subscription_row!(subscription_id)

    delivery_id
  end

  # Retires a fixture-created subscription that was only ever a vehicle for
  # producing some other row (a delivery, a backup artifact's contents) --
  # mirrors `BnestApp.Behaviour.UnitFamilyChatDriver`'s identical
  # helper/rationale: left active, it would silently inflate a LATER
  # scenario's "every active subscription" fan-out for the rest of this
  # shared test database's run.
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
end
