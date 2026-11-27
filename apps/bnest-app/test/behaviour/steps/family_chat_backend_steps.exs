defmodule BnestApp.Behaviour.FamilyChatBackendSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  # --- family_chat_graphql.feature ---

  step("the deployment tool generates the reverse-proxy configuration for a release", context,
    do: perform(context, :generate_caddy_configurations)
  )

  step(
    "the generated configuration omits \"stream_close_delay\" and any other nonzero stream-close delay",
    context,
    do: outcome(context, :caddy_omits_stream_close_delay)
  )

  step("the existing global five-minute grace period remains present", context,
    do: outcome(context, :caddy_grace_period_present)
  )

  step(
    "the deployment tool generates the reverse-proxy configuration that promotes the replacement slot",
    context,
    do: perform(context, :generate_caddy_configurations)
  )

  step("every replacement handshake is routed only to the promoted slot", context,
    do: outcome(context, :handshake_routed_only_to_promoted)
  )

  step("no routed handshake reaches the prior slot", context,
    do: outcome(context, :no_handshake_reaches_prior_slot)
  )

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
    "the user queries one page of family chat messages asking for bodyHtml once",
    context,
    do: perform(context, :query_messages_body_html_once)
  )

  step(
    "the user queries one page of family chat messages asking for bodyHtml under ten aliases",
    context,
    do: perform(context, :query_messages_body_html_ten_aliases)
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

  step(
    "no other session of that user and no other user reads that subscription as enabled",
    context,
    do: outcome(context, :subscription_bound_to_session)
  )

  step("the user has an enabled Web Push subscription for this session", context,
    do: prepare(context, :has_enabled_subscription)
  )

  step("the user has disabled their Web Push subscription for this session", context,
    do: context |> prepare(:has_enabled_subscription) |> perform(:disable_subscription)
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

  step("the member's current Web Push subscription still reads disabled", context,
    do:
      context
      |> perform(:query_current_subscription)
      |> outcome(:current_subscription_reads_disabled)
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
    "a subscription opened on the socket is authorised as the signed-in member",
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

  step("the socket context carries the server-resolved current user and session digest", context,
    do: outcome(context, :socket_context_server_resolved)
  )

  step("no subscription row is stored or requested over the network", context,
    do: context |> outcome(:no_web_push_subscription_stored) |> outcome(:no_web_push_request_sent)
  )

  step("no GraphiQL route is compiled or mounted", context,
    do: outcome(context, :graphiql_not_compiled)
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

  step("the additive family chat reply migration has applied", context,
    do: prepare(context, :reply_migration_applied)
  )

  step("code built before that migration opens the same database", context,
    do: perform(context, :pre_reply_release_opens_database)
  )

  step("it reads and writes every other family chat message column unchanged", context,
    do: outcome(context, :pre_reply_columns_unchanged)
  )

  step("messages it commits carry no reply target", context,
    do: outcome(context, :pre_reply_commits_have_no_target)
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

  step("a visitor requests the GraphiQL page", context, do: perform(context, :request_graphiql))

  step("the response is not found \\(404\\)", context, do: outcome(context, :graphiql_not_found))

  # --- family_chat_operations.feature ---

  step("a fresh installation", context, do: prepare(context, :fresh_migrated_database))

  step("a member lists the rooms and sends a message", context,
    do: perform(context, :member_lists_rooms_and_sends)
  )

  step(
    "room {string} is listed and the message is accepted",
    %{args: [name]} = context,
    do: outcome(context, :room_listed_and_message_accepted, [name])
  )

  step(
    "room ID 1 exists with slug {string}, name {string}, and posting enabled",
    %{args: [slug, name]} = context,
    do: outcome(context, :seeded_room_ready_for_posting, [slug, name])
  )

  step("repeating the migration changes nothing about that seeded room", context,
    do: outcome(context, :repeat_migration_changes_nothing)
  )

  step(
    "the message and one pending delivery row per other active subscription commit in one transaction",
    context,
    do: outcome(context, :message_and_deliveries_committed_atomically)
  )

  step("exactly one pending delivery row exists for that subscription", context,
    do: outcome(context, :one_pending_delivery_for_reply_subscription)
  )

  step("the delivery state becomes {string}", %{args: [state]} = context,
    do: outcome(context, :delivery_state_is, [state])
  )

  step("every probe completes with zero failures", context,
    do: outcome(context, :probes_complete_with_zero_failures)
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
    "each of the three other subscriptions is sent one push for the message and the sender's own subscription is sent none",
    context,
    do: outcome(context, :each_other_subscription_pushed_once)
  )

  step("a delivery row whose provider request will fail with a retryable result", context,
    do: prepare(context, :delivery_will_fail_retryable)
  )

  step("the dispatcher attempts the delivery", context,
    do: perform(context, :dispatcher_attempts_delivery)
  )

  step(
    "the push service is asked again after 30 seconds, then 120, 480 and 1920 seconds, with no sixth attempt and no attempt past one hour",
    context,
    do: outcome(context, :retries_follow_fixed_waits)
  )

  step("a delivery row targeting a subscription the provider reports as gone", context,
    do: prepare(context, :delivery_targets_gone_subscription)
  )

  step(
    "the member's current Web Push subscription reports disabled and the push service is not asked again",
    context,
    do: outcome(context, :subscription_reports_disabled_no_retry)
  )

  step("the existing {string} schedule uses a different daily time", %{args: [key]} = context,
    do: prepare(context, :schedule_different_time, [key])
  )

  step("the release's converge step has run", context,
    do: perform(context, :release_converge_step)
  )

  step(
    "the schedules page lists the daily backup at 18:00 UTC",
    context,
    do:
      outcome(context, :schedule_field_updated, [
        "prod-sqlite-backup-daily",
        "daily_at_utc",
        "18:00"
      ])
  )

  step("running the converge step again leaves it so", context,
    do: outcome(context, :convergence_call_idempotent)
  )

  step("a release whose retention schedule was listed disabled", context,
    do: prepare(context, :schedule_disabled_seed, ["family-chat-push-retention-daily"])
  )

  step(
    "the schedules page lists it enabled, and a second run changes nothing",
    context,
    do: outcome(context, :retention_enabled_second_run_changes_nothing)
  )

  step("the one-time convergence already ran", context,
    do: prepare(context, :convergence_already_ran)
  )

  step(
    "the administrator saved a different daily backup time on the schedules page",
    context,
    do: prepare(context, :operator_changed_schedule_time, ["prod-sqlite-backup-daily"])
  )

  step("Bnest restarts", context, do: perform(context, :bnest_starts_again))

  step("the schedules page still shows that time", context,
    do: outcome(context, :operator_time_unchanged)
  )

  step(
    "the backup destination reports insufficient free bytes for the required reserve",
    context,
    do: prepare(context, :insufficient_capacity)
  )

  step("the scheduled backup runs", context, do: perform(context, :run_backup_handler))

  step("no backup file or partial file appears", context,
    do: outcome(context, :no_partial_or_final_artifact)
  )

  step("the run shows a retryable {string} failure", %{args: [category]} = context,
    do: outcome(context, :retryable_failure, [category])
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

  step("every sent message ID exists in the room history afterward", context,
    do: outcome(context, :sent_ids_exist_live)
  )

  step("the backup produces a restorable, self-consistent snapshot", context,
    do: outcome(context, :load_proof_restorable_snapshot)
  )

  step("the configured backup timeout is far shorter than the snapshot needs", context,
    do: prepare(context, :backup_timeout_forced)
  )

  step("a scheduled backup exceeds its timeout", context,
    do: perform(context, :scheduled_backup_exceeds_timeout)
  )

  step(
    "no backup or partial file appears, the run shows a retryable {string} failure, and the next attempt runs",
    %{args: [category]} = context,
    do: outcome(context, :timeout_failure_retried, [category])
  )

  # --- family_chat_graphql.feature: replying to a message ---

  step(
    "a family chat message from another member is already committed in {string}",
    %{args: [slug]} = context,
    do: prepare(context, :other_member_message_committed, [slug])
  )

  step(
    "the user sends the family chat message {string} naming that message as the reply target",
    %{args: [body]} = context,
    do: perform(context, :send_reply_to_known_target, [body])
  )

  step("the response's quote names that reply target's server ID", context,
    do: outcome(context, :quote_names_target_id)
  )

  step(
    "the response's quote reports that target's sender display name and a preview of its body",
    context,
    do: outcome(context, :quote_reports_sender_and_preview)
  )

  step("the response's message carries no quote", context,
    do: outcome(context, :message_has_no_quote)
  )

  step("a committed family chat message whose body is 400 graphemes long", context,
    do: prepare(context, :committed_long_message)
  )

  step("the user sends a family chat reply naming that message as the reply target", context,
    do: perform(context, :send_reply_to_known_target)
  )

  step(
    "the response's quote preview keeps at most {int} graphemes before its ellipsis",
    %{args: [budget]} = context,
    do: outcome(context, :quote_preview_within_budget, [budget])
  )

  step("the response's quote preview ends with an ellipsis", context,
    do: outcome(context, :quote_preview_elided)
  )

  step("the quoted message's own body is returned in full, unshortened", context,
    do: outcome(context, :quoted_body_unshortened)
  )

  # One binding per Examples row rather than a parameter: ExBdd Expressions
  # have no free-text placeholder ({word} stops at whitespace), and each row
  # names a genuinely different refusal path anyway.
  step(
    "the user sends a family chat reply whose reply target names a server ID no message has",
    context,
    do: perform(context, :reply_target_unknown_id)
  )

  step(
    "the user sends a family chat reply whose reply target names a message in a different room",
    context,
    do: perform(context, :reply_target_other_room)
  )

  step(
    "the user sends a family chat reply whose reply target is not a positive integer",
    context,
    do: perform(context, :reply_target_not_positive_integer)
  )

  step("the response reports a validation failure", context,
    do: outcome(context, :safe_error, ["VALIDATION_FAILED"])
  )

  step("the family chat room holds no message for that client message ID", context,
    do: outcome(context, :room_has_no_message_for_client_id)
  )

  step("no committed-message event is published", context,
    do: outcome(context, :no_event_published)
  )

  step("a committed family chat message {string}", %{args: [body]} = context,
    do: prepare(context, :committed_message, [body])
  )

  step("a committed family chat reply to it reading {string}", %{args: [body]} = context,
    do: prepare(context, :committed_reply_to_previous, [body])
  )

  step("the user sends a family chat reply naming that reply as the reply target", context,
    do: perform(context, :send_reply_to_previous_reply)
  )

  step("the response's quote names the reply it answers", context,
    do: outcome(context, :quote_names_previous_reply)
  )

  step("that quote carries no quote of its own", context, do: outcome(context, :quote_is_flat))

  step(
    "the user already sent the family chat message {string} with a known client message ID",
    %{args: [body]} = context,
    do: prepare(context, :plain_message_with_known_id, [body])
  )

  step(
    "the user already sent a family chat reply to a known message with a known client message ID",
    context,
    do: prepare(context, :sent_reply_with_known_id)
  )

  step("the user resends the same client message ID naming a different reply target", context,
    do: perform(context, :resend_same_id_other_target)
  )

  step("that message's quote still names the reply target committed first", context,
    do: outcome(context, :quote_names_first_target)
  )

  step("the user replied to a message committed under the sender's earlier display name", context,
    do: prepare(context, :replied_under_earlier_display_name)
  )

  step(
    "the reply's quote reports {string} as the quoted sender's display name",
    %{args: [expected_name]} = context,
    do: outcome(context, :quote_reports_live_display_name, [expected_name])
  )

  step("that name matches the display name shown on the quoted message itself", context,
    do: outcome(context, :quote_name_matches_original)
  )

  step("another member sends a family chat reply to one of the user's messages", context,
    do: perform(context, :other_member_replies_to_user)
  )

  step("the subscriber receives exactly one committed-message event matching that reply", context,
    do: outcome(context, :one_event_for_reply)
  )

  step("that event's message carries a quote naming the message it answers", context,
    do: outcome(context, :event_message_carries_quote)
  )

  step("a family chat reply committed before the user's subscription started", context,
    do: prepare(context, :reply_committed_before_subscription)
  )

  step("the response includes that reply", context,
    do: outcome(context, :response_includes_reply)
  )

  step("that reply carries a quote naming the message it answers", context,
    do: outcome(context, :reply_carries_quote)
  )

  # --- family_chat_graphql.feature: message body as safe HTML ---

  step("the response's bodyHtml is the family chat message body element", context,
    do: outcome(context, :body_html_is_message_body_element)
  )

  step("the response's bodyHtml contains {string}", %{args: [fragment]} = context,
    do: outcome(context, :body_html_contains, [fragment])
  )

  step("the response's bodyHtml lacks {string}", %{args: [fragment]} = context,
    do: outcome(context, :body_html_lacks, [fragment])
  )

  step(
    "every message in the response has body HTML containing {string}",
    %{args: [fragment]} = context,
    do: outcome(context, :every_message_body_html_contains, [fragment])
  )

  step(
    "the response's bodyHtml shows the image as {string} at {string}",
    %{args: [decision, address]} = context,
    do: outcome(context, :body_html_shows_image, [decision, address])
  )

  step(
    "the subscriber receives exactly one committed-message event matching that message whose bodyHtml contains {string}",
    %{args: [fragment]} = context,
    do: outcome(context, :subscriber_event_body_html_contains, [fragment])
  )

  # The docstring is the message as typed, so its Markdown fence reaches the server unchanged.
  step(
    "the user sends this family chat message with a fresh client message ID:",
    %{docstring: body} = context,
    do: perform(context, :send_message_fresh_id, [body])
  )

  step("the response's bodyHtml marks a diagram for drawing", context,
    do: outcome(context, :body_html_marks_diagram)
  )

  step(
    "the response's bodyHtml keeps the diagram as a code block with the note {string}",
    %{args: [note]} = context,
    do: outcome(context, :body_html_keeps_diagram_note, [note])
  )

  step("the family chat quote type declares no bodyHtml field", context,
    do: outcome(context, :quote_declares_no_body_html)
  )

  # --- family_chat_operations.feature: the reply notification ---

  step(
    "one other member holds an active Web Push subscription in {string}",
    %{args: [slug]} = context,
    do: prepare(context, :one_other_active_subscription, [slug])
  )

  step("a member sends a durable family chat reply to that member's message", context,
    do: perform(context, :send_durable_reply)
  )

  step("exactly one push is sent to that subscription", context,
    do: outcome(context, :one_push_sent_to_reply_subscription)
  )

  step("the notification title and body carry no part of the quoted message", context,
    do: outcome(context, :delivery_payload_excludes_quote)
  )

  # --- family_chat_graphql.feature: Web Push refusals and malformed requests ---

  step("the signed-in session has no session digest", context,
    do: prepare(context, :session_without_digest)
  )

  step("the caller runs each Web Push subscription operation", context,
    do: perform(context, :run_web_push_operations)
  )

  step(
    "each Web Push subscription operation answers a safe {string} error reading {string}",
    %{args: [code, message]} = context,
    do: outcome(context, :web_push_operations_refused, [code, message])
  )

  step("the Web Push configuration query still answers the caller", context,
    do: outcome(context, :web_push_configuration_answers)
  )

  step("no Web Push subscription is stored", context,
    do: outcome(context, :no_web_push_subscription_stored)
  )

  step("the user sends a GraphQL request that is a GET", context,
    do: perform(context, :send_graphql_get)
  )

  step("the user sends a GraphQL request that is a body typed as plain text", context,
    do: perform(context, :send_graphql_text_plain)
  )

  step("the user sends a GraphQL request that is a body over 64 KiB", context,
    do: perform(context, :send_graphql_oversized)
  )

  step("the user sends a GraphQL request that is malformed JSON", context,
    do: perform(context, :send_graphql_malformed_json)
  )

  step(
    "the response has HTTP status {int} and a safe {string} error",
    %{args: [status, code]} = context,
    do: outcome(context, :refused_with_status_and_code, [status, code])
  )

  step("the response carries no GraphQL data", context,
    do: outcome(context, :carries_no_graphql_data)
  )

  # --- family_chat_operations.feature: the push payload ---

  step(
    "a member sends a family chat message of 300 characters with runs of spaces and line breaks",
    context,
    do: perform(context, :send_long_spaced_message)
  )

  step("a member sends a family chat message of exactly 120 characters", context,
    do: perform(context, :send_exact_120_message)
  )

  step(
    "the push payload of the 300 character message has a body of single spaces, 119 characters and one ellipsis",
    context,
    do: outcome(context, :long_payload_body_truncated)
  )

  step(
    "the push payload of the 120 character message has its body unchanged",
    context,
    do: outcome(context, :exact_payload_body_unchanged)
  )

  step("every push payload's title is the sender's display name at commit", context,
    do: outcome(context, :payload_titles_sender_name)
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
