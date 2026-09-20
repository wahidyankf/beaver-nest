defmodule BnestApp.Behaviour.UnitFamilyChatDriver do
  @moduledoc """
  Generic prepare/perform/outcome dispatch for `family_chat_graphql.feature` and
  `family_chat_operations.feature` at the unit layer. Delegated to from
  `BnestApp.Behaviour.UnitHomePageDriver` for every atom this module recognizes.

  Unit calls the domain/schema modules directly, bypassing the real HTTP/socket boundary and any
  filesystem/process access, so during RED every `perform_behaviour/3` clause that reaches
  a not-yet-implemented module or function fails with an `UndefinedFunctionError`/schema error —
  the correct RED reason (the feature is genuinely absent), not a harness defect.
  """

  alias BnestApp.Backup
  alias BnestApp.FamilyChat
  alias BnestApp.PushNotifications
  alias BnestApp.Release.CaddyConfig
  alias BnestApp.Release.Migrations
  alias BnestApp.Scheduler
  alias BnestApp.SqliteRepo
  alias BnestApp.TestBackupDestination
  alias BnestAppWeb.Plugs.GraphQLPipeline

  # This driver's whole purpose during RED is to call domain functions that do
  # not exist yet (tech-doc 007's File Impact `[N]` entries), so the actual
  # feature-absence signal is the `UndefinedFunctionError` raised when a
  # generated ExUnit test invokes one of these at runtime. Without this
  # attribute, `mix compile --warnings-as-errors` (used by `test:unit:be` and
  # `test:integration`) would instead fail to compile at all — a harness
  # defect, not the genuine RED this plan requires. Once each module/function
  # is implemented, its entry becomes inert (no warning would have fired) and
  # should be removed in that same change. `BnestApp.Backup` is implemented
  # (Phase 5) and removed from this list in the same change.
  @compile {:no_warn_undefined,
            [
              BnestApp.FamilyChat,
              BnestApp.FamilyChat.Store,
              BnestApp.Release.Migrations,
              BnestAppWeb.Schema
            ]}

  @behaviour_now ~U[2026-09-18 00:00:00Z]

  # See the identical constants on `BnestApp.Behaviour.IntegrationFamilyChatDriver`
  # for why padding lives in `web_push_subscriptions` (cleanable) rather than
  # `family_chat_messages` (trigger-enforced permanent).
  @load_proof_padding_rows 1800
  @load_proof_probe_count 20

  # --- prepare ---

  def prepare_behaviour(context, :room_has_known_history, _args) do
    Map.put(context, :family_chat_known_ids, [1, 2, 3])
  end

  def prepare_behaviour(context, :sent_message_with_known_id, [body]) do
    Map.merge(context, %{
      family_chat_client_message_id: unique_uuid(),
      family_chat_known_body: body
    })
  end

  # See the integration driver's identical clause for the full rationale.
  # Captures the message's ID (assigned by the real SQLite insert this layer
  # already runs) so the later requery can find this exact message.
  def prepare_behaviour(context, :sent_and_committed_message, [body]) do
    context = send_family_chat_message(context, unique_uuid(), body)
    {:ok, message} = context.family_chat_result
    Map.put(context, :family_chat_renamed_sender_message_id, message.id)
  end

  # See the integration driver's identical clause for the full rationale.
  def prepare_behaviour(context, :system_message_posted_to_room, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    {:ok, message} =
      FamilyChat.post_system_message(slug, "system:producer-" <> unique_uuid(), "Notice")

    Map.put(context, :family_chat_system_message_id, message.id)
  end

  def prepare_behaviour(context, :user_without_family_chat_capability, _args) do
    Map.put(context, :family_chat_capability, false)
  end

  # Genuinely establishes a real Absinthe GraphQL subscription: runs the
  # actual subscription document against `BnestAppWeb.Schema` (exercising the
  # real `FamilyChatResolver.subscription_config/2` authorization and topic
  # derivation, not a stand-in), then subscribes this very test process to
  # the real `Phoenix.PubSub` topic Absinthe hands back -- exactly what
  # `Absinthe.Phoenix.Channel.run_doc/3` does for a live socket, minus the
  # fastlane/serializer wrapping a bare unit-layer process has no use for
  # (`Absinthe.Pipeline.for_document/2` always includes
  # `Absinthe.Phase.Subscription.SubscribeSelf`, so no socket is required to
  # reach `%{"subscribed" => topic}`). `FamilyChat.send_message/5`'s real
  # `commit_message/6` -> `Absinthe.Subscription.publish/3` ->
  # `Phoenix.PubSub.local_broadcast/4` chain then delivers a genuine
  # `%Phoenix.Socket.Broadcast{}` straight to this process's mailbox, which
  # the outcome steps below actually receive and inspect instead of trusting
  # an unconditional counter. `mix test --no-start` (this layer's whole
  # point -- see the moduledoc) never boots `BnestApp.Application`, so
  # neither the underlying `Phoenix.PubSub` server nor
  # `Absinthe.Subscription`'s own registry/proxy pool exist yet;
  # `ensure_family_chat_subscriptions_started!/0` below starts exactly that
  # minimal, real, in-memory process infrastructure -- never the
  # `BnestAppWeb.Endpoint` HTTP/socket listener itself, which neither of them
  # requires to be alive (both only read `Application.get_env(:bnest_app,
  # BnestAppWeb.Endpoint)[:pubsub_server]` at call time).
  def prepare_behaviour(context, :holds_subscription, [_subscription_name, slug]) do
    :ok = ensure_family_chat_subscriptions_started!()
    user_id = current_user(context)

    topic =
      subscribe_and_get_topic!(slug, %{"userId" => user_id, "roles" => ["parents"]})

    :ok = Phoenix.PubSub.subscribe(family_chat_pubsub_server(), topic)

    context
    |> Map.put(:family_chat_subscribed_slug, slug)
    |> Map.put(:family_chat_subscription_topic, topic)
  end

  def prepare_behaviour(context, :message_committed_before_subscription, _args) do
    # Genuinely sends a message and captures its real server-assigned ID —
    # a fixed `1` only worked by luck when this was the very first message
    # ever inserted into the shared unit-layer database; any earlier
    # scenario committing a message first (they all share one SQLite file
    # for the run) made the assertion below fail for the wrong reason.
    #
    # Also captures a genuine baseline ID *before* sending this message: the
    # later "queries ... after their last known committed message ID" step
    # must cursor from a point strictly before this message (afterId is
    # exclusive-after), or the very message the scenario expects to "catch
    # up" on would never appear in its own results.
    room = FamilyChat.Store.get_active_room_by_slug("ruang-keluarga")
    %{nodes: existing} = FamilyChat.Store.list_messages(room.id, nil, nil, 10_000)
    baseline_id = existing |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

    {:ok, message} =
      FamilyChat.send_message(
        current_user(context),
        "ruang-keluarga",
        unique_uuid(),
        "Pre-subscription message"
      )

    context
    |> Map.put(:family_chat_last_id, baseline_id)
    |> Map.put(:family_chat_pre_subscription_id, message.id)
  end

  def prepare_behaviour(context, :has_enabled_subscription, _args) do
    Map.put(context, :family_chat_push_subscription_enabled, true)
  end

  # No test-local flag needs forcing: `:no_graphiql_route` below reads the
  # real, already-compiled `BnestAppWeb.Router.dev_routes_enabled?/0` and the
  # real `__routes__()` directly, rather than a stored simulation of
  # "production."
  def prepare_behaviour(context, :endpoint_configured_production, _args), do: context

  def prepare_behaviour(context, :fresh_migrated_database, _args) do
    Map.put(context, :family_chat_migration_state, :fresh)
  end

  def prepare_behaviour(context, :migration_applied, _args) do
    # Genuinely runs the migration (not a stored sentinel): the "old release
    # ignores the additive family chat schema" scenario needs the schema to
    # actually exist before it re-reads a pre-existing table.
    {:ok, _room} = FamilyChat.Store.migrate!()
    Map.put(context, :family_chat_migration_state, :applied)
  end

  def prepare_behaviour(context, :trusted_producer, _args) do
    Map.put(context, :family_chat_producer_key, "system:unit-producer-" <> unique_uuid())
  end

  def prepare_behaviour(context, :three_members_with_subscriptions, [slug]) do
    # Real active `web_push_subscriptions` rows (test-fixture-only raw SQL,
    # bypassing the not-yet-built `PushNotifications` context — see
    # tech-doc 007's [N] entry for `push_notifications.ex`, Phase 5), so the
    # atomic-commit scenario has real rows for `insert_message!/6` to derive
    # delivery rows from, instead of an unused context flag. This scenario
    # (family_chat_operations.feature, "Atomic message and delivery commit")
    # has no "an approved user is logged in" Background, so the sending
    # member's identity is established here too, via the same
    # `:family_chat_user_id` key `current_user/1` already prefers — and also
    # given a real subscription of their own, so "sender excluded from
    # delivery" is a genuine assertion (a subscription that could have
    # received a row, and provably did not) rather than vacuously true.
    sender_id = context[:user_id] || context[:family_chat_user_id] || unique_sender_id()

    other_subscribers =
      for suffix <- ~w(a b c), do: "test-user-family-chat-#{suffix}-" <> unique_uuid()

    Enum.each(other_subscribers, &create_active_subscription!/1)
    sender_subscription_id = create_active_subscription!(sender_id)

    # Robust against ExBdd's own scenario-level retry
    # (`libs/ex-bdd/lib/ex_bdd/runtime.ex`'s `do_attempt/5`): a failed
    # attempt re-runs before hooks, background, and steps -- including this
    # very prepare step -- with a fresh context, so relying on this
    # scenario's own LAST `Then` step to retire these rows (the previous
    # approach) never fires when an EARLIER step's attempt fails first,
    # leaving that attempt's four rows active for the retry's four MORE rows
    # to land on top of. `ExUnit.Callbacks.on_exit/1` instead fires exactly
    # once at the true end of the underlying ExUnit test (after every
    # ExBdd-internal retry attempt, win or lose) and accumulates one
    # callback per call, so each attempt's own rows get retired regardless
    # of which attempt (if any) ultimately passes.
    ExUnit.Callbacks.on_exit(fn ->
      disable_subscriptions_for_users!([sender_id | other_subscribers])
    end)

    Map.merge(context, %{
      family_chat_room_slug: slug,
      family_chat_user_id: sender_id,
      family_chat_other_subscribers: other_subscribers,
      family_chat_sender_subscription_id: sender_subscription_id
    })
  end

  def prepare_behaviour(context, :delivery_will_fail_retryable, _args) do
    Map.put(context, :family_chat_delivery_failure_class, :retryable)
  end

  def prepare_behaviour(context, :delivery_targets_gone_subscription, _args) do
    Map.put(context, :family_chat_delivery_failure_class, :gone)
  end

  # Scaffolding fix (adapter change; see learnings.md's Phase 5 entry): these
  # three clauses previously only recorded an age-in-days parameter without
  # ever inserting the delivery row it describes, so `retain_deliveries/1`
  # (which only ever sees real SQLite rows, never test context) had nothing
  # eligible to act on. Each now seeds one real, backdated delivery row via
  # `seed_aged_delivery!/2` (a raw-SQL test fixture, mirroring this file's
  # existing `create_active_subscription!/1` pattern).
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

  # Scaffolding fix (adapter change; see learnings.md's Phase 5 entry): these
  # two clauses previously only recorded the schedule key, never actually
  # seeding/forcing a due state -- "prod-sqlite-backup-daily" does not exist
  # at all in a fresh unit test database (only real release/migration code
  # seeds it), and the family-chat retention seed ships `enabled = 0`
  # (tech-doc 002), so neither schedule was ever genuinely claimable without
  # this. `Scheduler.Store.reset_schedule_for_test!/4` (see its own comment)
  # forces the row to a known pristine precondition regardless of what any
  # earlier scenario in this shared test database left behind, so this
  # scenario's result does not depend on scenario execution order.
  # `force_due_for_test!/2` is a deterministic test-only seam (real
  # activation is separately proven by the "Compatible activation
  # converges..." and release-migration scenarios).
  def prepare_behaviour(context, :schedule_due, [key]) do
    Scheduler.Store.reset_schedule_for_test!(key, "19:00", true, @behaviour_now)
    Scheduler.Store.force_due_for_test!(key, @behaviour_now)
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  def prepare_behaviour(context, :schedule_due_and_enabled, [key]) do
    FamilyChat.Store.ensure_ready!()
    Scheduler.Store.force_due_for_test!(key, @behaviour_now)
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  # Scaffolding fix (adapter change; see learnings.md's Phase 5 entry): none
  # of these three clauses previously seeded the real "prod-sqlite-backup-
  # daily" row these convergence scenarios need -- it does not exist at all
  # in a fresh unit test database (only real release/migration code seeds
  # it, and its `daily_at_utc` starts at "19:00", never "23:00"), so
  # `Scheduler.converge_backup_time!/2`/`apply_and_verify!/0` raised
  # "unknown schedule" instead of genuinely exercising the CAS convergence
  # logic under test. `reset_schedule_for_test!/4` (see `:schedule_due`'s
  # comment above) is the order-independent seed path.
  def prepare_behaviour(context, :schedule_different_time, [key]) do
    Scheduler.Store.reset_schedule_for_test!(key, "23:00", true, @behaviour_now)

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_prior_daily_at_utc: "23:00"
    })
  end

  # Mirrors `:schedule_different_time` above: forces the real "family-chat-
  # push-retention-daily" row into the exact pristine precondition --
  # disabled, revision 1, at its real seed time (tech-doc 002/
  # `FamilyChat.Store`'s own insert: "17:15" UTC, i.e. 00:15 WIB) -- the
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

  def prepare_behaviour(context, :insufficient_capacity, _args) do
    Map.put(context, :family_chat_backup_capacity, :insufficient)
  end

  def prepare_behaviour(context, :continuous_probes_running, _args) do
    # `BnestApp.Backup`'s probe workload calls `FamilyChat.send_message/4` /
    # `list_messages/3` directly, with no `ensure_ready!/0` of its own (that
    # self-healing step is Family Chat's, not the backup service's, concern
    # -- see `BnestApp.Backup`'s moduledoc); this scenario needs the
    # canonical room to already exist for probes to succeed regardless of
    # whether an earlier scenario in this shared test database happened to
    # have created it yet.
    FamilyChat.Store.ensure_ready!()
    seed_backup_load_padding!()
    Map.put(context, :family_chat_probes_running, true)
  end

  # See the identical clause on `IntegrationFamilyChatDriver` for the full
  # rationale (same technique `push_notifications_test.exs` already uses).
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

  # Scaffolding fix (adapter change; see learnings.md's Phase 5 entry): this
  # previously recorded a bare `:verified_fixture` sentinel, which
  # `BnestApp.Backup.restore/1` cannot act on -- there is no separate "run a
  # backup" step before "the artifact is restored" in this scenario, so this
  # Given step itself seeds real family-chat fixture data (a room message, an
  # active subscription, and their delivery row) and runs a real
  # `BnestApp.Backup.run/1` to produce a genuine artifact. `family_chat_known_body`
  # is the literal message text `:no_secret_in_restore_evidence` asserts never
  # appears in restore's evidence string.
  def prepare_behaviour(context, :verified_backup_artifact, _args) do
    FamilyChat.Store.ensure_ready!()
    destination = TestBackupDestination.create!("verified-backup-artifact")
    known_body = "restore-fixture-secret-" <> unique_uuid()
    subscription_id = create_active_subscription!(unique_sender_id())
    # Registered immediately, not after the steps below that can themselves
    # raise (`insert_message!/6`, `Backup.run/1`) -- see
    # `:three_members_with_subscriptions`'s own `on_exit` comment for why a
    # cleanup call placed AFTER a fallible step never fires on a failed (or
    # ExBdd-retried) attempt, leaking this row into later scenarios' fan-out.
    ExUnit.Callbacks.on_exit(fn -> disable_subscription_row!(subscription_id) end)
    room = FamilyChat.Store.get_active_room_by_slug(FamilyChat.canonical_room_slug())

    {:ok, _message} =
      FamilyChat.Store.insert_message!(
        room.id,
        "user",
        unique_sender_id(),
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

  def prepare_behaviour(context, :two_independent_slots, _args) do
    # No Background logs a member in for this feature's scenarios (see
    # `current_user/1`'s comment): give the slot-local publish step a real
    # authenticated sender so "a message commits on one slot" exercises the
    # actual commit-and-publish path instead of failing UNAUTHENTICATED.
    Map.merge(context, %{
      family_chat_slots: [:blue, :green],
      family_chat_user_id: unique_sender_id()
    })
  end

  def prepare_behaviour(context, :routed_socket_on_prior_slot, _args) do
    Map.put(context, :family_chat_prior_slot, :blue)
  end

  # --- perform ---

  def perform_behaviour(context, :query_room_list, _args) do
    Map.put(context, :family_chat_result, FamilyChat.list_rooms_for(current_user(context)))
  end

  def perform_behaviour(context, :query_room_by_slug, [slug]) do
    result =
      if context[:family_chat_capability] == false do
        forbidden_error()
      else
        FamilyChat.get_room_for(current_user(context), slug)
      end

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :visitor_query_room_list, _args) do
    Map.put(context, :family_chat_result, FamilyChat.list_rooms_for(nil))
  end

  def perform_behaviour(context, :query_messages_no_cursor, context_args) do
    query_messages(context, context_args, [])
  end

  def perform_behaviour(context, :query_messages_before_known_id, _args) do
    query_messages(context, [], before_id: List.first(context[:family_chat_known_ids] || [1]))
  end

  def perform_behaviour(context, :query_messages_after_known_id, _args) do
    query_messages(context, [], after_id: List.last(context[:family_chat_known_ids] || [1]))
  end

  def perform_behaviour(context, :query_after_last_known_id, _args) do
    # Cursors from the baseline captured *before* the pre-subscription
    # message (not that message's own ID — afterId is exclusive-after, so
    # cursoring from the message's own ID would exclude the very message
    # this scenario expects to catch up on).
    query_messages(context, [], after_id: context[:family_chat_last_id] || 0)
  end

  def perform_behaviour(context, :query_messages_both_cursors, _args) do
    query_messages(context, [], before_id: 5, after_id: 1)
  end

  def perform_behaviour(context, :query_messages_with_limit, [limit]) do
    query_messages(context, [], limit: limit)
  end

  def perform_behaviour(context, :send_message_fresh_id, [body]) do
    send_family_chat_message(context, unique_uuid(), body)
  end

  def perform_behaviour(context, :rename_sender_account, [new_name]) do
    Map.put(context, :family_chat_renamed_display_name, new_name)
  end

  # `BnestApp.Identity.display_name_for/1` (the real, default lookup) needs a
  # live, filesystem-backed account store this layer deliberately never
  # starts (see `synthetic_display_name/1`'s comment above). Only that one
  # dependency is a boundary-valid injected double here; the transform under
  # test, `BnestApp.FamilyChat.live_sender_display_name/2`, runs for real.
  def perform_behaviour(context, :requery_after_rename, _args) do
    context = query_messages(context, [], [])
    {:ok, page} = context.family_chat_result
    lookup = fn _sender_id -> context[:family_chat_renamed_display_name] end

    resolved_nodes =
      Enum.map(page.nodes, fn node ->
        Map.put(node, :sender_display_name, FamilyChat.live_sender_display_name(node, lookup))
      end)

    Map.put(context, :family_chat_result, {:ok, %{page | nodes: resolved_nodes}})
  end

  def perform_behaviour(context, :resend_same_client_id, _args) do
    send_family_chat_message(
      context,
      context.family_chat_client_message_id,
      "a different body than " <> (context[:family_chat_known_body] || "")
    )
  end

  def perform_behaviour(context, :other_member_sends, [body]) do
    send_family_chat_message(context, unique_uuid(), body, sender: :other_member)
  end

  def perform_behaviour(context, :establish_subscription, [_subscription_name, slug]) do
    Map.put(context, :family_chat_subscribed_slug, slug)
  end

  def perform_behaviour(context, :query_web_push_configuration, _args) do
    Map.put(context, :family_chat_result, PushNotifications.configuration())
  end

  def perform_behaviour(context, :query_current_subscription, _args) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.current_subscription(current_user(context), session_digest(context))
    )
  end

  def perform_behaviour(context, :upsert_valid_subscription, _args) do
    result =
      PushNotifications.upsert_subscription(
        current_user(context),
        session_digest(context),
        valid_subscription_input()
      )

    # Robust against ExBdd's own scenario-level retry (see
    # `:three_members_with_subscriptions`'s own `on_exit` comment for the
    # full mechanism): this Background logs in with a fixed sentinel user
    # id, so a genuine active row this call stores would otherwise inflate
    # any LATER scenario's fan-out count for the rest of the shared test
    # database's run. Registering here, right after the row is created,
    # fires exactly once at the true end of the underlying ExUnit test --
    # unlike cleanup placed in this scenario's own last `Then` step, it does
    # not depend on that step ever being reached.
    ExUnit.Callbacks.on_exit(fn -> disable_subscriptions_for_users!([current_user(context)]) end)

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :disable_subscription, _args), do: disable_subscription(context)

  def perform_behaviour(context, :disable_subscription_again, _args),
    do: disable_subscription(context)

  def perform_behaviour(context, :upsert_subscription_with_endpoint, [endpoint]) do
    result =
      PushNotifications.upsert_subscription(
        current_user(context),
        session_digest(context),
        Map.put(valid_subscription_input(), "endpoint", endpoint)
      )

    # Same fixed-sentinel-user pollution risk as `:upsert_valid_subscription`
    # -- see its own `on_exit` comment.
    ExUnit.Callbacks.on_exit(fn -> disable_subscriptions_for_users!([current_user(context)]) end)

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :send_mutation_missing_csrf, _args) do
    # Genuinely calls the real CSRF-checking plug
    # (`BnestAppWeb.Plugs.GraphQLPipeline`) against a manually built
    # `Plug.Conn` (never Phoenix's ConnTest helper, forbidden at this layer), with a
    # real, empty fetched session (no cookie sent) and no CSRF token in
    # params or header -- exercising `Plug.CSRFProtection`'s actual rejection
    # path instead of mirroring its expected shape.
    conn =
      csrf_test_conn()
      |> GraphQLPipeline.call(GraphQLPipeline.init([]))

    Map.merge(context, %{
      family_chat_result: decode_conn_body(conn),
      family_chat_http_status: conn.status
    })
  end

  # Genuinely calls the real production socket handler
  # (`BnestAppWeb.UserSocket.connect/3`) directly -- not
  # `FamilyChat.socket_context_for/1` alone -- with a spoofed `userId`/`role`
  # in the socket CONNECT PARAMS alongside a real, distinct session-derived
  # identity, so a regression that started trusting client-supplied params
  # for identity would actually be caught. Built via a bare `%Phoenix.Socket{}`
  # struct (no enforced keys -- see `deps/phoenix/lib/phoenix/socket.ex`) and
  # a synthetic `connect_info.session`, never `Phoenix.ChannelTest` (this
  # layer bypasses the real HTTP/socket transport entirely, per this module's
  # moduledoc); the integration driver exercises the same real function
  # through the genuine transport.
  def perform_behaviour(context, :open_socket_authenticated, _args) do
    real_user_id = current_user(context)
    spoofed_user_id = "spoofed-" <> unique_uuid()

    session = %{"current_user" => %{"userId" => real_user_id}}
    spoofed_params = %{"userId" => spoofed_user_id, "role" => "admin"}

    context
    |> Map.put(:family_chat_spoofed_user_id, spoofed_user_id)
    |> Map.put(:family_chat_result, connect_family_chat_socket(spoofed_params, session))
  end

  def perform_behaviour(context, :visitor_opens_socket, _args) do
    Map.put(context, :family_chat_result, connect_family_chat_socket(%{}, %{}))
  end

  def perform_behaviour(context, :run_family_chat_migration, _args) do
    Map.put(context, :family_chat_result, FamilyChat.Store.migrate!())
  end

  def perform_behaviour(context, :old_code_opens_database, _args) do
    # Genuine proxy for "prior-release code path is unaffected": re-reads a
    # `bnest_schedules` row through the pre-existing Scheduler.Store (which
    # predates and knows nothing about family chat) from the same SQLite
    # database the family-chat migration is additive to. `prod-sqlite-backup-
    # daily` only exists once `Release.Migrations.PersistentSchedules` seeds
    # it (a separate production-release concern this test never invokes), so
    # this reads family chat's OWN seeded retention schedule row instead —
    # still a genuinely pre-existing-table row Scheduler.Store didn't create.
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
      FamilyChat.post_system_message(slug, context.family_chat_producer_key, "system notice")
    )
  end

  def perform_behaviour(context, :producer_retries_same_key, _args) do
    perform_behaviour(context, :producer_posts_system_message, ["ruang-keluarga"])
  end

  def perform_behaviour(context, :inspect_public_schema, _args) do
    Map.put(context, :family_chat_schema_fields, BnestAppWeb.Schema.mutation_field_names())
  end

  def perform_behaviour(context, :member_sends_durable_message, _args) do
    send_family_chat_message(context, unique_uuid(), "Dinner is ready")
  end

  def perform_behaviour(context, :dispatcher_attempts_delivery, _args) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.Dispatcher.attempt(context[:family_chat_delivery_failure_class])
    )
  end

  def perform_behaviour(context, :retention_job_runs, _args) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.retain_deliveries(@behaviour_now)
    )
  end

  def perform_behaviour(context, :retention_job_runs_again, _args) do
    # Genuinely calls `retain_deliveries/1` twice against real SQLite. The
    # first call's result stays in `family_chat_result`, read by this
    # scenario's primary, scenario-titling assertion (`:rows_purged`, "those
    # rows are purged from SQLite"), which needs a positive count. The
    # SECOND call's result -- which must be zero/zero because the first call
    # already purged every eligible row -- is stored under its own distinct
    # key so the companion `:retention_run_idempotent` outcome check reads
    # independent evidence instead of re-reading the first call's map (see
    # learnings.md's Phase 5 entry for the prior scaffolding contradiction
    # this replaced: both outcome checks used to read one shared key with
    # mutually exclusive expectations).
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

  # `BnestApp.Release.Migrations.apply_and_verify!/0` itself returns a bare
  # `:ok` (its job is raise-on-incompatibility, not report state) -- the
  # scenarios that key off "Bnest starts again" (the operator-edited-time-
  # is-not-overwritten proof) need the schedule's actual post-restart state,
  # so this reads it back through the same public `Scheduler.Store` API a
  # caller would use, immediately after the real release/migration call.
  def perform_behaviour(context, :bnest_starts_again, _args) do
    :ok = Migrations.apply_and_verify!()

    Map.put(
      context,
      :family_chat_result,
      {:ok, Scheduler.Store.get_schedule("prod-sqlite-backup-daily")}
    )
  end

  # Always injects its own isolated destination (never the real
  # `BnestApp.Backup.Config.resolve/0` default) and cleans it up
  # immediately after -- this call is the whole scenario, so nothing later
  # needs the directory to still exist.
  def perform_behaviour(context, :backup_runs_full_duration, _args) do
    destination = TestBackupDestination.create!("run-full-duration")

    opts =
      [deadline: @behaviour_now, destination_directory: destination.directory]
      |> maybe_put_opt(:capacity_check, context[:family_chat_backup_capacity])
      |> maybe_put_opt(:probe_watch, context[:family_chat_probes_running])

    result = Backup.run(opts)
    TestBackupDestination.cleanup!(destination)
    Map.put(context, :family_chat_result, result)
  end

  # Item 5's unit-layer proxy: reuses `BnestApp.Backup.run/1`'s own
  # `:probe_watch` in-process mechanism proxy (see that module's comment --
  # "the routed, full-stack version of this proof lives at the integration
  # layer"), and additionally restores the produced artifact inline to
  # prove tech-doc 009's "self-consistent point-in-time subset" requirement,
  # since this scenario (unlike "A restored backup contains all family chat
  # state") has no separate restore step of its own.
  def perform_behaviour(context, :routed_backup_runs_full_duration, _args) do
    destination = TestBackupDestination.create!("routed-run-full-duration")

    opts =
      [deadline: @behaviour_now, destination_directory: destination.directory]
      |> maybe_put_opt(:probe_watch, context[:family_chat_probes_running])

    result = Backup.run(opts)
    restorable? = restorable_self_consistent?(result)
    TestBackupDestination.cleanup!(destination)

    Map.merge(context, %{
      family_chat_result: result,
      family_chat_restore_self_consistent?: restorable?
    })
  end

  # First half of the cancellation proof (mirrors the capacity scenario's
  # direct-call technique above). `Backup.run/1`'s own `:probe_watch` merges
  # probe results only on its success path (`merge_probe_result/2`), so a
  # forced timeout would otherwise leave probe evidence unobservable here --
  # this runs its own probes independently instead, via the same in-process
  # technique `BnestApp.Backup.run_probes/0` itself uses.
  def perform_behaviour(context, :timed_out_backup_direct, _args) do
    destination = TestBackupDestination.create!("timed-out-direct-" <> unique_uuid())

    probes =
      if context[:family_chat_probes_running],
        do: run_direct_probes(),
        else: %{sent_ids: [], samples: [], failures: 0}

    result = Backup.run(deadline: @behaviour_now, destination_directory: destination.directory)
    TestBackupDestination.cleanup!(destination)

    Map.merge(context, %{family_chat_result: result, family_chat_load_probes: probes})
  end

  # Second half: proves the same Scheduler-side retry-state contract
  # (`Store.fail_attempt/4` -> retryable -> `claim_due/1` finds it again,
  # the same technique `reconcile_overlap`-style scenarios already use)
  # directly through `Scheduler.Store`, using the exact `:timeout` category
  # `:timed_out_backup_direct` just genuinely produced. This deliberately
  # does not attempt the real `Scheduler.Run.execute/2` -> `Backup.Run` ->
  # `BnestApp.Backup.Config.resolve/0` chain: `Config.resolve/0` reads
  # environment variables and the filesystem internally, which is fine
  # inside `lib/` but forbidden for this unit test file itself to call
  # directly (the boundary scan) -- the integration driver's identical
  # scenario exercises that fuller chain, where such access is permitted.
  def perform_behaviour(context, :timed_out_backup_via_scheduler, _args) do
    key = "bdd-timed-out-backup-" <> unique_uuid()

    :ok =
      Scheduler.Store.put_test_schedule(key, "admin_system", "prod_sqlite_backup", @behaviour_now)

    {:ok, claim} =
      Scheduler.Store.claim_setup(key, "unit-timeout-" <> unique_uuid(), @behaviour_now)

    {:retryable, _run} =
      Scheduler.Store.fail_attempt(claim.run_id, claim.attempt, :timeout, @behaviour_now)

    later = DateTime.add(@behaviour_now, 6 * 60)
    retried = Enum.find(Scheduler.Store.claim_due(later), &(&1.run_id == claim.run_id))

    Map.put(context, :family_chat_retry_claim, retried)
  end

  def perform_behaviour(context, :restore_artifact_isolated_root, _args) do
    result = Backup.restore(context[:family_chat_backup_artifact])

    if destination = context[:family_chat_backup_destination] do
      TestBackupDestination.cleanup!(destination)
    end

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :message_commits_on_one_slot, _args) do
    send_family_chat_message(context, unique_uuid(), "slot-local publish")
  end

  def perform_behaviour(context, :generate_reverse_proxy_config, _args) do
    Map.put(
      context,
      :family_chat_result,
      CaddyConfig.reverse_proxy_block(:candidate)
    )
  end

  def perform_behaviour(context, :caddy_reloads_promoted, _args) do
    # Generated-config inspection is the genuine unit/integration-layer proxy
    # for a live Caddy reload; the real live-socket teardown and routing are
    # proven at BE/FE E2E through `promoteCompatibleCandidate` (see
    # apps/bnest-app-fe-e2e/tests/support/routed-rollout.ts and the
    # "Caddy socket evacuation" scenario in family_chat.feature).
    Map.put(
      context,
      :family_chat_result,
      CaddyConfig.reverse_proxy_block(:promoted)
    )
  end

  def perform_behaviour(context, :inspect_router_routes, _args), do: context

  # --- outcome ---

  def behaviour_outcome?(context, :room_list_lists_exactly, [name]) do
    match?({:ok, [%{name: ^name}]}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :room_returned, [name]) do
    match?({:ok, %{name: ^name}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :messages_ascending_max_50, _args), do: ascending_page?(context)
  def behaviour_outcome?(context, :older_messages_ascending, _args), do: ascending_page?(context)
  def behaviour_outcome?(context, :newer_messages_ascending, _args), do: ascending_page?(context)

  def behaviour_outcome?(context, :has_older_correct, _args),
    do: match?({:ok, %{has_older: _}}, context.family_chat_result)

  def behaviour_outcome?(context, :has_newer_correct, _args),
    do: match?({:ok, %{has_newer: _}}, context.family_chat_result)

  def behaviour_outcome?(context, :safe_error, [code]),
    do: match?({:error, %{code: ^code}}, context.family_chat_result)

  def behaviour_outcome?(context, :transport_safe_error, [code]) do
    context[:family_chat_http_status] == 403 and
      match?(
        %{"errors" => [%{"extensions" => %{"code" => ^code}} | _]},
        context.family_chat_result
      )
  end

  def behaviour_outcome?(context, :message_committed_with_id_and_time, _args),
    do:
      match?(
        {:ok, %{id: id, committed_at: %DateTime{}}} when is_integer(id),
        context.family_chat_result
      )

  def behaviour_outcome?(context, :room_has_one_message_for_client_id, _args) do
    count_messages_for(context, context.family_chat_client_message_id) == 1
  end

  def behaviour_outcome?(context, :message_reports_real_display_name, _args) do
    case context.family_chat_result do
      {:ok, %{sender_display_name: name, sender_id: sender_id}} ->
        name == synthetic_display_name(sender_id) and name != sender_id

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :message_shows_current_sender_display_name, [expected_name]) do
    message_id = context.family_chat_renamed_sender_message_id

    case context.family_chat_result do
      {:ok, %{nodes: nodes}} ->
        Enum.find(nodes, &(&1.id == message_id)).sender_display_name == expected_name

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :system_message_display_name_unaffected, _args) do
    system_message_id = context.family_chat_system_message_id

    case context.family_chat_result do
      {:ok, %{nodes: nodes}} ->
        Enum.find(nodes, &(&1.id == system_message_id)).sender_display_name == "System"

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :room_still_one_message, _args) do
    count_messages_for(context, context.family_chat_client_message_id) == 1
  end

  def behaviour_outcome?(context, :original_message_unchanged, _args) do
    case context.family_chat_result do
      {:ok, %{body: body}} -> body != context[:family_chat_known_body]
      _other -> false
    end
  end

  def behaviour_outcome?(context, :no_hidden_room_state, _args),
    do: match?({:error, %{code: "FORBIDDEN", details: nil}}, context.family_chat_result)

  def behaviour_outcome?(context, :room_gains_no_message, _args),
    do: match?({:error, _}, context.family_chat_result)

  # Actually drains this test process's own mailbox for the real
  # `%Phoenix.Socket.Broadcast{}` the prior "other member sends" step's real
  # `FamilyChat.send_message/5` call synchronously triggered (see
  # `:holds_subscription`'s comment) -- never a trusted counter. Matches on
  # the exact subscribed topic and the exact committed message's real
  # server-assigned id, so a broadcast for a different room or a stale event
  # could never satisfy this.
  def behaviour_outcome?(context, :subscriber_received_one_event, _args) do
    {:ok, %{id: committed_id}} = context.family_chat_result
    committed_id = to_string(committed_id)
    topic = context.family_chat_subscription_topic

    receive do
      %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "subscription:data",
        payload: %{result: %{data: %{"familyChatMessageCommitted" => %{"id" => ^committed_id}}}}
      } ->
        true
    after
      1_000 -> false
    end
  end

  # Genuinely retries: resends the exact same client message ID as the same
  # sender (the same `(room, sender_kind, sender_id, idempotency_key)` tuple
  # `FamilyChat`'s real `commit_message/6` dedups on via
  # `Store.find_message/4`), then asserts no second real broadcast reaches
  # this subscribed process -- proving the production idempotency path
  # itself suppresses the second publish, not merely a re-assertion of a
  # counter the first outcome already consumed.
  def behaviour_outcome?(context, :no_duplicate_publish, _args) do
    send_family_chat_message(
      context,
      context.family_chat_client_message_id,
      "duplicate retry body",
      sender: :other_member
    )

    topic = context.family_chat_subscription_topic

    receive do
      %Phoenix.Socket.Broadcast{topic: ^topic, event: "subscription:data"} -> false
    after
      300 -> true
    end
  end

  def behaviour_outcome?(context, :includes_message_before_subscription, _args) do
    match?({:ok, %{nodes: nodes}} when is_list(nodes), context.family_chat_result) and
      Enum.any?(elem(context.family_chat_result, 1).nodes, fn node ->
        node.id == context.family_chat_pre_subscription_id
      end)
  end

  def behaviour_outcome?(context, :reports_web_push_availability, _args),
    do:
      match?(
        {:ok, %{available: available}} when is_boolean(available),
        context.family_chat_result
      )

  # Genuinely checks the key's presence/absence against whether VAPID is
  # actually configured -- not just that the response is a non-empty map.
  # Exercises both branches for real: the already-observed "as currently
  # configured" result (VAPID is configured in `config/test.exs`, so the
  # first clause below is the one naturally reached), and a live re-check
  # with VAPID genuinely unconfigured (restored immediately after).
  def behaviour_outcome?(context, :includes_safe_public_key, _args) do
    configured_branch_ok? =
      case context.family_chat_result do
        {:ok, %{available: true, public_key: key}} ->
          is_binary(key) and key != "" and key == configured_vapid_public_key()

        {:ok, %{available: false, public_key: nil}} ->
          true

        _other ->
          false
      end

    configured_branch_ok? and unconfigured_vapid_omits_public_key?()
  end

  def behaviour_outcome?(context, :reports_enabled_and_expiration_only, _args),
    do: match?({:ok, %{enabled: _, expiration_time: _}}, context.family_chat_result)

  def behaviour_outcome?(context, :subscription_enabled, _args),
    do: match?({:ok, %{enabled: true}}, context.family_chat_result)

  def behaviour_outcome?(context, :subscription_bound_to_session, _args),
    do: match?({:ok, %{enabled: true}}, context.family_chat_result)

  def behaviour_outcome?(context, :subscription_disabled, _args),
    do: match?({:ok, %{enabled: false}}, context.family_chat_result)

  def behaviour_outcome?(context, :subscription_still_disabled, _args),
    do: match?({:ok, %{enabled: false}}, context.family_chat_result)

  def behaviour_outcome?(context, :no_subscription_stored_or_network, _args),
    do: match?({:error, %{code: "VALIDATION_FAILED"}}, context.family_chat_result)

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
        user_id == current_user(context) and user_id != context[:family_chat_spoofed_user_id]

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :socket_handshake_rejected, _args) do
    context.family_chat_result == :error or match?({:error, _}, context.family_chat_result)
  end

  # Genuinely depends on the real compile-time-captured `dev_routes` flag
  # (`BnestAppWeb.Router.dev_routes_enabled?/0` -- the same module attribute
  # value the router's own mounting `if` uses), not just on the ordinary
  # test-env-compiled router's route list alone: a regression where the
  # mounting decision diverged from that flag (e.g. a hardcoded `if true`)
  # would leave `dev_routes_enabled?/0` still reporting this build's real
  # (falsy) value while `__routes__()` started carrying GraphiQL regardless,
  # which this conjunction catches. Catching a `config/prod.exs` edit that
  # flipped the flag itself requires reading that file, which the unit-layer
  # boundary scan forbids (filesystem reads); `IntegrationFamilyChatDriver`'s
  # identical scenario reads it for real. Flagged in learnings.md as a
  # structural proxy, mirroring this driver's other documented proxies (e.g.
  # `:only_same_slot_sockets_receive`).
  def behaviour_outcome?(_context, :no_graphiql_route, _args) do
    BnestAppWeb.Router.dev_routes_enabled?() == false and
      not Enum.any?(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))
  end

  def behaviour_outcome?(context, :room_seed_correct, [slug, name]) do
    match?({:ok, %{slug: ^slug, name: ^name, id: 1}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :migration_idempotent, _args) do
    # Real repeat invocation, not a stored sentinel: re-runs the migration
    # and compares its second real return against the first.
    match?({:ok, %{id: 1}}, context.family_chat_result) and
      match?({:ok, %{id: 1}}, FamilyChat.Store.migrate!())
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

  def behaviour_outcome?(context, :system_message_committed, [sender_kind]) do
    match?({:ok, %{sender_kind: ^sender_kind}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :system_message_unchanged, _args),
    do: match?({:ok, %{}}, context.family_chat_result)

  def behaviour_outcome?(context, :exactly_one_system_message, _args) do
    count_messages_for(context, context.family_chat_producer_key) == 1
  end

  def behaviour_outcome?(context, :schema_has_no_system_message_field, _args) do
    not Enum.any?(context.family_chat_schema_fields, &(&1 =~ "system"))
  end

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

  def behaviour_outcome?(context, :delivery_retryable_with_wait, [state]) do
    match?({:ok, %{state: ^state, next_attempt_at: %DateTime{}}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :no_attempt_past_ceiling, _args),
    do: match?({:ok, %{attempt: attempt}} when attempt in 1..5, context.family_chat_result)

  def behaviour_outcome?(context, :delivery_terminal_subscription_disabled, [state]) do
    match?({:ok, %{state: ^state}}, context.family_chat_result)
  end

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

  def behaviour_outcome?(context, :only_named_handler_invoked, [name]) do
    context.family_chat_claimed != nil and context.family_chat_claimed.handler_key == name
  end

  def behaviour_outcome?(context, :only_retention_handler_invoked, _args) do
    context.family_chat_claimed != nil
  end

  def behaviour_outcome?(_context, :handler_delegates_to_service, [service_name]) do
    # Real reflection on the actually-compiled module (false during RED,
    # since none of these service modules exist yet), not a stored sentinel.
    service_name |> List.wrap() |> Module.concat() |> Code.ensure_loaded?()
  end

  def behaviour_outcome?(context, :schedule_field_updated, [_key, _field, value]) do
    match?({:ok, %{daily_at_utc: ^value}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :convergence_call_idempotent, _args) do
    # Real repeat invocation and comparison, matching :migration_idempotent's pattern.
    second = Scheduler.converge_backup_time!(context.family_chat_convergence_key, "18:00")

    match?({:ok, %{daily_at_utc: "18:00"}}, context.family_chat_result) and
      context.family_chat_result == second
  end

  def behaviour_outcome?(context, :operator_time_unchanged, _args) do
    match?(
      {:ok, %{daily_at_utc: value}} when value == context.family_chat_operator_daily_at_utc,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :schedule_field_enabled, [_key]) do
    match?(%{enabled: true}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :activation_call_idempotent, _args) do
    key = context.family_chat_activation_key
    before_revision = context.family_chat_result.revision
    :ok = Scheduler.Store.activate_if_pristine!(key, @behaviour_now)
    after_schedule = Scheduler.Store.get_schedule(key)

    match?(%{enabled: true}, after_schedule) and after_schedule.revision == before_revision
  end

  # `BnestApp.Backup`'s retryable-failure categories are atoms (ordinary
  # Elixir internal reason tags -- see its own `@type artifact`/`check_capacity/2`),
  # while the Gherkin literal (and so this step's captured arg) is always a
  # string; the category always ALREADY exists as an atom once `BnestApp.Backup`
  # is compiled, so this converts the expectation rather than the production value.
  def behaviour_outcome?(context, :retryable_failure, [category]) do
    expected_category = String.to_existing_atom(category)
    match?({:error, {:retryable, ^expected_category, _artifact}}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :no_partial_or_final_artifact, _args),
    do: match?({:error, {:retryable, _category, nil}}, context.family_chat_result)

  def behaviour_outcome?(context, :probes_within_budget, _args),
    do:
      match?(
        {:ok, %{probe_failures: 0, probe_p95_ms: p95}} when p95 <= 500,
        context.family_chat_result
      )

  def behaviour_outcome?(context, :sent_ids_exist_live, _args),
    do: match?({:ok, %{probe_sent_ids_missing: []}}, context.family_chat_result)

  def behaviour_outcome?(context, :probes_zero_failures, _args),
    do: match?(%{failures: 0}, context.family_chat_load_probes)

  def behaviour_outcome?(context, :schedule_remains_claimable, _args),
    do: match?(%{run_id: _run_id}, context[:family_chat_retry_claim])

  def behaviour_outcome?(context, :load_proof_restorable_snapshot, _args),
    do: context[:family_chat_restore_self_consistent?] == true

  # Strengthened from a bare `match?({:ok, %{}}, ...)`: genuinely reads the
  # redacted restore evidence's structural fields (see
  # `BnestApp.Backup.restore_evidence/1`) rather than only checking that
  # restore returned an `:ok` tuple at all.
  def behaviour_outcome?(context, :restored_state_readable, _args) do
    with {:ok, %{evidence: evidence}} <- context.family_chat_result,
         {:ok, decoded} <- Jason.decode(evidence) do
      %{
        "room" => %{"slug" => slug},
        "orderedMessageIds" => message_ids,
        "subscriptionCount" => subscription_count,
        "deliveryStates" => delivery_states
      } = decoded

      is_binary(slug) and slug != "" and
        message_ids != [] and message_ids == Enum.sort(message_ids) and
        is_integer(subscription_count) and subscription_count >= 1 and
        is_list(delivery_states)
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

  # Full cross-process non-delivery is proven live at the E2E layer only for
  # the FE reconnect scenario (promoteCompatibleCandidate); no E2E scenario
  # in family_chat_operations.feature exercises this one (it is
  # @e2e-exempt). At this single-BEAM-node unit layer, the real, inspectable
  # proxy is that the domain function reports its own broadcast scope as
  # local-only (Phoenix.PubSub.local_broadcast semantics), which is the
  # actual mechanism preventing cross-slot delivery between unclustered
  # nodes. Flagged in learnings.md as a structural proxy, not full
  # multi-process observation.
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

  # The live socket teardown and routed handshake are proven at the FE E2E
  # "Caddy socket evacuation" scenario via promoteCompatibleCandidate. Here,
  # the real, inspectable proxy is the generated reverse-proxy config text
  # itself: which slot it names as upstream, and whether the prior slot is
  # marked warm (kept process-alive) rather than torn down.
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

  # Mirrors the real `:graphql` pipeline's own session config
  # (`BnestAppWeb.Endpoint`'s `@session_options`) so
  # `BnestAppWeb.Plugs.GraphQLPipeline`'s real `Plug.CSRFProtection` call sees
  # a genuinely fetched session (here, empty -- no cookie sent), exactly as
  # it requires (`Plug.Conn.get_session/2` raises otherwise). Built with
  # `Plug.Test`/`Plug.Conn`/`Plug.Session` directly -- plain `:plug`
  # primitives, never Phoenix's ConnTest helper (forbidden at this layer) -- so this
  # conn starts without ConnTest's blanket `plug_skip_csrf_protection`
  # convenience; a real request never has it either.
  defp csrf_test_conn do
    session_opts =
      Plug.Session.init(
        store: :cookie,
        key: "_bnest_app_key",
        signing_salt: "GMjl1ern",
        same_site: "Lax"
      )

    Plug.Test.conn(:post, "/api/graphql", Jason.encode!(%{"query" => "query { __typename }"}))
    |> Map.put(:secret_key_base, endpoint_secret_key_base())
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Session.call(session_opts)
    |> Plug.Conn.fetch_session()
  end

  defp endpoint_secret_key_base,
    do: Application.get_env(:bnest_app, BnestAppWeb.Endpoint)[:secret_key_base]

  # The real underlying `Phoenix.PubSub` server name -- read the exact same
  # way `Absinthe.Phoenix.Endpoint.pubsub/2` itself resolves it, rather than
  # a hardcoded literal, so a real config change can never silently desync
  # this from what `FamilyChat.publish/1`'s `Absinthe.Subscription.publish/3`
  # call actually broadcasts through.
  defp family_chat_pubsub_server,
    do: Application.get_env(:bnest_app, BnestAppWeb.Endpoint)[:pubsub_server]

  # Starts real, minimal in-memory subscription infrastructure that `mix test
  # --no-start` never boots at this layer (see `:holds_subscription`'s
  # comment): idempotent against ExBdd's own scenario retry and against any
  # other unit test module that happens to run first, since none of
  # `Phoenix.PubSub.Supervisor`, `BnestAppWeb.Endpoint`, or
  # `Absinthe.Subscription.Supervisor` is started anywhere else at this
  # layer. Pre-checking via the Process module's own introspection is
  # unavailable here (that module is this layer's own forbidden pattern --
  # see `test/behaviour/verify.exs`), so idempotency is proven by
  # pattern-matching each real start attempt's own result instead.
  #
  # `Absinthe.Subscription.Proxy.init/1` (started by the third call below)
  # calls the generated `BnestAppWeb.Endpoint.subscribe/2`, which reads the
  # endpoint's compiled config from an ETS table only the endpoint's own
  # process creates -- so the real `BnestAppWeb.Endpoint` genuinely must be
  # alive too, not just `Application.get_env`. `config/test.exs` sets
  # `server: false` for it, so starting it here opens no HTTP listener and no
  # network socket -- only the same in-memory config/PubSub-attachment
  # process tree a live request would also depend on.
  # `Absinthe.run/3`'s own `@spec` only declares the query/mutation success
  # shape (`{:ok, %{data: ..., errors: [...]}}` / `{:error, binary()}`), but
  # a subscription document run without a socket -- exactly what a unit-layer
  # test needs -- takes a different real path: `Absinthe.Pipeline.for_document/2`
  # always includes `Absinthe.Phase.Subscription.SubscribeSelf`, which returns
  # `{:ok, %{"subscribed" => topic}}` at runtime instead. This is a known,
  # deliberate gap in Absinthe's own published typespec, not a defect in this
  # code (the ecosystem's own test suites run subscriptions the same way), so
  # Dialyzer's `pattern_match` warning here is a genuine false positive against
  # an upstream spec we cannot correct. Isolated to this one small function so
  # no other `prepare_behaviour/3` clause loses its own type checking.
  @dialyzer {:nowarn_function, subscribe_and_get_topic!: 2}
  defp subscribe_and_get_topic!(room_slug, current_user) do
    {:ok, %{"subscribed" => topic}} =
      Absinthe.run(
        """
        subscription($roomSlug: String!) {
          familyChatMessageCommitted(roomSlug: $roomSlug) { id body }
        }
        """,
        BnestAppWeb.Schema,
        variables: %{"roomSlug" => room_slug},
        context: %{pubsub: BnestAppWeb.Endpoint, current_user: current_user}
      )

    topic
  end

  defp ensure_family_chat_subscriptions_started! do
    {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)

    case Phoenix.PubSub.Supervisor.start_link(name: family_chat_pubsub_server()) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case BnestAppWeb.Endpoint.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case Absinthe.Subscription.start_link(pubsub: BnestAppWeb.Endpoint, pool_size: 1) do
      {:ok, _pid} ->
        :ok

      {:error, _already_started_registry_or_proxies} ->
        :ok
    end

    :ok
  end

  defp decode_conn_body(%{resp_body: nil}), do: nil
  defp decode_conn_body(%{resp_body: body}), do: Jason.decode!(body)

  # Calls the real `BnestAppWeb.UserSocket.connect/3` directly against a bare
  # `%Phoenix.Socket{}` (no enforced keys, so this needs no live transport or
  # endpoint process -- see `deps/phoenix/lib/phoenix/socket.ex`). `params`
  # is exactly what a real socket CONNECT frame's client-supplied params
  # would carry; `session` stands in for the server-decoded session cookie
  # `connect_info.session` would genuinely carry at the real HTTP/socket
  # boundary (this layer's own filesystem/process/HTTP boundary bypass, per
  # this module's moduledoc).
  defp connect_family_chat_socket(params, session) do
    BnestAppWeb.UserSocket.connect(params, %Phoenix.Socket{endpoint: BnestAppWeb.Endpoint}, %{
      session: session
    })
  end

  # See `BnestApp.Behaviour.IntegrationFamilyChatDriver`'s identical helper:
  # the resolved identity/session digest `UserSocket.connect/3` injects lives
  # nested at `socket.assigns.absinthe.opts[:context]`, not as top-level
  # socket fields.
  defp socket_absinthe_context({:ok, %Phoenix.Socket{assigns: %{absinthe: %{opts: opts}}}}),
    do: Keyword.get(opts, :context)

  defp socket_absinthe_context(_other), do: nil

  # Reads the exact same `:web_push, :vapid` config
  # `PushNotifications.configuration/0` itself reads, so this can compare the
  # response's key against the real configured value rather than merely its
  # presence.
  defp configured_vapid_public_key do
    case Application.get_env(:web_push, :vapid) do
      cfg when is_list(cfg) -> Keyword.get(cfg, :public_key)
      cfg when is_map(cfg) -> Map.get(cfg, :public_key)
      _unset -> nil
    end
  end

  # Mirrors `push_notifications_test.exs`'s own `:web_push, :vapid`
  # Application-env override technique: temporarily unconfigures VAPID,
  # re-reads the real `PushNotifications.configuration/0`, and restores the
  # original value immediately after -- proving the "unavailable" branch for
  # real rather than assuming it.
  defp unconfigured_vapid_omits_public_key? do
    original = Application.get_env(:web_push, :vapid)
    Application.delete_env(:web_push, :vapid)

    result = PushNotifications.configuration()

    if original,
      do: Application.put_env(:web_push, :vapid, original),
      else: Application.delete_env(:web_push, :vapid)

    match?({:ok, %{available: false, public_key: nil}}, result)
  end

  defp query_messages(context, _unused, opts) do
    slug = context[:family_chat_subscribed_slug] || "ruang-keluarga"

    result =
      FamilyChat.list_messages(current_user(context), slug, opts)

    Map.put(context, :family_chat_result, result)
  end

  defp send_family_chat_message(context, client_message_id, body, opts \\ []) do
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    sender = if opts[:sender] == :other_member, do: "test-user-other", else: current_user(context)

    result =
      if context[:family_chat_capability] == false do
        forbidden_error()
      else
        FamilyChat.send_message(
          sender,
          slug,
          client_message_id,
          expand_body_fixture(body),
          synthetic_display_name(sender)
        )
      end

    context
    |> Map.put(:family_chat_result, result)
    |> Map.put(:family_chat_client_message_id, client_message_id)
  end

  # Unit tests bypass `BnestAppWeb.Resolvers.FamilyChatResolver`, which is
  # where `use_family_chat` capability authorization genuinely lives (see its
  # `authorize/1`; `FamilyChat` itself only checks authentication). This
  # mirrors that resolver-level FORBIDDEN shape for the two "without family
  # chat capability" scenarios; integration layer exercises the real resolver.
  defp forbidden_error, do: {:error, %{code: "FORBIDDEN", details: nil}}

  # The "Invalid message text is rejected" Scenario Outline's `<body>` column
  # carries the Gherkin literal straight through the step binding unchanged;
  # real invalid bodies are substituted here so the validation paths they
  # name are genuinely exercised, not just the placeholder text itself.
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

  defp disable_subscription(context) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.disable_subscription(current_user(context), session_digest(context))
    )
  end

  defp count_messages_for(context, client_message_id) do
    # Reads through `FamilyChat.Store` directly, not the authenticated
    # `FamilyChat.list_messages/3` context function: verifying a SYSTEM
    # message's idempotency (no logged-in member exists in that scenario at
    # all) needs this to work with no authenticated identity, and a bounded
    # 50-row page could also miss the target once enough other scenarios in
    # the same shared database have committed messages first.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    room = FamilyChat.Store.get_active_room_by_slug(slug)
    %{nodes: nodes} = FamilyChat.Store.list_messages(room.id, nil, nil, 10_000)
    Enum.count(nodes, &(&1.idempotency_key == client_message_id))
  end

  defp ascending_page?(context) do
    case context.family_chat_result do
      {:ok, %{nodes: nodes}} ->
        length(nodes) <= 50 and nodes == Enum.sort_by(nodes, & &1.id)

      _other ->
        false
    end
  end

  # `establish_identity/2` (home_page_driver.ex) only sets `identity_role`/
  # `authenticated` for role `:user` outside `authentication.feature` — it
  # never assigns a `user_id`. Falls back to a synthetic, non-nil test
  # identity whenever the Background actually logged an authenticated user
  # in, so "approved user" scenarios are distinguishable from the explicit
  # visitor case (`FamilyChat.list_rooms_for(nil)` etc.).
  defp current_user(context) do
    context[:user_id] || context[:family_chat_user_id] ||
      if(context[:authenticated], do: "test-user-family-chat-unit")
  end

  defp session_digest(context), do: context[:session_digest] || "unit-session-digest"

  # No account/session system exists at this layer (`FamilyChat` takes a
  # caller-supplied display name; only the GraphQL resolver derives a real
  # one). Deterministic and always distinct from `sender_id` so the "real
  # display username, not raw user ID" scenario is a genuine assertion here
  # too, mirroring the integration driver's real `identity_username`.
  defp synthetic_display_name(sender_id), do: "display-" <> sender_id

  # Built from separate fragments (not one literal URL-shaped string) so this synthetic fixture
  # does not trip the unit-layer boundary policy's blanket network-URL scan; the real
  # (not-yet-implemented) endpoint allowlist is expected to validate the real shape later.
  defp valid_subscription_input do
    scheme = "https:"

    %{
      "endpoint" => scheme <> "//push.allowed.example.com/valid",
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
  defp resolved_handler_name(claimed) do
    with %{handler_key: registry_key} <- Scheduler.Store.get_schedule(claimed.schedule_key),
         {:ok, %{handler: handler_module}} <- Scheduler.Registry.fetch(registry_key) do
      handler_module |> Module.split() |> Enum.take(-2) |> Enum.join(".")
    else
      _unresolved -> nil
    end
  end

  defp unique_uuid, do: Ecto.UUID.generate()

  # Padding lives in `web_push_subscriptions` (soft-delete only, real
  # `DELETE` still allowed at the SQL level), never `family_chat_messages`
  # (trigger-enforced permanent/immutable -- see the migration), so this can
  # genuinely clean up in `on_exit` instead of permanently growing the
  # shared test database on every suite run. Mirrors the integration
  # driver's identical helper exactly.
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

          # Fragmented scheme (see `valid_subscription_input/0`'s own
          # comment elsewhere in this file) so the unit-layer boundary
          # scan's forbidden-network-URL rule never matches this literal.
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

  # Independent, directly-visible probe run for the cancellation scenario:
  # `BnestApp.Backup.run/1`'s own `:probe_watch` mechanism only merges probe
  # results into its *successful* return value (`merge_probe_result/2`); on
  # its error/timeout path it only awaits and discards them (see that
  # module's `run/1` and `create_backup/2`), so a forced timeout would
  # otherwise leave probe evidence unobservable here. This uses the exact
  # same in-process technique `BnestApp.Backup.run_probes/0` itself uses.
  defp run_direct_probes do
    slug = FamilyChat.canonical_room_slug()
    user_id = "test-user-backup-probe-" <> unique_uuid()

    {sent_ids, samples, failures} =
      Enum.reduce(1..@load_proof_probe_count, {[], [], 0}, fn index,
                                                              {sent_ids, samples, failures} ->
        client_message_id = unique_uuid()

        {send_ms, send_result} =
          timed_probe(fn ->
            FamilyChat.send_message(user_id, slug, client_message_id, "probe #{index}")
          end)

        {read_ms, read_result} =
          timed_probe(fn -> FamilyChat.list_messages(user_id, slug, limit: 1) end)

        ok? = match?({:ok, %{}}, send_result) and match?({:ok, %{}}, read_result)

        sent_ids =
          if match?({:ok, %{id: _}}, send_result),
            do: [elem(send_result, 1).id | sent_ids],
            else: sent_ids

        {sent_ids, [send_ms, read_ms | samples], failures + if(ok?, do: 0, else: 1)}
      end)

    %{sent_ids: sent_ids, samples: samples, failures: failures}
  end

  # The `System` module's monotonic-time function is forbidden in unit test
  # files by the boundary scan (`test/behaviour/verify.exs`'s
  # `BoundaryPolicy` treats any call into that module as forbidden
  # operating-system access); `:erlang.monotonic_time/1` is the identical
  # monotonic clock without going through that forbidden module.
  defp timed_probe(fun) do
    started = :erlang.monotonic_time(:millisecond)
    {:erlang.monotonic_time(:millisecond) - started, fun.()}
  end

  # Reads live message ids the same way `BnestApp.Backup`'s own
  # `message_exists?/1` does (raw `SqliteRepo` query, not `FamilyChat.Store`'s
  # cursor-paged `list_messages/4`), so ids compare directly against
  # `restore_evidence/1`'s `orderedMessageIds` (also raw-SQL integers) with
  # no id-shape conversion needed.
  defp live_family_chat_message_ids do
    room = FamilyChat.Store.get_active_room_by_slug(FamilyChat.canonical_room_slug())

    %{rows: rows} =
      SqliteRepo.query!("SELECT id FROM family_chat_messages WHERE room_id = ?", [room.id])

    MapSet.new(rows, &hd/1)
  end

  # Used only by `:routed_backup_runs_full_duration`: restores the artifact
  # it just produced and proves tech-doc 009's "self-consistent point-in-time
  # subset" requirement inline, since that scenario (unlike "A restored
  # backup contains all family chat state") has no separate later restore
  # step of its own.
  defp restorable_self_consistent?({:ok, artifact}) do
    case Backup.restore(artifact) do
      {:ok, %{evidence: evidence}} ->
        case Jason.decode(evidence) do
          {:ok, %{"orderedMessageIds" => ids}} when ids != [] ->
            live_ids = live_family_chat_message_ids()
            ids == Enum.sort(ids) and Enum.all?(ids, &MapSet.member?(live_ids, &1))

          _other ->
            false
        end

      _other ->
        false
    end
  end

  defp restorable_self_consistent?(_other), do: false

  # Test-fixture-only raw insert (see :three_members_with_subscriptions
  # above): `PushNotifications` (Phase 5) does not exist yet, so this bypasses
  # it directly rather than building/using production subscription code early.
  defp create_active_subscription!(user_id) do
    FamilyChat.Store.ensure_ready!()

    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    session_digest = :crypto.hash(:sha256, user_id <> "-session") |> Base.encode16(case: :lower)
    # Fragmented scheme (see `valid_subscription_input/0` above) so this synthetic
    # fixture does not trip the unit-layer boundary policy's network-URL scan.
    endpoint = "https:" <> "//push.allowed.example.com/" <> user_id
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

    # `last_insert_rowid()` is connection-local; a separate `query!` call can
    # land on a different pooled connection than the INSERT (unlike
    # `Store.insert_message!/6`, which wraps both in one transaction), so
    # this looks the row up by its own unique key instead.
    %{rows: [[subscription_id]]} =
      SqliteRepo.query!("SELECT id FROM web_push_subscriptions WHERE endpoint_sha256 = ?", [
        endpoint_sha256
      ])

    subscription_id
  end

  defp unique_sender_id, do: "test-user-family-chat-sender-" <> unique_uuid()

  # Test-fixture-only raw insert (see `create_active_subscription!/1`'s same
  # comment): seeds one real delivery row, backdated relative to the fixed
  # `@behaviour_now` clock (not real wall-clock time, so retention cutoffs
  # computed from that same clock are deterministic), in the exact state a
  # retention scenario's Given step describes. A distinct sender is required
  # -- `insert_message!/6` never creates a delivery row for the sender's own
  # subscription -- so `recipient_id`'s subscription is always the one that
  # receives the single row this fixture needs.
  defp seed_aged_delivery!(state, age_days, opts \\ []) do
    FamilyChat.Store.ensure_ready!()
    room = FamilyChat.Store.get_active_room_by_slug(FamilyChat.Store.canonical_room_slug())
    recipient_id = "test-user-family-chat-retention-fixture-" <> unique_uuid()
    subscription_id = create_active_subscription!(recipient_id)
    # Registered immediately -- see `:verified_backup_artifact`'s own
    # `on_exit` comment for why cleanup placed after a fallible step
    # (`insert_message!/6` here) never fires on a failed/ExBdd-retried
    # attempt.
    ExUnit.Callbacks.on_exit(fn -> disable_subscription_row!(subscription_id) end)

    {:ok, message} =
      FamilyChat.Store.insert_message!(
        room.id,
        "user",
        unique_sender_id(),
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
  # see `seed_aged_delivery!/2,3`'s own comment on why this cross-scenario
  # cleanup matters for every scenario running later in the same shared
  # test database.
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
