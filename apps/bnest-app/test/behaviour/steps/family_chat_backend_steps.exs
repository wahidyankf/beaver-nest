defmodule BnestApp.Behaviour.FamilyChatBackendSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  # --- family_chat_graphql.feature ---

  step("the family chat room holds a known ordered history of messages", context,
    do: prepare(context, :room_has_known_history)
  )

  step("the user queries the family chat room list", context,
    do: perform(context, :query_room_list)
  )

  step("the response lists exactly the active {string} room", %{args: [name]} = context,
    do: outcome(context, :room_list_lists_exactly, [name])
  )

  step("the user queries the family chat room {string}", %{args: [slug]} = context,
    do: perform(context, :query_room_by_slug, [slug])
  )

  step("the response returns the {string} room", %{args: [name]} = context,
    do: outcome(context, :room_returned, [name])
  )

  step("the user queries family chat messages with no cursor", context,
    do: perform(context, :query_messages_no_cursor)
  )

  step("the response returns at most 50 messages ascending by server ID", context,
    do: outcome(context, :messages_ascending_max_50)
  )

  step("\"hasOlder\" reflects whether an older message exists", context,
    do: outcome(context, :has_older_correct)
  )

  step("the user queries family chat messages before a known message ID", context,
    do: perform(context, :query_messages_before_known_id)
  )

  step("the response returns older messages ascending by server ID", context,
    do: outcome(context, :older_messages_ascending)
  )

  step("the user queries family chat messages after a known committed message ID", context,
    do: perform(context, :query_messages_after_known_id)
  )

  step("the response returns newer messages ascending by server ID", context,
    do: outcome(context, :newer_messages_ascending)
  )

  step("\"hasNewer\" reflects whether another page remains", context,
    do: outcome(context, :has_newer_correct)
  )

  step("the user queries family chat messages with both a beforeId and an afterId", context,
    do: perform(context, :query_messages_both_cursors)
  )

  step("the response is a safe {string} error", %{args: [code]} = context,
    do: outcome(context, :safe_error, [code])
  )

  step("the user queries family chat messages with limit {int}", %{args: [limit]} = context,
    do: perform(context, :query_messages_with_limit, [limit])
  )

  step(
    "the user sends the family chat message {string} with a fresh client message ID",
    %{args: [body]} = context,
    do: perform(context, :send_message_fresh_id, [body])
  )

  step("the response returns the committed message with a server ID and commit time", context,
    do: outcome(context, :message_committed_with_id_and_time)
  )

  step("the family chat room holds exactly one message with that client message ID", context,
    do: outcome(context, :room_has_one_message_for_client_id)
  )

  step(
    "the response reports the sender's real display username, not their raw user ID",
    context,
    do: outcome(context, :message_reports_real_display_name)
  )

  step(
    "the user already sent the family chat message {string} with a known client message ID",
    %{args: [body]} = context,
    do: prepare(context, :sent_message_with_known_id, [body])
  )

  step(
    "the user sent the family chat message {string} and it was committed",
    %{args: [body]} = context,
    do: prepare(context, :sent_and_committed_message, [body])
  )

  step("a system message was posted to the room", context,
    do: prepare(context, :system_message_posted_to_room)
  )

  step(
    "the sender's account display name later changes to {string}",
    %{args: [new_name]} = context,
    do: perform(context, :rename_sender_account, [new_name])
  )

  step("the user later re-queries family chat messages", context,
    do: perform(context, :requery_after_rename)
  )

  step(
    "the response reports {string} as that message's sender display name, not the name stored at commit time",
    %{args: [expected_name]} = context,
    do: outcome(context, :message_shows_current_sender_display_name, [expected_name])
  )

  step(
    "the system message's sender display name remains unaffected by the account rename",
    context,
    do: outcome(context, :system_message_display_name_unaffected)
  )

  step("the user resends a different body with the same client message ID", context,
    do: perform(context, :resend_same_client_id)
  )

  step("the response returns the original committed message unchanged", context,
    do: outcome(context, :original_message_unchanged)
  )

  step(
    "the family chat room still holds exactly one message for that client message ID",
    context,
    do: outcome(context, :room_still_one_message)
  )

  step("the visitor queries the family chat room list", context,
    do: perform(context, :visitor_query_room_list)
  )

  step("an approved user without family chat capability is logged in", context,
    do: prepare(context, :user_without_family_chat_capability)
  )

  step("the response reveals no hidden room state", context,
    do: outcome(context, :no_hidden_room_state)
  )

  step("the family chat room gains no new message", context,
    do: outcome(context, :room_gains_no_message)
  )

  step(
    "the user holds an authorized {string} subscription for {string}",
    %{args: [subscription_name, slug]} = context,
    do: prepare(context, :holds_subscription, [subscription_name, slug])
  )

  step(
    "another member sends the family chat message {string} with a fresh client message ID",
    %{args: [body]} = context,
    do: perform(context, :other_member_sends, [body])
  )

  step(
    "the subscriber receives exactly one committed-message event matching that message",
    context,
    do: outcome(context, :subscriber_received_one_event)
  )

  step("a duplicate retry of the same client message ID publishes no second event", context,
    do: outcome(context, :no_duplicate_publish)
  )

  step("a message committed before the user's subscription started", context,
    do: prepare(context, :message_committed_before_subscription)
  )

  step(
    "the user establishes the {string} subscription for {string}",
    %{args: [subscription_name, slug]} = context,
    do: perform(context, :establish_subscription, [subscription_name, slug])
  )

  step(
    "the user queries family chat messages after their last known committed message ID",
    context,
    do: perform(context, :query_after_last_known_id)
  )

  step("the response includes the message committed before the subscription started", context,
    do: outcome(context, :includes_message_before_subscription)
  )

  step("the user queries the Web Push configuration", context,
    do: perform(context, :query_web_push_configuration)
  )

  step("the response reports whether Web Push is available", context,
    do: outcome(context, :reports_web_push_availability)
  )

  step(
    "the response includes the public application server key only when configured and safe",
    context,
    do: outcome(context, :includes_safe_public_key)
  )

  step("the user queries their current Web Push subscription", context,
    do: perform(context, :query_current_subscription)
  )

  step("the response reports enabled state and expiration only", context,
    do: outcome(context, :reports_enabled_and_expiration_only)
  )

  step("the user upserts a valid Web Push subscription for this session", context,
    do: perform(context, :upsert_valid_subscription)
  )

  step("the response reports the subscription enabled", context,
    do: outcome(context, :subscription_enabled)
  )

  step("the stored subscription is bound to the current user and session only", context,
    do: outcome(context, :subscription_bound_to_session)
  )

  step("the user has an enabled Web Push subscription for this session", context,
    do: prepare(context, :has_enabled_subscription)
  )

  step("the user disables their current Web Push subscription", context,
    do: perform(context, :disable_subscription)
  )

  step("the response reports the subscription disabled", context,
    do: outcome(context, :subscription_disabled)
  )

  step("the user disables their current Web Push subscription again", context,
    do: perform(context, :disable_subscription_again)
  )

  step("the response still reports the subscription disabled", context,
    do: outcome(context, :subscription_still_disabled)
  )

  step(
    "the user upserts a Web Push subscription with endpoint {string}",
    %{args: [endpoint]} = context,
    do: perform(context, :upsert_subscription_with_endpoint, [endpoint])
  )

  step("no subscription row is stored or requested over the network", context,
    do: outcome(context, :no_subscription_stored_or_network)
  )

  step("the user sends a family chat message mutation with a missing CSRF token", context,
    do: perform(context, :send_mutation_missing_csrf)
  )

  step("the response is a 403 envelope with a safe {string} error", %{args: [code]} = context,
    do: outcome(context, :transport_safe_error, [code])
  )

  step(
    "the user's browser opens the family chat GraphQL socket with the authenticated session",
    context,
    do: perform(context, :open_socket_authenticated)
  )

  step(
    "the socket context carries the server-resolved current user and session digest",
    context,
    do: outcome(context, :socket_context_server_resolved)
  )

  step("socket parameters claiming another identity or role are ignored", context,
    do: outcome(context, :socket_params_ignored)
  )

  step("the visitor's browser opens the family chat GraphQL socket", context,
    do: perform(context, :visitor_opens_socket)
  )

  step("the socket handshake is rejected", context,
    do: outcome(context, :socket_handshake_rejected)
  )

  step("the endpoint is configured for the production environment", context,
    do: prepare(context, :endpoint_configured_production)
  )

  step("the router's compiled routes are inspected", context,
    do: perform(context, :inspect_router_routes)
  )

  step("no GraphiQL route is compiled or mounted", context,
    do: outcome(context, :no_graphiql_route)
  )

  # --- family_chat_operations.feature ---

  step("a freshly migrated database with no prior family chat data", context,
    do: prepare(context, :fresh_migrated_database)
  )

  step("the family chat migration runs", context,
    do: perform(context, :run_family_chat_migration)
  )

  step(
    "room ID 1 exists with slug {string}, name {string}, and posting enabled",
    %{args: [slug, name]} = context,
    do: outcome(context, :room_seed_correct, [slug, name])
  )

  step("repeating the migration changes nothing about that seeded room", context,
    do: outcome(context, :migration_idempotent)
  )

  step("the additive family chat migration has applied", context,
    do: prepare(context, :migration_applied)
  )

  step("code built before this migration opens the same database", context,
    do: perform(context, :old_code_opens_database)
  )

  step("the prior release's existing behavior is unaffected", context,
    do: outcome(context, :prior_release_unaffected)
  )

  step("no prior-release code path touches the new family chat tables", context,
    do: outcome(context, :no_prior_release_table_access)
  )

  step("a trusted internal producer with a stable idempotency key", context,
    do: prepare(context, :trusted_producer)
  )

  step("the producer posts a system message to {string}", %{args: [slug]} = context,
    do: perform(context, :producer_posts_system_message, [slug])
  )

  step(
    "the message is committed with sender kind {string} and the producer's stable sender ID",
    %{args: [sender_kind]} = context,
    do: outcome(context, :system_message_committed, [sender_kind])
  )

  step("the same producer retries with the same idempotency key", context,
    do: perform(context, :producer_retries_same_key)
  )

  step("the original committed system message is returned unchanged", context,
    do: outcome(context, :system_message_unchanged)
  )

  step("exactly one system message exists for that idempotency key", context,
    do: outcome(context, :exactly_one_system_message)
  )

  step("the public GraphQL schema is inspected", context,
    do: perform(context, :inspect_public_schema)
  )

  step("it declares no field that posts a system message", context,
    do: outcome(context, :schema_has_no_system_message_field)
  )

  step(
    "three other members hold active Web Push subscriptions in {string}",
    %{args: [slug]} = context,
    do: prepare(context, :three_members_with_subscriptions, [slug])
  )

  step("a member sends a durable family chat message", context,
    do: perform(context, :member_sends_durable_message)
  )

  step(
    "the message and one pending delivery row per other active subscription commit in one transaction",
    context,
    do: outcome(context, :message_and_deliveries_committed_atomically)
  )

  step("the sender receives no delivery row for their own message", context,
    do: outcome(context, :sender_excluded_from_delivery)
  )

  step("a delivery row whose provider request will fail with a retryable result", context,
    do: prepare(context, :delivery_will_fail_retryable)
  )

  step("the dispatcher attempts the delivery", context,
    do: perform(context, :dispatcher_attempts_delivery)
  )

  step(
    "the delivery state becomes {string} with the next fixed push wait",
    %{args: [state]} = context,
    do: outcome(context, :delivery_retryable_with_wait, [state])
  )

  step("a sixth attempt or an attempt past the one-hour ceiling does not occur", context,
    do: outcome(context, :no_attempt_past_ceiling)
  )

  step("a delivery row targeting a subscription the provider reports as gone", context,
    do: prepare(context, :delivery_targets_gone_subscription)
  )

  step(
    "the delivery state becomes {string} and the subscription is disabled",
    %{args: [state]} = context,
    do: outcome(context, :delivery_terminal_subscription_disabled, [state])
  )

  step("no further delivery attempt is scheduled", context,
    do: outcome(context, :no_further_attempt_scheduled)
  )

  step("delivered and terminal delivery rows completed more than seven days ago", context,
    do: prepare(context, :final_rows_older_than_7_days)
  )

  step("pending, claimed, and retryable delivery rows of the same age", context,
    do: prepare(context, :nonfinal_rows_same_age)
  )

  step("the retention job runs", context, do: perform(context, :retention_job_runs))

  step("the completed rows more than seven days old are soft-deleted", context,
    do: outcome(context, :completed_rows_soft_deleted)
  )

  step("the pending, claimed, and retryable rows remain active regardless of age", context,
    do: outcome(context, :nonfinal_rows_remain_active)
  )

  step("delivery rows soft-deleted more than seven days ago", context,
    do: prepare(context, :soft_deleted_rows_older_than_7_days)
  )

  step("the retention job runs again", context, do: perform(context, :retention_job_runs_again))

  step("those rows are purged from SQLite", context, do: outcome(context, :rows_purged))

  step("the run is idempotent when repeated with no newly eligible rows", context,
    do: outcome(context, :retention_run_idempotent)
  )

  step("the {string} schedule is due", %{args: [key]} = context,
    do: prepare(context, :schedule_due, [key])
  )

  step("the {string} schedule is due and enabled", %{args: [key]} = context,
    do: prepare(context, :schedule_due_and_enabled, [key])
  )

  step("the Scheduler claims and dispatches it", context,
    do: perform(context, :scheduler_claims_and_dispatches)
  )

  step("only the registered {string} handler is invoked", %{args: [name]} = context,
    do: outcome(context, :only_named_handler_invoked, [name])
  )

  step("only the registered retention handler is invoked", context,
    do: outcome(context, :only_retention_handler_invoked)
  )

  step(
    "the handler delegates to the public {string} service without direct SQL",
    %{args: [service_name]} = context,
    do: outcome(context, :handler_delegates_to_service, [service_name])
  )

  step("the existing {string} schedule uses a different daily time", %{args: [key]} = context,
    do: prepare(context, :schedule_different_time, [key])
  )

  step("the compatibility release calls the public Scheduler convergence operation", context,
    do: perform(context, :call_convergence_operation)
  )

  step(
    "{string} is updated to {string} {string}",
    %{args: [key, field, value]} = context,
    do: outcome(context, :schedule_field_updated, [key, field, value])
  )

  step("repeating the convergence call afterward changes nothing", context,
    do: outcome(context, :convergence_call_idempotent)
  )

  step("the {string} schedule ships as a disabled seed", %{args: [key]} = context,
    do: prepare(context, :schedule_disabled_seed, [key])
  )

  step("the compatibility release calls the public Scheduler activation operation", context,
    do: perform(context, :call_activation_operation)
  )

  step("{string} becomes enabled", %{args: [key]} = context,
    do: outcome(context, :schedule_field_enabled, [key])
  )

  step("repeating the activation call afterward changes nothing", context,
    do: outcome(context, :activation_call_idempotent)
  )

  step("the one-time convergence already ran", context,
    do: prepare(context, :convergence_already_ran)
  )

  step("an operator later changed {string} to a different daily time", %{args: [key]} = context,
    do: prepare(context, :operator_changed_schedule_time, [key])
  )

  step("Bnest starts again", context, do: perform(context, :bnest_starts_again))

  step("the operator's chosen time remains unchanged", context,
    do: outcome(context, :operator_time_unchanged)
  )

  step(
    "the backup destination reports insufficient free bytes for the required reserve",
    context,
    do: prepare(context, :insufficient_capacity)
  )

  step("the service returns a retryable {string} failure", %{args: [category]} = context,
    do: outcome(context, :retryable_failure, [category])
  )

  step("no partial or final backup artifact is created", context,
    do: outcome(context, :no_partial_or_final_artifact)
  )

  step("continuous authenticated family chat read and send probes are running", context,
    do: prepare(context, :continuous_probes_running)
  )

  step("a whole-database backup runs for its entire duration", context,
    do: perform(context, :routed_backup_runs_full_duration)
  )

  step(
    "every probe completes with zero failures, p95 at most 500 ms, and every sample at most two seconds",
    context,
    do: outcome(context, :probes_within_budget)
  )

  step("every sent message ID exists in the live database afterward", context,
    do: outcome(context, :sent_ids_exist_live)
  )

  step("the backup produces a restorable, self-consistent snapshot", context,
    do: outcome(context, :load_proof_restorable_snapshot)
  )

  step("the configured backup timeout is far shorter than the snapshot needs", context,
    do: prepare(context, :backup_timeout_forced)
  )

  step("the timed-out backup handler runs directly", context,
    do: perform(context, :timed_out_backup_direct)
  )

  step("every probe completes with zero failures", context,
    do: outcome(context, :probes_zero_failures)
  )

  step("the same timed-out backup is claimed and run through the Scheduler", context,
    do: perform(context, :timed_out_backup_via_scheduler)
  )

  step("the schedule remains claimable for another attempt", context,
    do: outcome(context, :schedule_remains_claimable)
  )

  step(
    "a verified backup artifact containing family chat rooms, messages, subscriptions, and deliveries",
    context,
    do: prepare(context, :verified_backup_artifact)
  )

  step("the artifact is restored into an isolated marked root", context,
    do: perform(context, :restore_artifact_isolated_root)
  )

  step(
    "the restored room, ordered messages, push subscription structure, and delivery states are all readable",
    context,
    do: outcome(context, :restored_state_readable)
  )

  step("no message body or secret value appears in the restore evidence", context,
    do: outcome(context, :no_secret_in_restore_evidence)
  )

  step("two application slots are started independently with no shared distribution", context,
    do: prepare(context, :two_independent_slots)
  )

  step("a message commits on one slot", context,
    do: perform(context, :message_commits_on_one_slot)
  )

  step("only sockets connected to that same slot receive the subscription event", context,
    do: outcome(context, :only_same_slot_sockets_receive)
  )

  step("the other slot publishes no corresponding event", context,
    do: outcome(context, :other_slot_no_event)
  )

  step("the deployment tool generates the reverse-proxy configuration for a release", context,
    do: perform(context, :generate_reverse_proxy_config)
  )

  step(
    "the generated configuration omits {string} and any other nonzero stream-close delay",
    %{args: [setting]} = context,
    do: outcome(context, :no_nonzero_stream_close_delay, [setting])
  )

  step("the existing global five-minute grace period remains present", context,
    do: outcome(context, :grace_period_present)
  )

  step("a routed socket is held open on the prior slot before promotion", context,
    do: prepare(context, :routed_socket_on_prior_slot)
  )

  step("Caddy reloads to route the promoted slot", context,
    do: perform(context, :caddy_reloads_promoted)
  )

  step("the prior-slot socket closes", context, do: outcome(context, :prior_slot_socket_closes))

  step("every replacement handshake reaches only the promoted slot", context,
    do: outcome(context, :handshake_only_promoted_slot)
  )

  step(
    "the prior slot remains process-warm and receives no new routed handshake during the observation window",
    context,
    do: outcome(context, :prior_slot_warm_unrouted)
  )

  defp prepare(context, state), do: context.behaviour_driver.prepare_behaviour(context, state, [])

  defp prepare(context, state, args),
    do: context.behaviour_driver.prepare_behaviour(context, state, args)

  defp perform(context, action),
    do: context.behaviour_driver.perform_behaviour(context, action, [])

  defp perform(context, action, args),
    do: context.behaviour_driver.perform_behaviour(context, action, args)

  defp outcome(context, expected) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, [])
    context
  end

  defp outcome(context, expected, args) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, args)
    context
  end
end
