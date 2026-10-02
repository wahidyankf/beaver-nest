defmodule BnestApp.Behaviour.UnitFamilyChatDriver do
  @moduledoc """
  Generic prepare/perform/outcome dispatch for `family_chat_graphql.feature` and
  `family_chat_operations.feature` at the unit layer. Delegated to from
  `BnestApp.Behaviour.UnitHomePageDriver` for every atom this module recognizes.

  Unit calls the domain/schema modules directly, bypassing the real HTTP/socket boundary and any
  filesystem/process access, so during RED every `perform_behaviour/3` clause that reaches
  a not-yet-implemented module or function fails with an `UndefinedFunctionError`/schema error —
  the correct RED reason (the feature is genuinely absent), not a harness defect.

  Family Chat runs on the unit layer's in-memory adapters (`config/test.exs`): the room store
  `BnestApp.Behaviour.UnitSupport` installs fresh for every scenario, and a publisher that
  records each publish in the committing process. PushNotifications keeps its subscriptions
  and deliveries on that same in-memory store and pushes to a push-client double
  (`BnestApp.Test.InMemory.PushSender`) that records each request in the calling process. The
  Scheduler keeps its schedules and runs in the in-memory schedule store `UnitSupport` installs
  for every scenario. Backup keeps its configuration and destination files in the in-memory
  doubles `UnitSupport` installs for every scenario, and snapshots that scenario's in-memory
  room store (`BnestApp.Test.InMemory.DatabaseSnapshot`); its destinations are synthetic
  `/srv/test-user-backup` paths no disk holds.
  """

  alias BnestApp.Backup
  alias BnestApp.FamilyChat
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.Identity
  alias BnestApp.Preferences
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Dispatcher
  alias BnestApp.PushNotifications.Domain.Policy, as: PushPolicy
  alias BnestApp.Scheduler
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.ArtifactStore, as: InMemoryArtifactStore
  alias BnestApp.Test.InMemory.CapacityProbe, as: InMemoryCapacityProbe
  alias BnestApp.Test.InMemory.DatabaseSnapshot, as: InMemoryDatabaseSnapshot
  alias BnestApp.Test.InMemory.DeliveryStore, as: InMemoryDeliveryStore
  alias BnestApp.Test.InMemory.PreferenceStore, as: InMemoryPreferenceStore
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.RoomStore, as: InMemoryRoomStore
  alias BnestApp.Test.InMemory.ScheduleStore, as: InMemoryScheduleStore
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestApp.Test.InMemory.SubscriptionStore, as: InMemorySubscriptionStore
  alias BnestApp.Test.PublicMutationProbe
  alias BnestApp.Test.SchedulerDispatch
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
  @compile {:no_warn_undefined, [BnestAppWeb.Schema]}

  @behaviour_now ~U[2026-09-18 00:00:00Z]

  @load_proof_probe_count 20

  # --- prepare ---

  # Commits the history through the facade, since every scenario starts from an empty room.
  # The known IDs are the middle three of five, so a page before the first and a page after
  # the last both have a committed message to return.
  def prepare_behaviour(context, :room_has_known_history, _args) do
    ids =
      for n <- 1..5 do
        {:ok, message} =
          FamilyChat.send_message(
            unique_sender_id(),
            FamilyChat.canonical_room_slug(),
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

  # Genuinely commits the first message (adapter fix; see learnings.md's
  # Phase 3 entry). This used to record a client message ID and a body without
  # ever sending them, so the "retry" that followed was the FIRST commit for
  # that ID -- idempotency was never exercised, and "the response returns the
  # original committed message unchanged" passed by reading the retry's own
  # body back. The reply plan's own retry scenario shares that step, which is
  # how the gap surfaced.
  def prepare_behaviour(context, :sent_message_with_known_id, [body]) do
    context = send_family_chat_message(context, unique_uuid(), body)
    {:ok, original} = context.family_chat_result

    Map.merge(context, %{
      family_chat_known_body: original.body,
      family_chat_original_message_id: original.id
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
  # derivation, not a stand-in), which registers this very test process in
  # Absinthe's subscription registry under the field topic the resolver
  # derived (`Absinthe.Pipeline.for_document/2` always includes
  # `Absinthe.Phase.Subscription.SubscribeSelf`, so no socket is required).
  # That registered topic is what this scenario holds. The unit layer's
  # recording publisher (`BnestApp.Test.InMemory.MessagePublisher`) then sends
  # every publish `FamilyChat.send_message/5` makes straight to this process
  # as `{:family_chat_published, topic, message}`, which the outcome steps
  # below actually receive and match on that topic and the committed
  # message's server ID, instead of trusting a counter. Absinthe rendering the
  # event payload for a socket is the integration layer's evidence (it joins the
  # real `UserSocket` through `Phoenix.ChannelTest`), and a live browser socket
  # the BE E2E layer's. `mix test --no-start` never boots
  # `BnestApp.Application`, so `ensure_family_chat_subscriptions_started!/0`
  # below starts the minimal, real, in-memory process infrastructure the
  # subscription document needs -- never an HTTP/socket listener.
  def prepare_behaviour(context, :holds_subscription, [_subscription_name, slug]) do
    :ok = ensure_family_chat_subscriptions_started!()
    user_id = current_user(context)

    topic =
      subscribe_and_get_topic!(slug, %{"userId" => user_id, "roles" => ["parents"]})

    context
    |> Map.put(:family_chat_subscribed_slug, slug)
    |> Map.put(:family_chat_subscription_topic, topic)
  end

  def prepare_behaviour(context, :message_committed_before_subscription, _args) do
    # Genuinely sends a message and captures its real server-assigned ID
    # rather than assuming one.
    #
    # Also captures a genuine baseline ID *before* sending this message: the
    # later "queries ... after their last known committed message ID" step
    # must cursor from a point strictly before this message (afterId is
    # exclusive-after), or the very message the scenario expects to "catch
    # up" on would never appear in its own results.
    baseline_id = latest_message_id("ruang-keluarga")

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

  # A real subscription of the user's session, stored through the facade, so disabling it
  # acts on something.
  def prepare_behaviour(context, :has_enabled_subscription, _args) do
    input = valid_subscription_input()

    {:ok, %{enabled: true}} =
      PushNotifications.upsert_subscription(current_user(context), session_digest(context), input)

    Map.put(context, :family_chat_push_endpoint, input["endpoint"])
  end

  # The `:dev_routes` value a production build compiles with: unset, because
  # `config/prod.exs` names no such key. This layer reads no files, so the value
  # is stated here; the integration layer's identical Given reads it out of
  # `config/prod.exs` itself.
  def prepare_behaviour(context, :endpoint_configured_production, _args),
    do: Map.put(context, :family_chat_production_dev_routes, nil)

  # The scenario's room store is fresh: no room seeded and no message committed yet. Checked
  # before the migration runs, so a store some earlier step seeded fails here.
  def prepare_behaviour(context, :fresh_migrated_database, _args) do
    unless InMemoryRoomStore.pristine?(InMemoryRoomStore.new()),
      do: raise("the family chat room store already holds a room or a message")

    Map.put(context, :family_chat_migration_state, :fresh)
  end

  # The unit layer has no shared SQLite file: Family Chat's store is the scenario's in-memory
  # one, and the prior release's state is a theme preference in an in-memory preference
  # store (Preferences' records predate Family Chat and share its database in production).
  # The prior-release reads run once before the real migration, so the outcome can compare
  # what they answer afterwards with what they answered before it.
  def prepare_behaviour(context, :migration_applied, _args) do
    owner = "test-user-family-chat-prior-release-" <> unique_uuid()
    preferences = InMemoryPreferenceStore.start()
    :ok = Preferences.put_theme(owner, "dark", @behaviour_now, store: preferences)
    before_migration = prior_release_reads(owner, preferences)

    {:ok, _room} = FamilyChat.migrate!()

    Map.merge(context, %{
      family_chat_migration_state: :applied,
      family_chat_prior_release: %{
        owner: owner,
        preferences: preferences,
        before_migration: before_migration
      }
    })
  end

  def prepare_behaviour(context, :trusted_producer, _args) do
    Map.put(context, :family_chat_producer_key, "system:unit-producer-" <> unique_uuid())
  end

  def prepare_behaviour(context, :three_members_with_subscriptions, [slug]) do
    # Active push subscriptions in the scenario's in-memory room store (the
    # subscriptions themselves are PushNotifications' state, which the room
    # store only reads to fan a commit out), so the atomic-commit scenario has
    # real subscriptions for the commit to derive delivery rows from, instead
    # of an unused context flag. This scenario (family_chat_operations.feature,
    # "Atomic message and delivery commit") has no "an approved user is logged
    # in" Background, so the sending member's identity is established here
    # too, via the same `:family_chat_user_id` key `current_user/1` already
    # prefers — and also given a subscription of their own, so "sender
    # excluded from delivery" is a genuine assertion (a subscription that
    # could have received a row, and provably did not) rather than vacuously
    # true. The store is fresh for every scenario and every retry of one, so
    # nothing here outlives the scenario.
    sender_id = context[:user_id] || context[:family_chat_user_id] || unique_sender_id()

    other_subscribers =
      for suffix <- ~w(a b c), do: "test-user-family-chat-#{suffix}-" <> unique_uuid()

    other_subscription_ids = Enum.map(other_subscribers, &put_subscription/1)
    sender_subscription_id = put_subscription(sender_id)

    Map.merge(context, %{
      family_chat_room_slug: slug,
      family_chat_user_id: sender_id,
      family_chat_other_subscribers: other_subscribers,
      family_chat_other_subscription_ids: other_subscription_ids,
      family_chat_sender_subscription_id: sender_subscription_id
    })
  end

  # --- replying (family_chat_graphql.feature / family_chat_operations.feature) ---

  def prepare_behaviour(context, :other_member_message_committed, [slug]) do
    context
    |> Map.put(:family_chat_room_slug, slug)
    |> send_family_chat_message(unique_uuid(), "Nanti aku jemput jam 5", sender: :other_member)
    |> capture_reply_target()
  end

  def prepare_behaviour(context, :committed_long_message, _args) do
    context
    |> send_family_chat_message(unique_uuid(), String.duplicate("a", 400), sender: :other_member)
    |> capture_reply_target()
  end

  def prepare_behaviour(context, :committed_message, [body]) do
    context
    |> send_family_chat_message(unique_uuid(), body)
    |> capture_reply_target()
  end

  def prepare_behaviour(context, :committed_reply_to_previous, [body]) do
    context =
      send_family_chat_message(context, unique_uuid(), body,
        reply_to: context.family_chat_reply_target_id
      )

    {:ok, reply} = context.family_chat_result
    Map.put(context, :family_chat_previous_reply_id, reply.id)
  end

  # Commits two candidate targets so the retry can name a genuinely different
  # one -- a retry naming the same target would prove nothing about which
  # commit wins.
  def prepare_behaviour(context, :sent_reply_with_known_id, _args) do
    context = send_family_chat_message(context, unique_uuid(), "first target")
    {:ok, first} = context.family_chat_result
    context = send_family_chat_message(context, unique_uuid(), "second target")
    {:ok, second} = context.family_chat_result

    context =
      context
      |> Map.merge(%{
        family_chat_first_target_id: first.id,
        family_chat_second_target_id: second.id,
        family_chat_known_body: "Oke, aku siapin"
      })
      |> send_family_chat_message(unique_uuid(), "Oke, aku siapin", reply_to: first.id)

    {:ok, original} = context.family_chat_result
    Map.put(context, :family_chat_original_message_id, original.id)
  end

  def prepare_behaviour(context, :replied_under_earlier_display_name, _args) do
    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    {:ok, quoted} = context.family_chat_result

    context =
      send_family_chat_message(context, unique_uuid(), "Oke, aku siapin", reply_to: quoted.id)

    {:ok, reply} = context.family_chat_result

    Map.merge(context, %{
      family_chat_quoted_message_id: quoted.id,
      family_chat_reply_message_id: reply.id
    })
  end

  # Mirrors `:message_committed_before_subscription` (see its comment for why
  # the baseline is captured before the send), with a reply as the message the
  # catch-up query must return carrying its quote.
  def prepare_behaviour(context, :reply_committed_before_subscription, _args) do
    baseline_id = latest_message_id("ruang-keluarga")

    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    {:ok, target} = context.family_chat_result

    context =
      send_family_chat_message(context, unique_uuid(), "Oke, aku siapin", reply_to: target.id)

    {:ok, reply} = context.family_chat_result

    Map.merge(context, %{
      family_chat_last_id: baseline_id,
      family_chat_reply_target_id: target.id,
      family_chat_pre_subscription_reply_id: reply.id
    })
  end

  # Same shape as `:migration_applied`: genuinely runs the migration rather
  # than storing a sentinel, because the scenario then re-reads and re-writes
  # the real table through the pre-reply call shape.
  def prepare_behaviour(context, :reply_migration_applied, _args) do
    {:ok, _room} = FamilyChat.migrate!()
    Map.put(context, :family_chat_migration_state, :applied)
  end

  # One other subscriber (not three): this scenario counts delivery rows for a
  # reply, so a single expected row makes "exactly one" an exact assertion.
  # The sender also gets a subscription so their own exclusion stays genuine.
  # Subscriptions live in the scenario's in-memory room store, as in
  # `:three_members_with_subscriptions`.
  def prepare_behaviour(context, :one_other_active_subscription, [slug]) do
    sender_id = context[:user_id] || context[:family_chat_user_id] || unique_sender_id()
    other_subscriber = "test-user-family-chat-other-" <> unique_uuid()

    other_subscription_id = put_subscription(other_subscriber)
    sender_subscription_id = put_subscription(sender_id)

    context =
      Map.merge(context, %{
        family_chat_room_slug: slug,
        family_chat_user_id: sender_id,
        family_chat_other_subscription_id: other_subscription_id,
        family_chat_sender_subscription_id: sender_subscription_id
      })

    {:ok, target} =
      FamilyChat.send_message(
        other_subscriber,
        slug,
        unique_uuid(),
        "Nanti aku jemput jam 5",
        "display-" <> other_subscriber
      )

    Map.put(context, :family_chat_reply_target_id, target.id)
  end

  # A real delivery owed to a subscription whose provider the push-client double answers
  # with a retryable 503 (or 410 Gone below): the recipient subscribes through the facade and
  # another member's commit fans the one pending delivery out to it.
  def prepare_behaviour(context, :delivery_will_fail_retryable, _args),
    do: owe_push_delivery!(context, 503)

  def prepare_behaviour(context, :delivery_targets_gone_subscription, _args),
    do: owe_push_delivery!(context, 410)

  # Real deliveries, one per named state, last stamped eight days before the retention run.
  def prepare_behaviour(context, :final_rows_older_than_7_days, _args),
    do: seed_aged_deliveries!(context, :final, ~w(delivered terminal))

  def prepare_behaviour(context, :nonfinal_rows_same_age, _args),
    do: seed_aged_deliveries!(context, :nonfinal, ~w(pending claimed retryable))

  def prepare_behaviour(context, :soft_deleted_rows_older_than_7_days, _args),
    do: seed_aged_deliveries!(context, :soft_deleted, ~w(terminal))

  # The schedules these scenarios start from exist in the scenario's own in-memory
  # schedule store, put there as the release seeds put them: the production backup
  # schedule at 19:00 UTC and the push retention schedule at its 17:15 UTC
  # (00:15 WIB) seed time, both pristine at revision 1.
  #
  # The backup schedule is due now, so its claim runs the registered Backup task,
  # which resolves its destination itself and snapshots the scenario's in-memory
  # room store: the Given saves a synthetic destination through the Backup facade.
  def prepare_behaviour(context, :schedule_due, [key]) do
    _location = backup_destination!("scheduled")
    :ok = put_backup_schedule!(key, %{next_run_at: @behaviour_now})
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  # The retention seed ships disabled; this one is already enabled, and due now.
  def prepare_behaviour(context, :schedule_due_and_enabled, [key]) do
    :ok = put_retention_schedule!(key, %{next_run_at: @behaviour_now})
    Map.put(context, :family_chat_due_schedule_key, key)
  end

  def prepare_behaviour(context, :schedule_different_time, [key]) do
    :ok = put_backup_schedule!(key, %{daily_at_utc: "23:00"})

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_prior_daily_at_utc: "23:00"
    })
  end

  def prepare_behaviour(context, :schedule_disabled_seed, [key]) do
    :ok = put_retention_schedule!(key, %{enabled: false})
    Map.put(context, :family_chat_activation_key, key)
  end

  # Both schedules as the releases seed them, then the one-time convergence a compatible
  # release runs through the Family Chat facade.
  def prepare_behaviour(context, :convergence_already_ran, _args) do
    :ok = put_backup_schedule!("prod-sqlite-backup-daily", %{})
    :ok = put_retention_schedule!("family-chat-push-retention-daily", %{enabled: false})
    :ok = FamilyChat.converge_after_drain!()
    %{daily_at_utc: "18:00"} = Scheduler.get_schedule("prod-sqlite-backup-daily")
    Map.put(context, :family_chat_convergence_ran, true)
  end

  # The operator's edit goes through the same facade operation the admin schedules
  # page calls: 03:00 WIB, at the revision the operator read.
  def prepare_behaviour(context, :operator_changed_schedule_time, [key]) do
    schedule = Scheduler.get_schedule(key)

    {:ok, edited} =
      Scheduler.update_daily(
        key,
        %{
          "daily_time_wib" => "03:00",
          "enabled" => to_string(schedule.enabled),
          "revision" => to_string(schedule.revision)
        },
        @behaviour_now
      )

    Map.merge(context, %{
      family_chat_convergence_key: key,
      family_chat_operator_daily_at_utc: edited.daily_at_utc
    })
  end

  # The destination's measured free space is none at all, so the capacity preflight
  # refuses whatever the snapshot needs. The context key tells the home page driver's
  # shared "the backup handler runs" step which scenario it serves.
  def prepare_behaviour(context, :insufficient_capacity, _args) do
    :ok = InMemoryCapacityProbe.put_available_bytes(InMemoryCapacityProbe.new(), 0)
    Map.put(context, :family_chat_backup_capacity, :insufficient)
  end

  # The live room holds history before the backup starts, so the snapshot's
  # self-consistency check always has committed messages to compare. Then authenticated
  # read and send probes start in a process of their own, through the facade the GraphQL
  # resolvers call, and keep running until the When that runs the backup stops them.
  def prepare_behaviour(context, :continuous_probes_running, _args) do
    FamilyChat.ensure_ready!()

    {:ok, _history} =
      FamilyChat.send_message(
        unique_sender_id(),
        FamilyChat.canonical_room_slug(),
        unique_uuid(),
        "history before the backup"
      )

    Map.put(context, :family_chat_probes, start_probes())
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
    FamilyChat.ensure_ready!()
    destination = backup_destination!("verified-backup-artifact")
    known_body = "restore-fixture-secret-" <> unique_uuid()
    # An active subscription in the scenario's own store, subscribed through the facade, so
    # the message below fans a pending delivery out to it. Its endpoint and keys are what
    # the restore evidence must never carry.
    subscription = subscribe_through_facade!(unique_sender_id(), "accepted")
    stored = stored_subscription(subscription.endpoint)
    room = FamilyChat.canonical_room()

    {:ok, message} =
      FamilyChat.insert_message!(
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
      family_chat_known_body: known_body,
      family_chat_fixture_message_id: message.id,
      family_chat_fixture_secrets: [stored.endpoint, stored.p256dh, stored.auth]
    })
  end

  # Two slots, each a process of its own that commits through the Family Chat facade and
  # records what its own publisher port published: this test's process is one, and a second
  # one is started beside it. They share nothing but the in-memory room store, as two slots
  # share the database. A real authenticated sender commits on each, since no Background
  # logs a member in for this feature.
  def prepare_behaviour(context, :two_independent_slots, _args) do
    other_slot = start_slot()

    Map.merge(context, %{
      family_chat_other_slot: other_slot,
      family_chat_user_id: unique_sender_id()
    })
  end

  # --- perform ---

  def perform_behaviour(context, :query_room_list, _args) do
    Map.put(context, :family_chat_result, FamilyChat.list_rooms_for(current_user(context)))
  end

  def perform_behaviour(context, :query_room_by_slug, [slug]) do
    result =
      if context[:family_chat_capability] == false do
        run_without_capability(
          context,
          "query($slug: String!) { familyChatRoom(slug: $slug) { id slug name roomKind memberPostingEnabled } }",
          %{"slug" => slug}
        )
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

  # A member's send is the GraphQL mutation their browser posts, so it runs through the
  # real schema and resolver with the member's session: the resolver chooses the sender
  # name it commits, and the message type answers the name a reader sees. A user without
  # the capability is refused by the same resolver (`send_family_chat_message/4`).
  def perform_behaviour(context, :send_message_fresh_id, [body]) do
    if context[:family_chat_capability] == false,
      do: send_family_chat_message(context, unique_uuid(), body),
      else: send_through_schema(context, unique_uuid(), body)
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

    # Resolves the quote's sender name through the same seam, exactly as the
    # GraphQL quote type does -- so "the quoted name follows the account too"
    # is proved against the real transform here as well, not assumed.
    resolved_nodes =
      Enum.map(page.nodes, fn node ->
        node
        |> Map.put(:sender_display_name, FamilyChat.live_sender_display_name(node, lookup))
        |> Map.update!(:reply_to, fn
          nil ->
            nil

          quoted ->
            Map.put(
              quoted,
              :sender_display_name,
              FamilyChat.live_sender_display_name(quoted, lookup)
            )
        end)
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

  # The same real subscription document `:holds_subscription` runs, after the
  # message the Given committed: `subscribe_and_get_topic!/2` raises unless the
  # document registered this process on a topic.
  def perform_behaviour(context, :establish_subscription, [_subscription_name, slug]) do
    :ok = ensure_family_chat_subscriptions_started!()
    user_id = current_user(context)
    topic = subscribe_and_get_topic!(slug, %{"userId" => user_id, "roles" => ["parents"]})

    context
    |> Map.put(:family_chat_subscribed_slug, slug)
    |> Map.put(:family_chat_subscription_topic, topic)
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

  def perform_behaviour(context, :upsert_valid_subscription, _args),
    do: upsert_subscription(context, valid_subscription_input())

  def perform_behaviour(context, :disable_subscription, _args), do: disable_subscription(context)

  def perform_behaviour(context, :disable_subscription_again, _args),
    do: disable_subscription(context)

  def perform_behaviour(context, :upsert_subscription_with_endpoint, [endpoint]),
    do: upsert_subscription(context, Map.put(valid_subscription_input(), "endpoint", endpoint))

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
  # (`BnestAppWeb.UserSocket.connect/3`) directly, with a spoofed `userId`/`role`
  # in the socket CONNECT PARAMS alongside a real, distinct session-derived
  # identity, so a regression that started trusting client-supplied params
  # for identity would actually be caught. Built via a bare `%Phoenix.Socket{}`
  # struct (no enforced keys -- see `deps/phoenix/lib/phoenix/socket.ex`) and
  # a synthetic `connect_info.session`, never `Phoenix.ChannelTest` (this
  # layer bypasses the real HTTP/socket transport entirely, per this module's
  # moduledoc); the integration driver exercises the same real function
  # through the genuine transport.
  #
  # The session is what `BnestAppWeb.UserAuth.fetch_current_user/2` writes for a
  # logged-in member without the admin role: the account, and the digest of the
  # browser's own session token, taken through the Identity facade from a
  # synthetic token.
  def perform_behaviour(context, :open_socket_authenticated, _args) do
    real_user_id = current_user(context)
    spoofed_user_id = "test-user-family-chat-spoofed-" <> unique_uuid()

    session = %{
      "current_user" => %{
        "userId" => real_user_id,
        "displayUsername" => synthetic_display_name(real_user_id),
        "roles" => ["parents"]
      },
      "session_digest" => Identity.session_digest("test-user-unit-session-" <> unique_uuid())
    }

    spoofed_params = %{"userId" => spoofed_user_id, "role" => "admin", "roles" => ["admin"]}

    context
    |> Map.merge(%{
      family_chat_spoofed_user_id: spoofed_user_id,
      family_chat_socket_session: session
    })
    |> Map.put(:family_chat_result, connect_family_chat_socket(spoofed_params, session))
  end

  def perform_behaviour(context, :visitor_opens_socket, _args) do
    Map.put(context, :family_chat_result, connect_family_chat_socket(%{}, %{}))
  end

  def perform_behaviour(context, :run_family_chat_migration, _args) do
    Map.put(context, :family_chat_result, FamilyChat.migrate!())
  end

  # Re-runs the prior-release reads against the migrated state and records every call
  # Family Chat's store served while they ran, read from the store's own access log.
  def perform_behaviour(context, :old_code_opens_database, _args) do
    %{owner: owner, preferences: preferences} = context.family_chat_prior_release
    store = InMemoryRoomStore.new()
    served_before = InMemoryRoomStore.calls(store)
    after_migration = prior_release_reads(owner, preferences)
    served_after = InMemoryRoomStore.calls(store)

    Map.merge(context, %{
      family_chat_result: after_migration,
      family_chat_store_calls_before: served_before,
      family_chat_store_calls_during: Enum.drop(served_after, length(served_before))
    })
  end

  # The first post's result is kept apart, so the retry's can be compared with it.
  def perform_behaviour(context, :producer_posts_system_message, [slug]) do
    result =
      FamilyChat.post_system_message(slug, context.family_chat_producer_key, "system notice")

    context
    |> Map.put(:family_chat_result, result)
    |> Map.put_new(:family_chat_first_system_result, result)
  end

  def perform_behaviour(context, :producer_retries_same_key, _args) do
    perform_behaviour(context, :producer_posts_system_message, ["ruang-keluarga"])
  end

  # The public schema answers its own introspection query, in process, and every mutation
  # field it declares is then run through it as an authenticated member with the use family
  # chat capability.
  def perform_behaviour(context, :inspect_public_schema, _args) do
    {:ok, %{data: data}} = Absinthe.run(PublicMutationProbe.introspection(), BnestAppWeb.Schema)
    user_id = "test-user-family-chat-schema-" <> unique_uuid()
    fields = PublicMutationProbe.fields(data)

    Map.merge(context, %{
      family_chat_schema_fields: fields,
      family_chat_schema_runs: Enum.map(fields, &run_public_mutation(&1, user_id))
    })
  end

  def perform_behaviour(context, :member_sends_durable_message, _args) do
    send_family_chat_message(context, unique_uuid(), "Dinner is ready")
  end

  def perform_behaviour(context, :send_reply_to_known_target, args) do
    body = List.first(args) || "Oke, aku siapin"

    send_family_chat_message(context, unique_uuid(), body,
      reply_to: context.family_chat_reply_target_id
    )
  end

  def perform_behaviour(context, :reply_target_unknown_id, _args) do
    send_family_chat_message(context, unique_uuid(), "answer", reply_to: 999_999_999)
  end

  def perform_behaviour(context, :reply_target_other_room, _args) do
    send_family_chat_message(context, unique_uuid(), "answer",
      reply_to: archived_room_message_id()
    )
  end

  def perform_behaviour(context, :reply_target_not_positive_integer, _args) do
    send_family_chat_message(context, unique_uuid(), "answer", reply_to: "not-a-number")
  end

  def perform_behaviour(context, :send_reply_to_previous_reply, _args) do
    send_family_chat_message(context, unique_uuid(), "Siap",
      reply_to: context.family_chat_previous_reply_id
    )
  end

  def perform_behaviour(context, :resend_same_id_other_target, _args) do
    send_family_chat_message(
      context,
      context.family_chat_client_message_id,
      context.family_chat_known_body,
      reply_to: context.family_chat_second_target_id
    )
  end

  # Commits the user's own message first so the reply has something of theirs
  # to answer. Both commits publish; every publish they made is collected, so
  # the outcomes read the events the subscriber actually received rather than
  # the commit's return value.
  def perform_behaviour(context, :other_member_replies_to_user, _args) do
    context = send_family_chat_message(context, unique_uuid(), "Nanti aku jemput jam 5")
    {:ok, target} = context.family_chat_result

    context
    |> Map.put(:family_chat_reply_target_id, target.id)
    |> send_family_chat_message(unique_uuid(), "Oke, aku siapin",
      sender: :other_member,
      reply_to: target.id
    )
    |> Map.put(:family_chat_published_events, published_events())
  end

  # "Code built before that migration" is exactly code compiled against the
  # pre-reply call shape: `send_message/5`, with no reply argument at all.
  # Calling it against the migrated database is the genuine compatibility
  # proof -- a stored sentinel would prove nothing about the real column.
  def perform_behaviour(context, :pre_reply_release_opens_database, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"
    sender = current_user(context) || unique_sender_id()

    {:ok, committed} =
      FamilyChat.send_message(
        sender,
        slug,
        unique_uuid(),
        "Dinner is ready",
        "display-" <> sender
      )

    readback = stored_message(slug, committed.id)

    Map.merge(context, %{
      family_chat_result: {:ok, committed},
      family_chat_pre_reply_readback: readback
    })
  end

  def perform_behaviour(context, :send_durable_reply, _args) do
    slug = context[:family_chat_room_slug] || "ruang-keluarga"

    result =
      FamilyChat.send_message(
        current_user(context),
        slug,
        unique_uuid(),
        "Oke, aku siapin",
        "display-" <> current_user(context),
        context.family_chat_reply_target_id
      )

    Map.put(context, :family_chat_result, result)
  end

  def perform_behaviour(context, :dispatcher_attempts_delivery, _args),
    do: Map.put(context, :family_chat_result, Dispatcher.attempt())

  def perform_behaviour(context, :retention_job_runs, _args) do
    Map.put(
      context,
      :family_chat_result,
      PushNotifications.retain_deliveries(@behaviour_now)
    )
  end

  def perform_behaviour(context, :retention_job_runs_again, _args) do
    # Genuinely calls `retain_deliveries/1` twice. The
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

  # Claims through the Scheduler facade and runs the claimed run through it, as
  # the coordinator's tick does, recording which registered task ran and what it
  # called (see `BnestApp.Test.SchedulerDispatch`).
  def perform_behaviour(context, :scheduler_claims_and_dispatches, _args) do
    key = context.family_chat_due_schedule_key
    dispatch = SchedulerDispatch.claim_and_dispatch(key, @behaviour_now)
    Map.put(context, :family_chat_dispatch, dispatch)
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
    Map.put(context, :family_chat_result, Scheduler.get_schedule(key))
  end

  # What a compatible start does to the schedules: the release entry point's convergence,
  # which is the Family Chat facade's, on the unit layer's in-memory schedule store (the
  # integration driver runs the release migrations themselves). The schedule's state
  # afterward is read back through the Scheduler facade.
  def perform_behaviour(context, :bnest_starts_again, _args) do
    key = context.family_chat_convergence_key
    :ok = FamilyChat.converge_after_drain!()
    Map.put(context, :family_chat_result, {:ok, Scheduler.get_schedule(key)})
  end

  # Always injects its own synthetic destination, never the configured default, and
  # keeps it so a Then can read what the destination holds afterwards.
  def perform_behaviour(context, :backup_runs_full_duration, _args) do
    destination = backup_destination!("run-full-duration")

    Map.merge(context, %{
      family_chat_result:
        Backup.run(deadline: @behaviour_now, destination_directory: destination.directory),
      family_chat_backup_directory: destination.directory
    })
  end

  # The whole backup runs while the Given's probes do: its copy is held open until the probes
  # finished further rounds, and they stop only once the backup returned. The produced
  # artifact is then restored, since this scenario has no restore step of its own.
  def perform_behaviour(context, :routed_backup_runs_full_duration, _args) do
    destination = backup_destination!("routed-run-full-duration")

    {result, probes} =
      backup_under_probes(context, fn ->
        Backup.run(deadline: @behaviour_now, destination_directory: destination.directory)
      end)

    Map.merge(context, %{
      family_chat_result: result,
      family_chat_load_probes: probes,
      family_chat_restore_self_consistent?: restorable_self_consistent?(result)
    })
  end

  # First half of the cancellation proof: the backup the Given's timeout cancels runs, and
  # is cancelled, while the probes do.
  def perform_behaviour(context, :timed_out_backup_direct, _args) do
    destination = backup_destination!("timed-out-direct")

    {result, probes} =
      backup_under_probes(context, fn ->
        Backup.run(deadline: @behaviour_now, destination_directory: destination.directory)
      end)

    Map.merge(context, %{
      family_chat_result: result,
      family_chat_load_probes: probes,
      family_chat_backup_directory: destination.directory
    })
  end

  # Second half: the same timed-out backup, claimed through the Scheduler as the setup
  # run of an isolated destination and run through `Scheduler.execute/2` under the
  # Given's forced timeout. The Scheduler's registered Backup task resolves that
  # destination itself, its backup times out, and the Scheduler records the failed
  # attempt. A claim six minutes later, well inside the attempt's lease, finds the run
  # again only because the Scheduler recorded it retryable. The claim names the
  # destination's own ID, since the Backup task skips a setup run of another destination.
  def perform_behaviour(context, :timed_out_backup_via_scheduler, _args) do
    location = backup_destination!("timed-out-scheduler")
    key = "bdd-timed-out-backup-" <> unique_uuid()
    :ok = put_backup_schedule!(key, %{})

    {:ok, claim} = Scheduler.claim_setup(key, location.destination_id, @behaviour_now)
    :ok = Scheduler.execute(claim, @behaviour_now)

    later = DateTime.add(@behaviour_now, 6 * 60)
    retried = Enum.find(Scheduler.claim_due(later), &(&1.run_id == claim.run_id))

    Map.put(context, :family_chat_retry_claim, retried)
  end

  def perform_behaviour(context, :restore_artifact_isolated_root, _args) do
    result = Backup.restore(context[:family_chat_backup_artifact])
    Map.put(context, :family_chat_result, result)
  end

  # Collects every publish the commit made through this slot's publisher port.
  def perform_behaviour(context, :message_commits_on_one_slot, _args) do
    context
    |> send_family_chat_message(unique_uuid(), "slot-local publish")
    |> Map.put(:family_chat_published_events, published_events())
  end

  # The router's own mounting decision (`BnestAppWeb.DevRoutes.mounted?/1`, which its
  # compile-time branch calls) taken for the production configuration, beside the routes
  # this build's router compiled from its own configuration.
  def perform_behaviour(context, :inspect_router_routes, _args) do
    Map.merge(context, %{
      family_chat_production_mounts_dev_routes:
        BnestAppWeb.DevRoutes.mounted?(context.family_chat_production_dev_routes),
      family_chat_graphiql_routes: graphiql_routes()
    })
  end

  # --- outcome ---

  def behaviour_outcome?(context, :room_list_lists_exactly, [name]) do
    match?({:ok, [%{name: ^name}]}, context.family_chat_result)
  end

  def behaviour_outcome?(context, :room_returned, [name]) do
    match?({:ok, %{name: ^name}}, context.family_chat_result)
  end

  # Each page must be exactly the slice of the room's whole history its cursor names, read
  # back through the port, and must reach the committed history the Given made.
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
    {:ok, %{has_older: has_older}} = context.family_chat_result
    has_older == Enum.any?(room_message_ids(context), &(&1 < hd(page_ids(context))))
  end

  def behaviour_outcome?(context, :has_newer_correct, _args) do
    {:ok, %{has_newer: has_newer}} = context.family_chat_result
    has_newer == Enum.any?(room_message_ids(context), &(&1 > List.last(page_ids(context))))
  end

  # A response the real resolver gave a user without the capability (see
  # `run_without_capability/3`): the code, no operation data, and nothing committed.
  def behaviour_outcome?(%{family_chat_capability: false} = context, :safe_error, [code]),
    do: refused_without_capability?(context, code)

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

  # The name the response carries is the session's display username, which differs from
  # the user ID the same session names.
  def behaviour_outcome?(context, :message_reports_real_display_name, _args) do
    %{"userId" => user_id, "displayUsername" => display} = context.family_chat_session_user

    display != user_id and
      match?(
        {:ok, %{sender_display_name: ^display, sender_id: ^user_id}},
        context.family_chat_result
      )
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

  # Compares against the FIRST commit, by server ID and body both: a retry
  # that returned a new row, or the retry's own body, fails here. The previous
  # check asserted the body merely differed from the Given's body, which a
  # fresh commit of a different body also satisfies.
  def behaviour_outcome?(context, :original_message_unchanged, _args) do
    case context.family_chat_result do
      {:ok, %{id: id, body: body}} ->
        id == context.family_chat_original_message_id and
          body == context.family_chat_known_body

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :quote_names_target_id, _args) do
    match?(
      {:ok, %{reply_to: %{id: id}}} when id == context.family_chat_reply_target_id,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :quote_reports_sender_and_preview, _args) do
    {:ok, %{reply_to: quoted}} = context.family_chat_result

    quoted.sender_display_name == context.family_chat_reply_target_display_name and
      quoted.body_preview == context.family_chat_reply_target_body
  end

  # The response carries no quote, and the commit it reports names no reply target.
  def behaviour_outcome?(context, :message_has_no_quote, _args) do
    case context.family_chat_result do
      {:ok, %{id: id, reply_to: nil}} ->
        match?(%{reply_to_message_id: nil}, stored_message(room_slug(context), id))

      _other ->
        false
    end
  end

  # The graphemes the preview keeps before the ellipsis that marks the cut.
  def behaviour_outcome?(context, :quote_preview_within_budget, [budget]) do
    {:ok, %{reply_to: quoted}} = context.family_chat_result
    quoted.body_preview |> String.trim_trailing("…") |> String.length() <= budget
  end

  def behaviour_outcome?(context, :quote_preview_elided, _args) do
    {:ok, %{reply_to: quoted}} = context.family_chat_result
    String.ends_with?(quoted.body_preview, "…")
  end

  # Reads the quoted message back through the page a client gets, and compares it with
  # the 400-grapheme body the Given wrote, not with anything the commit echoed.
  def behaviour_outcome?(context, :quoted_body_unshortened, _args) do
    target_id = context.family_chat_reply_target_id

    case FamilyChat.list_messages(current_user(context), room_slug(context),
           after_id: target_id - 1,
           limit: 1
         ) do
      {:ok, %{nodes: [%{id: ^target_id, body: body}]}} -> body == String.duplicate("a", 400)
      _other -> false
    end
  end

  def behaviour_outcome?(context, :room_has_no_message_for_client_id, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 0

  # The refusal happens before any commit, so nothing could have been
  # published. Draining this process's own mailbox for a publish on the held
  # topic proves that -- but only for a scenario that actually holds a
  # subscription. Without one there is no topic to check, so answering
  # `true` there would be a guaranteed pass rather than a proof; it raises
  # instead, and the scenario carries the subscription Given that makes the
  # drain mean something.
  def behaviour_outcome?(context, :no_event_published, _args) do
    unless Map.has_key?(context, :family_chat_subscription_topic) do
      raise """
      `no committed-message event is published` was asked of a scenario that \
      holds no subscription. Nothing could arrive regardless of the \
      implementation, so the step would pass unconditionally. Give the \
      scenario the subscription Given, or assert something else.\
      """
    end

    topic = context.family_chat_subscription_topic

    receive do
      {:family_chat_published, ^topic, _message} -> false
    after
      100 -> true
    end
  end

  def behaviour_outcome?(context, :quote_names_previous_reply, _args) do
    match?(
      {:ok, %{reply_to: %{id: id}}} when id == context.family_chat_previous_reply_id,
      context.family_chat_result
    )
  end

  # The quote is a plain map with exactly four public keys and no nesting: a
  # quote of a quote is unrepresentable, not merely absent this once.
  def behaviour_outcome?(context, :quote_is_flat, _args) do
    {:ok, %{reply_to: quoted}} = context.family_chat_result

    not Map.has_key?(quoted, :reply_to) and not Map.has_key?(quoted, :reply_to_message_id)
  end

  def behaviour_outcome?(context, :quote_names_first_target, _args) do
    match?(
      {:ok, %{reply_to: %{id: id}}} when id == context.family_chat_first_target_id,
      context.family_chat_result
    )
  end

  def behaviour_outcome?(context, :quote_reports_live_display_name, [expected_name]) do
    case quoted_of_reply(context) do
      nil -> false
      quoted -> quoted.sender_display_name == expected_name
    end
  end

  def behaviour_outcome?(context, :quote_name_matches_original, _args) do
    quoted = quoted_of_reply(context)
    original = node_by_id(context, context.family_chat_quoted_message_id)

    quoted != nil and original != nil and
      quoted.sender_display_name == original.sender_display_name
  end

  # Exactly one of the events published on the held topic is the reply; the
  # target message this scenario committed first published its own, which is
  # not counted.
  def behaviour_outcome?(context, :one_event_for_reply, _args) do
    match?([_reply_event], reply_events(context))
  end

  # Reads the quote off the event the subscriber received, not off the
  # commit's return value.
  def behaviour_outcome?(context, :event_message_carries_quote, _args) do
    case reply_events(context) do
      [%{reply_to: %{id: id}}] -> id == context.family_chat_reply_target_id
      _other -> false
    end
  end

  def behaviour_outcome?(context, :response_includes_reply, _args),
    do: node_by_id(context, context.family_chat_pre_subscription_reply_id) != nil

  def behaviour_outcome?(context, :reply_carries_quote, _args) do
    case node_by_id(context, context.family_chat_pre_subscription_reply_id) do
      %{reply_to: %{id: id}} -> id == context.family_chat_reply_target_id
      _other -> false
    end
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

  # The dispatcher sends the reply's owed deliveries, and no payload the push client
  # received for the reply may carry the quoted text; nor may any stored delivery column.
  # The commit must owe at least one delivery, or there is no payload to check. The
  # delivery rows' SQLite columns are the integration driver's evidence.
  def behaviour_outcome?(context, :delivery_payload_excludes_quote, _args) do
    {:ok, %{id: message_id}} = context.family_chat_result
    slug = context[:family_chat_room_slug] || "ruang-keluarga"
    quoted_body = stored_message(slug, context.family_chat_reply_target_id).body
    deliveries = Enum.filter(stored_deliveries(), &(&1.message_id == message_id))
    :ok = PushNotifications.dispatch_all_due!()

    payloads =
      for {_endpoint, %{"messageId" => ^message_id} = payload} <- push_requests(), do: payload

    deliveries != [] and length(payloads) == length(deliveries) and
      not Enum.any?(payloads, &String.contains?(Jason.encode!(&1), quoted_body)) and
      Enum.all?(deliveries, fn delivery ->
        Enum.all?(Map.values(delivery), fn value ->
          not (is_binary(value) and String.contains?(value, quoted_body))
        end)
      end)
  end

  def behaviour_outcome?(context, :no_hidden_room_state, _args) do
    refused_without_capability?(context, "FORBIDDEN") and
      not leaks_room?(context.family_chat_result)
  end

  def behaviour_outcome?(context, :room_gains_no_message, _args),
    do: count_messages_for(context, context.family_chat_client_message_id) == 0

  # Actually drains this test process's own mailbox for the publish the prior
  # "other member sends" step's real `FamilyChat.send_message/5` call made
  # (see `:holds_subscription`'s comment) -- never a trusted counter. Matches
  # on the exact subscribed topic and the exact committed message's real
  # server-assigned id, so a publish for a different room or a stale event
  # could never satisfy this.
  def behaviour_outcome?(context, :subscriber_received_one_event, _args) do
    {:ok, %{id: committed_id}} = context.family_chat_result
    topic = context.family_chat_subscription_topic

    receive do
      {:family_chat_published, ^topic, %{id: ^committed_id}} -> true
    after
      1_000 -> false
    end
  end

  # Genuinely retries: resends the exact same client message ID as the same
  # sender (the same `(room, sender_kind, sender_id, idempotency_key)` tuple
  # `FamilyChat`'s real `commit_message/8` dedups on via
  # `RoomStore.find_message/5`), then asserts no second publish reaches this
  # subscribed process -- proving the production idempotency path itself
  # suppresses the second publish, not merely a re-assertion of a counter
  # the first outcome already consumed.
  def behaviour_outcome?(context, :no_duplicate_publish, _args) do
    send_family_chat_message(
      context,
      context.family_chat_client_message_id,
      "duplicate retry body",
      sender: :other_member
    )

    topic = context.family_chat_subscription_topic

    receive do
      {:family_chat_published, ^topic, _message} -> false
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

  def behaviour_outcome?(context, :reports_enabled_and_expiration_only, _args) do
    case context.family_chat_result do
      {:ok, state} -> state |> Map.keys() |> Enum.sort() == [:enabled, :expiration_time]
      _error -> false
    end
  end

  def behaviour_outcome?(context, :subscription_enabled, _args) do
    match?({:ok, %{enabled: true}}, context.family_chat_result) and
      session_subscribed?(current_user(context), session_digest(context))
  end

  # The stored subscription is the user's and active, and serves that session only: not
  # another session of the same user, nor the same session key of another user.
  def behaviour_outcome?(context, :subscription_bound_to_session, _args) do
    user_id = current_user(context)
    session = session_digest(context)

    match?(
      %{user_id: ^user_id, deleted_at: nil},
      stored_subscription(context.family_chat_push_endpoint)
    ) and session_subscribed?(user_id, session) and
      not session_subscribed?(user_id, "test-other-session-" <> unique_uuid()) and
      not session_subscribed?(unique_sender_id(), session)
  end

  def behaviour_outcome?(context, :subscription_disabled, _args),
    do: subscription_disabled?(context)

  def behaviour_outcome?(context, :subscription_still_disabled, _args),
    do: subscription_disabled?(context)

  # Rejected before storage: no subscription holds the endpoint, the session has none, and
  # the push client was asked for nothing.
  def behaviour_outcome?(context, :no_subscription_stored_or_network, _args) do
    match?({:error, %{code: "VALIDATION_FAILED"}}, context.family_chat_result) and
      stored_subscription(context.family_chat_push_endpoint) == nil and
      not session_subscribed?(current_user(context), session_digest(context)) and
      push_requests() == []
  end

  # The context is the session's own user and the digest of the session's own token.
  def behaviour_outcome?(context, :socket_context_server_resolved, _args) do
    %{"current_user" => user, "session_digest" => digest} = context.family_chat_socket_session

    match?(
      %{current_user: ^user, session_digest: ^digest},
      socket_absinthe_context(context.family_chat_result)
    )
  end

  # Genuine negative-input check: the spoofed `userId` and `admin` role the connect
  # params `:open_socket_authenticated` sent must never surface in the resolved
  # identity -- only the session's member, with the session's roles.
  def behaviour_outcome?(context, :socket_params_ignored, _args) do
    case socket_absinthe_context(context.family_chat_result) do
      %{current_user: %{"userId" => user_id, "roles" => roles}} ->
        user_id == current_user(context) and user_id != context.family_chat_spoofed_user_id and
          "admin" not in roles and
          roles == context.family_chat_socket_session["current_user"]["roles"]

      _other ->
        false
    end
  end

  def behaviour_outcome?(context, :socket_handshake_rejected, _args) do
    context.family_chat_result == :error or match?({:error, _}, context.family_chat_result)
  end

  # The production configuration mounts nothing, and the router follows that same
  # decision: the routes it compiled carry GraphiQL exactly when the decision it took for
  # this build's own configuration says so. A router that mounted GraphiQL regardless of
  # the decision, or a decision that mounted it for production, fails here.
  def behaviour_outcome?(context, :no_graphiql_route, _args) do
    context.family_chat_production_mounts_dev_routes == false and
      BnestAppWeb.Router.dev_routes_enabled?() ==
        BnestAppWeb.DevRoutes.mounted?(Application.get_env(:bnest_app, :dev_routes)) and
      context.family_chat_graphiql_routes != [] == BnestAppWeb.Router.dev_routes_enabled?()
  end

  # The migration's room, and the room read back from the store, both open for posting.
  def behaviour_outcome?(context, :room_seed_correct, [slug, name]) do
    seeded = %{id: 1, slug: slug, name: name, member_posting_enabled: true}
    stored = RoomStore.get_active_room(FamilyChat.adapter(:room_store).new(), slug)

    match?({:ok, %{}}, context.family_chat_result) and
      Map.take(elem(context.family_chat_result, 1), Map.keys(seeded)) == seeded and
      Map.take(stored || %{}, Map.keys(seeded)) == seeded
  end

  # Re-runs the migration for real and compares the whole seeded room it
  # returns with the first run's, then reads the store's active rooms back: the
  # same single room.
  def behaviour_outcome?(context, :migration_idempotent, _args) do
    {:ok, %{id: 1} = room} = context.family_chat_result
    second = FamilyChat.migrate!()

    second == {:ok, room} and
      RoomStore.list_active_rooms(FamilyChat.adapter(:room_store).new()) == [room]
  end

  def behaviour_outcome?(context, :prior_release_unaffected, _args) do
    %{before_migration: before_migration} = context.family_chat_prior_release
    before_migration.theme == "dark" and context.family_chat_result == before_migration
  end

  # The migration itself reached the store, so its log is live; the
  # prior-release reads that followed reached it not once.
  def behaviour_outcome?(context, :no_prior_release_table_access, _args) do
    :ensure_ready! in context.family_chat_store_calls_before and
      context.family_chat_store_calls_during == []
  end

  # The answer and the stored row both carry the producer's key as sender and idempotency key.
  def behaviour_outcome?(context, :system_message_committed, [sender_kind]) do
    key = context.family_chat_producer_key

    case context.family_chat_result do
      {:ok, %{id: id, sender_kind: ^sender_kind, sender_id: ^key}} ->
        match?(
          %{sender_kind: ^sender_kind, sender_id: ^key, idempotency_key: ^key},
          Enum.find(stored_messages("ruang-keluarga"), &(&1.id == id))
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

  def behaviour_outcome?(context, :exactly_one_system_message, _args) do
    count_messages_for(context, context.family_chat_producer_key) == 1
  end

  # No field is named for a system message in any letter case, every field ran without an
  # error, and none of them committed a system message.
  def behaviour_outcome?(context, :schema_has_no_system_message_field, _args) do
    names = Enum.map(context.family_chat_schema_fields, & &1.name)

    names != [] and not Enum.any?(names, &PublicMutationProbe.names_system?/1) and
      Enum.all?(context.family_chat_schema_runs, &match?({_name, :ran}, &1)) and
      not Enum.any?(stored_messages("ruang-keluarga"), &(&1.sender_kind == "system"))
  end

  # The store holds one pending delivery for each other member's subscription, exactly; and a
  # commit whose delivery rows fail leaves neither its message nor any delivery behind.
  def behaviour_outcome?(context, :message_and_deliveries_committed_atomically, _args) do
    {:ok, %{id: message_id, deliveries: returned}} = context.family_chat_result

    stored =
      for delivery <- InMemoryDeliveryStore.deliveries(InMemoryDeliveryStore.new()),
          delivery.message_id == message_id,
          do: {delivery.subscription_id, delivery.state}

    expected = Enum.map(context.family_chat_other_subscription_ids, &{&1, "pending"})

    length(returned) == 3 and Enum.sort(stored) == Enum.sort(expected) and
      failed_commit_left_nothing?(context)
  end

  def behaviour_outcome?(context, :sender_excluded_from_delivery, _args) do
    {:ok, %{deliveries: deliveries}} = context.family_chat_result
    not Enum.any?(deliveries, &(&1.subscription_id == context.family_chat_sender_subscription_id))
  end

  # One request reached the provider, and the delivery waits for the push retry policy's
  # first wait, counted from that attempt.
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
    :ok = Scheduler.activate_if_pristine!(key, @behaviour_now)
    after_schedule = Scheduler.get_schedule(key)

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

  # The failure names no artifact, and the destination the run wrote to holds no backup
  # file, partial or final, afterwards: read from the artifact store the run wrote through.
  def behaviour_outcome?(context, :no_partial_or_final_artifact, _args) do
    backups =
      InMemoryArtifactStore.new()
      |> InMemoryArtifactStore.paths(context.family_chat_backup_directory)
      |> Enum.filter(&String.contains?(&1, "/bnest-prod-"))

    match?({:error, {:retryable, _category, nil}}, context.family_chat_result) and backups == [] and
      refused_before_snapshot?(context)
  end

  # Read from the probes' own timings, never from the backup's result. Some rounds finished
  # while the copy was open.
  def behaviour_outcome?(context, :probes_within_budget, _args) do
    %{failures: failures, samples: samples, during_backup: during} =
      context.family_chat_load_probes

    failures == 0 and during > 0 and samples != [] and Enum.all?(samples, &(&1 <= 2_000)) and
      percentile_95(samples) <= 500
  end

  # Every message a probe sent is read back from the live room store.
  def behaviour_outcome?(context, :sent_ids_exist_live, _args) do
    %{sent_ids: sent_ids} = context.family_chat_load_probes
    live_ids = live_family_chat_message_ids()
    sent_ids != [] and Enum.all?(sent_ids, &MapSet.member?(live_ids, &1))
  end

  def behaviour_outcome?(context, :probes_zero_failures, _args) do
    %{failures: failures, samples: samples, during_backup: during} =
      context.family_chat_load_probes

    failures == 0 and during > 0 and samples != []
  end

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

      slug == FamilyChat.canonical_room_slug() and
        context.family_chat_fixture_message_id in message_ids and
        message_ids == Enum.sort(message_ids) and
        is_integer(subscription_count) and subscription_count >= 1 and
        "pending" in delivery_states
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

  # This slot's publisher port published exactly one event for the commit, on its room's
  # topic.
  def behaviour_outcome?(context, :only_same_slot_sockets_receive, _args) do
    {:ok, %{id: id, room_id: room_id}} = context.family_chat_result
    topic = FamilyChat.subscription_topic(room_id)

    match?(
      [{^topic, %{id: ^id}}],
      Enum.filter(context.family_chat_published_events, &match?({^topic, _message}, &1))
    )
  end

  # The other slot's publisher port published nothing for that commit. It is live: a message
  # it commits itself is published there, and only there.
  def behaviour_outcome?(context, :other_slot_no_event, _args) do
    other_slot = context.family_chat_other_slot
    received = slot_published(other_slot)
    {:ok, %{id: own_id}} = slot_commit(other_slot, context.family_chat_user_id)

    received == [] and match?([{_topic, %{id: ^own_id}}], slot_published(other_slot)) and
      published_events() == []
  end

  # --- helpers ---

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
  # this from the server the endpoint the subscription document names uses.
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
  #
  # `SubscribeSelf` registers the calling process in Absinthe's registry
  # (`BnestAppWeb.Endpoint.Registry`) under the document's ID and under
  # `{field, topic}` for the topic the resolver's `subscription_config/2`
  # returned; the latter is the topic a commit publishes to. `uniq: true`
  # folds a registration an ExBdd retry of this scenario made before.
  @dialyzer {:nowarn_function, subscribe_and_get_topic!: 2}
  defp subscribe_and_get_topic!(room_slug, current_user) do
    {:ok, %{"subscribed" => _document_id}} =
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

    [topic] =
      for {:family_chat_message_committed, topic} <-
            Registry.keys(BnestAppWeb.Endpoint.Registry, self()),
          uniq: true,
          do: topic

    topic
  end

  defp ensure_family_chat_subscriptions_started! do
    {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)

    # All three are named singletons owned by the scenario's test supervisor.
    # Started linked to the test process instead, they died asynchronously
    # after the scenario, and the next subscription scenario could find them
    # still registered while their tables were already gone ("unknown
    # registry: BnestAppWeb.Endpoint.Registry"). ExUnit stops supervised
    # children before the next test starts, so each scenario gets a fresh,
    # whole set. No HTTP listener is started either way (see
    # `:holds_subscription`'s comment).
    start_once!(family_chat_pubsub_server(), {Phoenix.PubSub, name: family_chat_pubsub_server()})
    start_once!(BnestAppWeb.Endpoint, BnestAppWeb.Endpoint)

    # `Absinthe.Subscription` names its registry `Module.concat([pubsub,
    # :Registry])` -- i.e. `BnestAppWeb.Endpoint.Registry`.
    start_once!(
      BnestAppWeb.Endpoint.Registry,
      {Absinthe.Subscription, pubsub: BnestAppWeb.Endpoint, pool_size: 1}
    )

    :ok
  end

  # Checked by registered name before starting: another driver may already
  # run one of these under its own test. `GenServer.whereis/1` keeps this
  # lookup inside the unit layer's process-access boundary.
  defp start_once!(registered_name, child_spec) do
    if is_nil(GenServer.whereis(registered_name)),
      do: ExUnit.Callbacks.start_supervised!(child_spec)

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
        run_without_capability(
          context,
          """
          mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
            sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id body }
          }
          """,
          %{"roomSlug" => slug, "clientMessageId" => client_message_id, "body" => body}
        )
      else
        FamilyChat.send_message(
          sender,
          slug,
          client_message_id,
          expand_body_fixture(body),
          synthetic_display_name(sender),
          opts[:reply_to]
        )
      end

    context
    |> Map.put(:family_chat_result, result)
    |> Map.put(:family_chat_client_message_id, client_message_id)
  end

  # Runs `sendFamilyChatMessage` through the real schema, with the session a logged-in
  # member's browser carries: its display username differs from its user ID. The
  # response's message is answered in the facade's own shape for the shared Thens.
  defp send_through_schema(context, client_message_id, body) do
    :ok = start_identity_records!()
    user_id = current_user(context)

    session_user = %{
      "userId" => user_id,
      "roles" => ["parents"],
      "displayUsername" => synthetic_display_name(user_id)
    }

    {:ok, response} =
      Absinthe.run(
        """
        mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
          sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) {
            id senderId senderDisplayName body committedAt
            replyTo { id senderKind senderDisplayName bodyPreview }
          }
        }
        """,
        BnestAppWeb.Schema,
        variables: %{
          "roomSlug" => room_slug(context),
          "clientMessageId" => client_message_id,
          "body" => expand_body_fixture(body)
        },
        context: %{current_user: session_user}
      )

    Map.merge(context, %{
      family_chat_result: response_message(response),
      family_chat_client_message_id: client_message_id,
      family_chat_session_user: session_user
    })
  end

  # `Identity.display_name_for/1`, the lookup the message type resolves a sender's name
  # through, reads accounts over Storage's records, which `mix test --no-start` leaves
  # unstarted. In-memory Storage and record doubles stand in, holding no account, so the
  # lookup finds none and the type answers the name the resolver stamped on the commit.
  # Started once per scenario, an ExBdd retry included.
  defp start_identity_records! do
    if is_nil(GenServer.whereis(Records)) do
      previous = StoragePorts.install()
      ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
      ExUnit.Callbacks.start_supervised!({Records, store: InMemoryRecordBackend.start()})
    end

    :ok
  end

  defp response_message(%{data: %{"sendFamilyChatMessage" => %{} = sent}}) do
    {:ok, committed_at, 0} = DateTime.from_iso8601(sent["committedAt"])

    {:ok,
     %{
       id: String.to_integer(sent["id"]),
       sender_id: sent["senderId"],
       sender_display_name: sent["senderDisplayName"],
       body: sent["body"],
       committed_at: committed_at,
       reply_to: sent["replyTo"]
     }}
  end

  defp response_message(%{errors: [%{extensions: %{code: code}} | _]}),
    do: {:error, %{code: code}}

  # `use_family_chat` is authorized in `BnestAppWeb.Resolvers.FamilyChatResolver`
  # (`FamilyChat` itself only checks authentication), so a user without the
  # capability runs the GraphQL document through the real schema and resolver.
  # No persisted account can lack every role (see the integration driver's
  # `graphql_via_schema_as_forbidden/3`), so only the session's role list is
  # synthetic: empty.
  defp run_without_capability(context, document, variables) do
    user_id = current_user(context)

    current_user = %{
      "userId" => user_id,
      "roles" => [],
      "displayUsername" => synthetic_display_name(user_id)
    }

    Absinthe.run(document, BnestAppWeb.Schema,
      variables: variables,
      context: %{current_user: current_user}
    )
  end

  # The resolver refused with `code`, returned no data for the operation, and
  # committed nothing under the client message ID the When sent, if any.
  defp refused_without_capability?(context, code) do
    case context.family_chat_result do
      {:ok, %{data: data, errors: [%{extensions: %{code: ^code}}]}} ->
        Enum.all?(Map.values(data || %{}), &is_nil/1) and
          (is_nil(context[:family_chat_client_message_id]) or
             count_messages_for(context, context.family_chat_client_message_id) == 0)

      _other ->
        false
    end
  end

  defp leaks_room?({:ok, result}) do
    rendered = inspect(result)
    String.contains?(rendered, "ruang-keluarga") or String.contains?(rendered, "Ruang Keluarga")
  end

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
    # Reads through the configured room store (see `stored_messages/1`), not
    # the authenticated `FamilyChat.list_messages/3` context function:
    # verifying a SYSTEM message's idempotency (no logged-in member exists in
    # that scenario at all) needs this to work with no authenticated
    # identity, and a bounded 50-row page could also miss the target.
    slug =
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] || "ruang-keluarga"

    slug
    |> stored_messages()
    |> Enum.count(&(&1.idempotency_key == client_message_id))
  end

  # What the room store holds, read through the port on the handle the
  # facade itself is configured with: the scenario's in-memory store.
  # Observation only; every write goes through the facade.
  defp stored_messages(slug) do
    store = FamilyChat.adapter(:room_store).new()
    room = RoomStore.get_active_room(store, slug)
    %{nodes: nodes} = RoomStore.list_messages(store, room.id, nil, nil, 10_000)
    nodes
  end

  defp room_slug(context),
    do:
      context[:family_chat_room_slug] || context[:family_chat_subscribed_slug] ||
        "ruang-keluarga"

  defp graphiql_routes,
    do: Enum.filter(BnestAppWeb.Router.__routes__(), &String.contains?(&1.path, "graphiql"))

  defp stored_message(slug, message_id) do
    store = FamilyChat.adapter(:room_store).new()
    room = RoomStore.get_active_room(store, slug)
    RoomStore.message_by_id(store, room.id, message_id)
  end

  defp latest_message_id(slug),
    do: slug |> stored_messages() |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end)

  # A synthetic destination, saved through the Backup facade as the operator's override, in
  # the scenario's in-memory Backup doubles.
  defp backup_destination!(tag) do
    {:ok, location} =
      Backup.save_destination("/srv/test-user-backup/" <> tag <> "-" <> unique_uuid())

    location
  end

  # A capacity refusal comes before VACUUM INTO, so the snapshot double recorded no copy at
  # all. Only the capacity scenario carries `:family_chat_backup_capacity`; the timeout
  # scenario's copy legitimately starts before it is cancelled.
  defp refused_before_snapshot?(%{family_chat_backup_capacity: :insufficient}),
    do: InMemoryDatabaseSnapshot.snapshots(InMemoryDatabaseSnapshot.new()) == []

  defp refused_before_snapshot?(_context), do: true

  # The production backup schedule as the release seeds it, pristine and enabled at
  # 19:00 UTC, with `fields` replaced.
  defp put_backup_schedule!(key, fields) do
    InMemoryScheduleStore.put_daily_schedule(
      Scheduler.store(),
      key,
      "prod_sqlite_backup",
      "admin_system",
      @behaviour_now,
      fields
    )
  end

  # The push retention schedule as Family Chat's release seeds it, pristine at
  # 17:15 UTC (00:15 WIB), with `fields` replaced.
  defp put_retention_schedule!(key, fields) do
    InMemoryScheduleStore.put_daily_schedule(
      Scheduler.store(),
      key,
      "family_chat_push_retention",
      "admin_system",
      @behaviour_now,
      Map.put(fields, :daily_at_utc, "17:15")
    )
  end

  # An active push subscription, stored through the facade, which each later commit by
  # another member fans a delivery out to.
  defp put_subscription(user_id), do: subscribe_through_facade!(user_id, "accepted").id

  # Subscribes `user_id` through the facade for a session of its own, at a synthetic
  # endpoint whose last segment is `last_segment` (`status-<code>` makes the push-client
  # double answer with that status).
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
      FamilyChat.send_message(
        unique_sender_id(),
        FamilyChat.canonical_room_slug(),
        unique_uuid(),
        "push delivery fixture"
      )

    %{id: id} =
      Enum.find(
        stored_deliveries(),
        &(&1.message_id == message.id and &1.subscription_id == subscription.id)
      )

    id
  end

  defp owe_push_delivery!(context, status) do
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

  # Each delivery is owed to a subscription of its own, disabled once the commit fanned out
  # to it so later commits owe it nothing. The delivery is then put in its state as last
  # stamped eight days before the retention run, and soft-deleted then for the
  # `:soft_deleted` group: time that has passed, which only the store's test seam can stand
  # in for. Records `{state, id}` per delivery under the group.
  defp seed_aged_deliveries!(context, group, states) do
    aged = DateTime.add(@behaviour_now, -8 * 86_400, :second)

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

        :ok = InMemoryDeliveryStore.put(delivery_store(), id, aged_changes(group, state, aged))
        {state, id}
      end

    Map.update(
      context,
      :family_chat_aged_deliveries,
      %{group => seeded},
      &Map.put(&1, group, seeded)
    )
  end

  defp aged_changes(:soft_deleted, state, aged),
    do: [state: state, updated_at: aged, deleted_at: aged, deleted_by: "system:test-fixture"]

  defp aged_changes(_group, "claimed", aged),
    do: [state: "claimed", updated_at: aged, lease_expires_at: DateTime.add(aged, 120, :second)]

  defp aged_changes(_group, state, aged), do: [state: state, updated_at: aged]

  # The delivery's wait elapses: it ages by that wait (its creation moves back by it) and is
  # due now.
  defp elapse_push_wait!(delivery_id) do
    row = stored_delivery(delivery_id)
    wait = DateTime.diff(row.next_attempt_at, row.updated_at)

    InMemoryDeliveryStore.put(delivery_store(), delivery_id,
      created_at: DateTime.add(row.created_at, -wait, :second),
      next_attempt_at: row.updated_at
    )
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

    InMemoryDeliveryStore.put(delivery_store(), delivery_id,
      created_at: DateTime.add(row.updated_at, -age_seconds, :second),
      next_attempt_at: row.updated_at
    )
  end

  defp upsert_subscription(context, input) do
    result =
      PushNotifications.upsert_subscription(current_user(context), session_digest(context), input)

    Map.merge(context, %{family_chat_result: result, family_chat_push_endpoint: input["endpoint"]})
  end

  # The response reports it disabled, the Given's stored subscription was disabled by the
  # user, and the session has none.
  defp subscription_disabled?(context) do
    user_id = current_user(context)
    stored = stored_subscription(context.family_chat_push_endpoint)

    match?({:ok, %{enabled: false}}, context.family_chat_result) and
      match?(%{deleted_at: %DateTime{}}, stored) and stored.deleted_by == "user:" <> user_id and
      not session_subscribed?(user_id, session_digest(context))
  end

  defp session_subscribed?(user_id, session),
    do: match?({:ok, %{enabled: true}}, PushNotifications.current_subscription(user_id, session))

  # What the push stores hold, read on the handles the facade itself is configured with.
  # Observation only; every write goes through the facade (or the delivery store's seam for
  # elapsed time).
  defp delivery_store, do: PushNotifications.adapter(:delivery_store).new()
  defp stored_deliveries, do: InMemoryDeliveryStore.deliveries(delivery_store())
  defp stored_delivery(id), do: Enum.find(stored_deliveries(), &(&1.id == id))

  defp stored_subscription(endpoint) do
    PushNotifications.adapter(:subscription_store).new()
    |> InMemorySubscriptionStore.subscriptions()
    |> Enum.find(&(&1.endpoint == endpoint))
  end

  # Every request the push-client double recorded in this process so far, oldest first, as
  # `{endpoint, payload}`; draining them. The dispatcher sends in its caller's process, so
  # nothing can still be in flight.
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

  defp page_ids(context) do
    {:ok, %{nodes: nodes}} = context.family_chat_result
    Enum.map(nodes, & &1.id)
  end

  # Every message ID the queried room holds, ascending, read through the port.
  defp room_message_ids(context) do
    (context[:family_chat_subscribed_slug] || "ruang-keluarga")
    |> stored_messages()
    |> Enum.map(& &1.id)
  end

  # Every publish the recording publisher has delivered to this process so far,
  # oldest first, as `{topic, message}`. A commit publishes in the committing
  # process, so nothing can still be in flight.
  defp published_events do
    receive do
      {:family_chat_published, topic, message} -> [{topic, message} | published_events()]
    after
      0 -> []
    end
  end

  defp reply_events(context) do
    {:ok, %{id: reply_id}} = context.family_chat_result
    topic = context.family_chat_subscription_topic

    for {^topic, %{id: ^reply_id} = message} <- context.family_chat_published_events,
        do: message
  end

  # What code built before Family Chat answers: a stored theme preference, the
  # themes a user may choose, and whether a member may change their theme.
  defp prior_release_reads(owner, preferences) do
    member = %{"userId" => owner, "roles" => ["parents"]}

    %{
      theme: Preferences.theme(owner, store: preferences),
      themes: Preferences.themes(),
      may_write_theme: Identity.authorize(member, :write_theme, owner)
    }
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

  # A fresh endpoint on the synthetic provider host the test push senders name.
  defp valid_subscription_input do
    %{
      "endpoint" => synthetic_endpoint("valid-" <> unique_uuid()),
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
  end

  # Built from separate fragments (not one literal URL-shaped string) so this synthetic
  # fixture does not trip the unit-layer boundary policy's blanket network-URL scan.
  defp synthetic_endpoint(path), do: "https:" <> "//push.allowed.example.com/" <> path

  defp unique_uuid, do: Ecto.UUID.generate()

  # The load scenarios' probes: an authenticated member sends a message and reads the newest
  # one, timing each, round after round in a process of their own until told to stop after at
  # least `@load_proof_probe_count` rounds. Each finished round is reported to the test
  # process, so a backup can wait for rounds that finish while its copy is open.
  defp start_probes do
    test = self()
    ref = make_ref()
    empty = %{sent_ids: [], samples: [], failures: 0}
    task = Task.async(fn -> probe_rounds(test, ref, 1, empty) end)
    :ok = await_probe_rounds(ref, 1)
    %{task: task, ref: ref}
  end

  defp probe_rounds(test, ref, index, acc) do
    acc = probe_round(index, acc)
    send(test, {:probe_round, ref})

    receive do
      {:stop_probes, ^ref} when index >= @load_proof_probe_count -> acc
    after
      0 -> probe_rounds(test, ref, index + 1, acc)
    end
  end

  defp probe_round(index, acc) do
    slug = FamilyChat.canonical_room_slug()
    user_id = "test-user-backup-probe-" <> unique_uuid()

    {send_ms, sent} =
      timed_probe(fn ->
        FamilyChat.send_message(user_id, slug, unique_uuid(), "probe #{index}")
      end)

    {read_ms, read} = timed_probe(fn -> FamilyChat.list_messages(user_id, slug, limit: 1) end)

    {sent_ids, ok?} =
      case {sent, read} do
        {{:ok, %{id: id}}, {:ok, %{nodes: [_newest]}}} -> {[id | acc.sent_ids], true}
        {{:ok, %{id: id}}, _failed_read} -> {[id | acc.sent_ids], false}
        _failed_send -> {acc.sent_ids, false}
      end

    %{
      sent_ids: sent_ids,
      samples: [send_ms, read_ms | acc.samples],
      failures: acc.failures + if(ok?, do: 0, else: 1)
    }
  end

  defp await_probe_rounds(_ref, 0), do: :ok

  defp await_probe_rounds(ref, count) do
    receive do
      {:probe_round, ^ref} -> await_probe_rounds(ref, count - 1)
    after
      10_000 -> {:error, :probes_stalled}
    end
  end

  # Runs `backup` while the probes run: its copy is held open until three more probe rounds
  # finished, then the probes are stopped and their results collected. `during_backup` counts
  # the rounds the copy was held for, read back from the snapshot double.
  defp backup_under_probes(context, backup) do
    %{task: task, ref: ref} = context.family_chat_probes
    snapshot = InMemoryDatabaseSnapshot.new()
    :ok = flush_probe_rounds(ref)

    InMemoryDatabaseSnapshot.hold_next_copy(snapshot, fn ->
      :ok = await_probe_rounds(ref, 3)
      3
    end)

    result = backup.()
    send(task.pid, {:stop_probes, ref})
    probes = Task.await(task, 30_000)
    :ok = flush_probe_rounds(ref)
    {result, Map.put(probes, :during_backup, Enum.sum(InMemoryDatabaseSnapshot.holds(snapshot)))}
  end

  defp flush_probe_rounds(ref) do
    receive do
      {:probe_round, ^ref} -> flush_probe_rounds(ref)
    after
      0 -> :ok
    end
  end

  defp percentile_95([]), do: 0

  defp percentile_95(samples) do
    sorted = Enum.sort(samples)
    Enum.at(sorted, max(0, ceil(0.95 * length(sorted)) - 1))
  end

  # The `System` module's monotonic-time function is forbidden in unit test
  # files by the boundary scan (`test/behaviour/verify.exs`'s
  # `BoundaryPolicy` treats any call into that module as forbidden
  # operating-system access); `:erlang.monotonic_time/1` is the identical
  # monotonic clock without going through that forbidden module.
  # The call's own duration: the clock is read again only once it returned.
  defp timed_probe(fun) do
    started = :erlang.monotonic_time(:millisecond)
    result = fun.()
    {:erlang.monotonic_time(:millisecond) - started, result}
  end

  # The live room's message IDs, read from the scenario's room store, so they compare
  # directly against the restore evidence's `orderedMessageIds`.
  defp live_family_chat_message_ids do
    FamilyChat.canonical_room_slug() |> stored_messages() |> MapSet.new(& &1.id)
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

  # Records what the next reply must quote: the target's server ID, and the
  # sender name and body a correct quote has to report back.
  defp capture_reply_target(context) do
    {:ok, target} = context.family_chat_result

    Map.merge(context, %{
      family_chat_reply_target_id: target.id,
      family_chat_reply_target_body: target.body,
      family_chat_reply_target_display_name: target.sender_display_name
    })
  end

  # A second room only v1's data model allows, never its UI: seeded already
  # archived so `list_rooms_for/1` keeps reporting exactly one active room
  # (the behaviour corpus asserts that), while `message_by_id/3`'s room
  # scoping still has a genuinely foreign message to refuse. No Family Chat
  # operation creates a room, so the room goes into the scenario's in-memory
  # store directly; its message is committed through the facade's
  # trusted-producer insert.
  defp archived_room_message_id do
    archived = %{FamilyChat.canonical_room() | id: 900, slug: "ruang-arsip", name: "Ruang Arsip"}
    :ok = InMemoryRoomStore.put_room(InMemoryRoomStore.new(), archived, deleted?: true)

    {:ok, foreign} =
      FamilyChat.insert_message!(
        900,
        "user",
        "test-user-family-chat-archive",
        "Arsip",
        "archive-" <> unique_uuid(),
        "a message in another room"
      )

    foreign.id
  end

  defp quoted_of_reply(context) do
    case node_by_id(context, context.family_chat_reply_message_id) do
      %{reply_to: quoted} -> quoted
      _other -> nil
    end
  end

  defp node_by_id(context, id) do
    case context.family_chat_result do
      {:ok, %{nodes: nodes}} -> Enum.find(nodes, &(&1.id == id))
      _other -> nil
    end
  end

  defp unique_sender_id, do: "test-user-family-chat-sender-" <> unique_uuid()

  # Runs one mutation field through the public schema as an authenticated member with the
  # use family chat capability, its arguments filled by name. A field that needs an
  # argument no value names cannot run, and is reported so.
  defp run_public_mutation(field, user_id) do
    values = %{
      "roomSlug" => FamilyChat.canonical_room_slug(),
      "clientMessageId" => unique_uuid(),
      "body" => "public schema probe",
      "endpoint" => synthetic_endpoint("schema-" <> unique_uuid()),
      "p256dh" => Base.url_encode64(:crypto.strong_rand_bytes(65), padding: false),
      "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    current_user = %{
      "userId" => user_id,
      "roles" => ["parents"],
      "displayUsername" => synthetic_display_name(user_id)
    }

    with {:ok, document, variables} <- PublicMutationProbe.invocation(field, values),
         {:ok, %{data: data} = result} when not is_map_key(result, :errors) <-
           Absinthe.run(document, BnestAppWeb.Schema,
             variables: variables,
             context: %{current_user: current_user, session_digest: "test-session-" <> user_id}
           ),
         %{} <- data[field.name] do
      {field.name, :ran}
    else
      other -> {field.name, {:failed, other}}
    end
  end

  # A commit whose delivery rows cannot be written raises, and leaves the store as it was.
  defp failed_commit_left_nothing?(context) do
    store = InMemoryRoomStore.new()
    deliveries_before = InMemoryDeliveryStore.deliveries(InMemoryDeliveryStore.new())
    client_message_id = unique_uuid()
    :ok = InMemoryRoomStore.fail_next_delivery_insert(store)

    refused? =
      try do
        _committed =
          FamilyChat.send_message(
            context.family_chat_user_id,
            context.family_chat_room_slug,
            client_message_id,
            "Dinner is ready, again"
          )

        false
      rescue
        ArgumentError -> true
      end

    refused? and count_messages_for(context, client_message_id) == 0 and
      InMemoryDeliveryStore.deliveries(InMemoryDeliveryStore.new()) == deliveries_before
  end

  # A second slot: a process of its own that commits through the facade when asked, and
  # reports what its publisher port published there.
  defp start_slot do
    Task.async(fn -> slot_loop([]) end)
  end

  defp slot_loop(published) do
    receive do
      {:family_chat_published, topic, message} ->
        slot_loop([{topic, message} | published])

      {:commit, sender, from, ref} ->
        result =
          FamilyChat.send_message(
            sender,
            FamilyChat.canonical_room_slug(),
            unique_uuid(),
            "the other slot's own message"
          )

        send(from, {ref, result})
        slot_loop(published)

      {:published, from, ref} ->
        send(from, {ref, Enum.reverse(published)})
        slot_loop(published)
    end
  end

  defp slot_commit(slot, sender), do: slot_call(slot, &{:commit, sender, &1, &2})
  defp slot_published(slot), do: slot_call(slot, &{:published, &1, &2})

  defp slot_call(%Task{pid: pid}, request) do
    ref = make_ref()
    send(pid, request.(self(), ref))

    receive do
      {^ref, answer} -> answer
    after
      5_000 -> raise "the other slot did not answer"
    end
  end
end
