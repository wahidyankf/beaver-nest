defmodule BnestApp.Behaviour.ChatSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step "a visitor opens {string}", %{args: [route]} = context do
    context.behaviour_driver.open(context, route)
  end

  step "the page displays the Beaver Nest logo", context do
    assert context.behaviour_driver.brand_logo_visible?(context)
    context
  end

  step "Beaver Nest is ready to install as an app", context do
    assert context.behaviour_driver.installable_as_app?(context)
    context
  end

  step "the page displays the heading {string}", %{args: [heading]} = context do
    assert context.behaviour_driver.heading_visible?(context, heading)
    context
  end

  step "the page displays the text {string}", %{args: [text]} = context do
    assert context.behaviour_driver.text_visible?(context, text)
    context
  end

  step "the page offers the {string} link to {string}", %{args: [label, path]} = context do
    assert context.behaviour_driver.chat_entry_link_visible?(context, label, path)
    context
  end

  step "the home header and hero do not overlap", context do
    assert context.behaviour_driver.home_controls_arranged?(context)
    context
  end

  step "the visitor follows the Beaver Nest home link", context do
    context.behaviour_driver.follow_brand_home_link(context)
  end

  step "the page does not offer browser-data migration", context do
    assert context.behaviour_driver.data_migration_entry_absent?(context)
    context
  end

  # The names are listed in the picker's order, separated by ", ".
  step "the model selector lists only {string}", %{args: [names]} = context do
    assert context.behaviour_driver.model_selector_lists_only?(
             context,
             String.split(names, ", ")
           )

    context
  end

  step "the selected model is {string}", %{args: [model]} = context do
    assert context.behaviour_driver.selected_model?(context, model)
    context
  end

  step "the reasoning effort selector lists every effort supported by the selected model",
       context do
    assert context.behaviour_driver.effort_selector_lists_supported?(context)
    context
  end

  step "the selected reasoning effort is {string}", %{args: [effort]} = context do
    assert context.behaviour_driver.selected_effort?(context, effort)
    context
  end

  step "the model selector is available", context do
    assert context.behaviour_driver.model_selector_available?(context)
    context
  end

  step "the model selector is unavailable", context do
    assert context.behaviour_driver.model_selector_unavailable?(context)
    context
  end

  step "the model selector is not shown", context do
    assert context.behaviour_driver.model_selector_hidden?(context)
    context
  end

  step "the reasoning effort selector is available", context do
    assert context.behaviour_driver.effort_selector_available?(context)
    context
  end

  step "the reasoning effort selector is unavailable", context do
    assert context.behaviour_driver.effort_selector_unavailable?(context)
    context
  end

  step "the reasoning effort selector is not shown", context do
    assert context.behaviour_driver.effort_selector_hidden?(context)
    context
  end

  step "the visitor selects the model {string}", %{args: [model]} = context do
    context.behaviour_driver.select_model(context, model)
  end

  step "the visitor selects the reasoning effort {string}", %{args: [effort]} = context do
    context.behaviour_driver.select_effort(context, effort)
  end

  step "the conversation is empty", context do
    assert context.behaviour_driver.conversation_empty?(context)
    context
  end

  step "the message composer is available", context do
    assert context.behaviour_driver.composer_available?(context)
    context
  end

  step "the message composer is unavailable", context do
    assert context.behaviour_driver.composer_unavailable?(context)
    context
  end

  step "the clear chat control is available", context do
    assert context.behaviour_driver.clear_chat_control_available?(context)
    context
  end

  step "the chat controls do not overlap", context do
    assert context.behaviour_driver.chat_controls_arranged?(context)
    context
  end

  step "repository access is shown as read-only", context do
    assert context.behaviour_driver.repository_access_read_only?(context)
    context
  end

  step "repository access is shown as write enabled", context do
    assert context.behaviour_driver.repository_access_write_enabled?(context)
    context
  end

  step "the repository write control is available", context do
    assert context.behaviour_driver.repository_write_control_available?(context)
    context
  end

  step "the repository write control is not shown", context do
    assert context.behaviour_driver.repository_write_control_hidden?(context)
    context
  end

  step "the visitor enables repository writes", context do
    context.behaviour_driver.enable_repository_writes(context)
  end

  step "the visitor disables repository writes", context do
    context.behaviour_driver.disable_repository_writes(context)
  end

  step "the visitor attempts to send an empty message", context do
    context.behaviour_driver.attempt_empty_message(context)
  end

  step "the visitor sends {string}", %{args: [message]} = context do
    context.behaviour_driver.send_message(context, message)
  end

  # The pointer is a browser media state the server never receives. The step records the touch pointer so the scenario
  # reads as the browser runs it. The chord itself is not proven here: the Vitest key rows (Codex and Family) and the
  # browser rows of bnest-app-fe-e2e prove that Shift+Enter sends on a touch pointer. At this layer the scenario proves
  # only that its send runs with the declared pointer.
  step "the visitor's pointer is a touch pointer", context do
    Map.put(context, :visitor_pointer, :touch)
  end

  step "the visitor submits {string} with Shift+Enter", %{args: [message]} = context do
    context.behaviour_driver.submit_with_shift_enter(context, message)
  end

  step "the visitor attempts to send {string} before Codex finishes",
       %{args: [message]} = context do
    context.behaviour_driver.attempt_message_before_finished(context, message)
  end

  step "the conversation displays the visitor message {string}",
       %{args: [message]} = context do
    assert context.behaviour_driver.visitor_message_visible?(context, message)
    context
  end

  step "the conversation does not display the visitor message {string}",
       %{args: [message]} = context do
    assert context.behaviour_driver.visitor_message_absent?(context, message)
    context
  end

  step "a Codex response appears incrementally", context do
    {streamed?, context} = context.behaviour_driver.stream_codex_response(context)
    assert streamed?
    context
  end

  step "the in-progress turn resumes once or fails safely without duplication", context do
    assert context.behaviour_driver.in_progress_turn_recovered?(context)
    context
  end

  step "Codex reports public progress", context do
    context.behaviour_driver.report_public_codex_progress(context)
  end

  step "the conversation shows the public Codex reasoning summary", context do
    assert context.behaviour_driver.codex_reasoning_summary_visible?(context)
    context
  end

  step "the conversation preserves the Codex progress beside the final answer", context do
    assert context.behaviour_driver.codex_progress_preserved_beside_final_answer?(context)
    context
  end

  step "the conversation displays one completed Codex response", context do
    assert context.behaviour_driver.one_completed_codex_response_visible?(context)
    context
  end

  step "the conversation displays a second Codex response", context do
    assert context.behaviour_driver.second_codex_response_visible?(context)
    context
  end

  step "Codex rejects the visitor message {string}", %{args: [message]} = context do
    context.behaviour_driver.reject_message(context, message)
  end

  step "Codex fails the visitor message {string} with the error {string}",
       %{args: [message, error]} = context do
    context = context.behaviour_driver.send_message(context, message)
    context.behaviour_driver.report_codex_error(context, error)
  end

  step "the page displays the alert {string}", %{args: [message]} = context do
    assert context.behaviour_driver.alert_visible?(context, message)
    context
  end

  step "the visitor types {string} without sending", %{args: [draft]} = context do
    context.behaviour_driver.type_draft(context, draft)
  end

  step "the message composer contains {string}", %{args: [draft]} = context do
    assert context.behaviour_driver.composer_contains?(context, draft)
    context
  end

  step "the current route is {string}", %{args: [route]} = context do
    assert context.behaviour_driver.current_route?(context, route)
    context
  end

  step "the visitor reconnects after a deployment", context do
    context.behaviour_driver.reconnect(context)
  end

  # A dropped LiveView socket remounts the saved chat on the same server, as a reconnect after a deployment does.
  step "the visitor's live connection drops and returns", context do
    context.behaviour_driver.reconnect(context)
  end

  step "{int} synthetic visitors across {int} recovery groups have distinct drafts on {string}",
       %{args: [client_count, group_count, route]} = context do
    context.behaviour_driver.prepare_recovery_group(
      context,
      client_count,
      group_count,
      route
    )
  end

  step "every recovery-group visitor reconnects after a deployment", context do
    context.behaviour_driver.reconnect_recovery_group(context)
  end

  step "every recovery-group visitor keeps its route and draft", context do
    assert context.behaviour_driver.recovery_group_preserved?(context)
    context
  end

  step "the visitor reloads the page", context do
    context.behaviour_driver.reload(context)
  end

  step "the visitor clears the chat", context do
    context.behaviour_driver.clear_chat(context)
  end

  step "the visitor starts a new chat", context do
    context.behaviour_driver.start_new_chat(context)
  end

  step "the conversation list shows {string}", %{args: [title]} = context do
    assert context.behaviour_driver.conversation_list_shows?(context, title)
    context
  end

  step "the conversation list does not show {string}", %{args: [title]} = context do
    refute context.behaviour_driver.conversation_list_shows?(context, title)
    context
  end

  step "the visitor opens the conversation {string}", %{args: [title]} = context do
    context.behaviour_driver.open_conversation(context, title)
  end

  step "the visitor deletes the conversation {string}", %{args: [title]} = context do
    context.behaviour_driver.delete_conversation(context, title)
  end

  step "the visitor renames the conversation {string} to {string}",
       %{args: [title, next]} = context do
    context.behaviour_driver.rename_conversation(context, title, next)
  end

  step "the study mode is available", context do
    assert context.behaviour_driver.study_mode_available?(context)
    context
  end

  step "the quiz mode is available", context do
    assert context.behaviour_driver.quiz_mode_available?(context)
    context
  end

  step "the visitor starts learning", context do
    context.behaviour_driver.start_learning(context)
  end

  step "the visitor has remembered every Sifat Allah pair", context do
    context.behaviour_driver.remember_every_sifat_pair(context)
  end

  step "the visitor has remembered the first pair by {string}", %{args: [how]} = context do
    remember_first_pair(context, how)
  end

  step "the visitor swipes left on the study card", context do
    context.behaviour_driver.swipe_study_card_left(context)
  end

  step "the visitor swipes right on the study card", context do
    context.behaviour_driver.swipe_study_card_right(context)
  end

  step "the visitor returns to the mission", context do
    context.behaviour_driver.return_to_mission(context)
  end

  step "the visitor goes back in the browser", context do
    context.behaviour_driver.browser_back_to_mission(context)
  end

  step "the study card shows {string} and {string}", %{args: [name, meaning]} = context do
    assert context.behaviour_driver.study_card_shows?(context, name, meaning)
    context
  end

  step "the study card uses green for wajib and orange for mustahil", context do
    assert context.behaviour_driver.study_card_colors_attributes?(context)
    context
  end

  step "the visitor marks the current pair as remembered", context do
    context.behaviour_driver.mark_current_pair_remembered(context)
  end

  step "the progress shows {string}", %{args: [progress]} = context do
    assert context.behaviour_driver.progress_shows?(context, progress)
    context
  end

  step "the visitor asks to reset Sifat Allah progress", context do
    context.behaviour_driver.ask_reset_sifat_progress(context)
  end

  step "the visitor confirms resetting Sifat Allah progress", context do
    context.behaviour_driver.confirm_reset_sifat_progress(context)
  end

  step "the visitor starts a quiz", context do
    context.behaviour_driver.start_quiz(context)
  end

  step "the quiz puts correct answers in varied positions", context do
    assert context.behaviour_driver.quiz_answer_positions_vary?(context)
    context
  end

  step "the quiz answer choices are locked", context do
    assert context.behaviour_driver.quiz_answer_choices_locked?(context)
    context
  end

  step "five seconds pass after a quiz answer", context do
    context.behaviour_driver.wait_for_quiz_auto_advance(context)
  end

  step "the visitor starts learned review", context do
    context.behaviour_driver.start_learned_review(context)
  end

  step "the visitor starts focused review", context do
    context.behaviour_driver.start_focused_review(context)
  end

  step "the visitor swipes left on the quiz question", context do
    context.behaviour_driver.swipe_quiz_question_left(context)
  end

  step "the visitor swipes right on the quiz question", context do
    context.behaviour_driver.swipe_quiz_question_right(context)
  end

  step "the visitor continues to the next quiz question", context do
    context.behaviour_driver.next_quiz_question(context)
  end

  step "the visitor reaches quiz question number {int}", %{args: [number]} = context do
    Enum.reduce(1..(number - 1)//1, context, fn _step, context ->
      context.behaviour_driver.next_quiz_question(context)
    end)
  end

  step "the visitor answers {string}", %{args: [answer]} = context do
    context.behaviour_driver.answer_quiz(context, answer)
  end

  step "the visitor answers {string} in focused review", %{args: [answer]} = context do
    context.behaviour_driver.answer_focused_review(context, answer)
  end

  step "the visitor continues focused review", context do
    context.behaviour_driver.next_focused_review(context)
  end

  step "the revision list contains {string}", %{args: [name]} = context do
    assert context.behaviour_driver.revision_list_contains?(context, name)
    context
  end

  step "Codex streams the first part of the reply", context do
    context.behaviour_driver.stream_first_codex_part(context)
  end

  step "Codex streams the rest of the reply", context do
    context.behaviour_driver.stream_rest_of_codex_reply(context)
  end

  step "the latest Codex reply is still streaming", context do
    assert context.behaviour_driver.latest_codex_reply_streaming?(context)
    context
  end

  step "the latest Codex reply is complete", context do
    assert context.behaviour_driver.latest_codex_reply_complete?(context)
    context
  end

  step "the latest Codex reply contains a {string} element with the text {string}",
       %{args: [element, text]} = context do
    assert context.behaviour_driver.latest_codex_reply_contains_element_with_text?(
             context,
             element,
             text
           )

    context
  end

  step "the latest Codex reply contains no {string} element", %{args: [element]} = context do
    assert context.behaviour_driver.latest_codex_reply_lacks_element?(context, element)
    context
  end

  step "the latest Codex reply shows the text {string}", %{args: [text]} = context do
    assert context.behaviour_driver.latest_codex_reply_shows_text?(context, text)
    context
  end

  step "the latest Codex reply shows the text {string} without a link",
       %{args: [text]} = context do
    assert context.behaviour_driver.latest_codex_reply_shows_text_without_link?(context, text)
    context
  end

  step "the latest Codex reply does not contain the text {string}", %{args: [text]} = context do
    assert context.behaviour_driver.latest_codex_reply_lacks_text?(context, text)
    context
  end

  step "the latest Codex reply has no link whose address starts with {string}",
       %{args: [prefix]} = context do
    assert context.behaviour_driver.latest_codex_reply_lacks_link_to_address?(context, prefix)
    context
  end

  step "the latest Codex reply links {string} to {string}", %{args: [label, address]} = context do
    assert context.behaviour_driver.latest_codex_reply_links_to?(context, label, address)
    context
  end

  step "the link {string} in the latest Codex reply opens in a new tab without sharing the page",
       %{args: [label]} = context do
    assert context.behaviour_driver.link_opens_in_new_tab_privately?(context, label)
    context
  end

  step "the latest Codex reply shows two checked and two unchecked task checkboxes",
       context do
    assert context.behaviour_driver.latest_codex_reply_task_checkboxes?(context, 2, 2)
    context
  end

  step "the latest Codex reply lays out its table, task list, link and image inside the bubble",
       context do
    assert context.behaviour_driver.latest_codex_reply_lays_out_inside_bubble?(context)
    context
  end

  step "the latest Codex reply holds a wide table and an image", context do
    assert context.behaviour_driver.latest_codex_reply_holds_wide_content?(context)
    context
  end

  step "the latest Codex reply shows an inline image with the alt text {string}",
       %{args: [alt]} = context do
    assert context.behaviour_driver.latest_codex_reply_shows_inline_image?(context, alt)
    context
  end

  step "the latest Codex reply loads the inline image {string} from {string}",
       %{args: [alt, address]} = context do
    assert context.behaviour_driver.latest_codex_reply_loads_inline_image?(context, alt, address)
    context
  end

  step "the latest Codex reply shows the repository image {string}", %{args: [path]} = context do
    assert context.behaviour_driver.latest_codex_reply_shows_repository_image?(context, path)
    context
  end

  step "the latest Codex reply keeps the diagram as a plain code block", context do
    assert context.behaviour_driver.latest_codex_reply_keeps_plain_code_blocks?(context, 1)
    context
  end

  step "the latest Codex reply keeps {int} diagrams as plain code blocks",
       %{args: [count]} = context do
    assert context.behaviour_driver.latest_codex_reply_keeps_plain_code_blocks?(context, count)
    context
  end

  step "the latest Codex reply does not mark a diagram for drawing", context do
    assert context.behaviour_driver.latest_codex_reply_marks_diagrams?(context, 0)
    context
  end

  step "the latest Codex reply marks the diagram for drawing", context do
    assert context.behaviour_driver.latest_codex_reply_marks_diagrams?(context, 1)
    context
  end

  step "the latest Codex reply marks {int} diagrams for drawing", %{args: [count]} = context do
    assert context.behaviour_driver.latest_codex_reply_marks_diagrams?(context, count)
    context
  end

  step "the visitor requests the repository image {string}", %{args: [path]} = context do
    context.behaviour_driver.request_repository_image(context, path)
  end

  step "the image response has status {int}", %{args: [status]} = context do
    assert context.behaviour_driver.image_response_status?(context, status)
    context
  end

  step "the image response has content type {string}", %{args: [type]} = context do
    assert context.behaviour_driver.image_response_content_type?(context, type)
    context
  end

  step "the image response is an empty not found response", context do
    assert context.behaviour_driver.image_response_empty_not_found?(context)
    context
  end

  step "the image response redirects to {string}", %{args: [location]} = context do
    assert context.behaviour_driver.image_response_redirects_to?(context, location)
    context
  end

  step "the repository holds a file {string} with the content {string}",
       %{args: [path, content]} = context do
    context.behaviour_driver.repository_holds_file(context, path, content)
  end

  step "the repository holds an image at {string}", %{args: [path]} = context do
    context.behaviour_driver.repository_holds_image(context, path)
  end

  step "the repository holds a symbolic link {string} to {string}",
       %{args: [link, target]} = context do
    context.behaviour_driver.repository_holds_symbolic_link(context, link, target)
  end

  step "the repository holds a file {string} of {int} bytes", %{args: [path, bytes]} = context do
    context.behaviour_driver.repository_holds_sized_file(context, path, bytes)
  end

  # --- phase-8 FE ADD rows ---

  step "a visitor opens the home page", context do
    context.behaviour_driver.open(context, "/")
  end

  step "the page does not offer the {string} link to {string}",
       %{args: [label, path]} = context do
    outcome(context, :chat_entry_link_absent, [label, path])
  end

  step "the same user opens {string} in another tab", %{args: [route]} = context do
    perform(context, :open_second_session, [route])
  end

  step "the other tab shows the visitor message {string}", %{args: [message]} = context do
    outcome(context, :second_session_message, [message])
  end

  step "the other tab shows a completed Codex response", context do
    outcome(context, :second_session_response)
  end

  step "the Codex image reply completes", context do
    perform(context, :complete_image_reply)
  end

  step "the visitor signs out", context do
    perform(context, :sign_out)
  end

  step "the runner {string}", %{args: [event]} = context do
    perform(context, :runner_event, [event])
  end

  step "the runner reports {string} to its owner", %{args: [alert]} = context do
    outcome(context, :runner_reported, [alert])
  end

  step "the transcript store rejects saves", context do
    prepare(context, :transcript_saves_rejected)
  end

  step "the stored transcript is unchanged", context do
    outcome(context, :stored_transcript_unchanged)
  end

  step "the transcript store reports a stale save", context do
    prepare(context, :transcript_saves_stale)
  end

  step "Codex cannot open a write session", context do
    prepare(context, :write_session_refused)
  end

  step "local Codex lists no {string} for a {string}", %{args: [model, role]} = context do
    prepare(context, :model_missing_for_role, [model, role])
  end

  step "no Codex session opens", context do
    outcome(context, :no_codex_session)
  end

  step "the latest Codex reply shows the generated image {string} inline",
       %{args: [file]} = context do
    outcome(context, :generated_image_inline, [file])
  end

  step "the family room shows the same reference as text", context do
    outcome(context, :family_reference_as_text)
  end

  step "the visitor requests the generated image {string}", %{args: [file]} = context do
    perform(context, :request_generated_image, [file])
  end

  step "the visitor requests the generated image {string} as one encoded segment",
       %{args: [file]} = context do
    perform(context, :request_generated_image_encoded, [file])
  end

  step "the visitor requests the generated image path {string}", %{args: [path]} = context do
    perform(context, :request_generated_image_path, [path])
  end

  step "a generated image {string} is saved", %{args: [file]} = context do
    prepare(context, :generated_image_saved, [file])
  end

  step "a generated image {string} holding JPEG bytes is saved", %{args: [file]} = context do
    prepare(context, :generated_jpeg_saved, [file])
  end

  step "no generated image is saved", context do
    prepare(context, :generated_images_cleared)
  end

  step "the repository holds its logo", context do
    outcome(context, :repository_logo_present)
  end

  step "the image answer is private-cached and sandboxed", context do
    outcome(context, :image_cached_and_sandboxed)
  end

  step "the image answer echoes no request header", context do
    outcome(context, :image_echoes_no_header)
  end

  step "the web manifest names Beaver Nest as a standalone app", context do
    outcome(context, :manifest_names_app)
  end

  step "each manifest icon loads", context do
    outcome(context, :manifest_icons_load)
  end

  step "a visitor requests the service worker script", context do
    perform(context, :request_service_worker)
  end

  step "the worker precaches the manifest, app CSS, app JS and both icons under {string}",
       %{args: [cache]} = context do
    outcome(context, :worker_precaches_shell, [cache])
  end

  step "the worker never precaches {string}", %{args: [path]} = context do
    outcome(context, :worker_never_precaches, [path])
  end

  step "activating the worker deletes every other cache name", context do
    outcome(context, :worker_activate_deletes)
  end

  step "the room answers not found with the body {string}", %{args: [body]} = context do
    outcome(context, :room_not_found_body, [body])
  end

  step "the room reveals no room name", context do
    outcome(context, :room_reveals_no_name)
  end

  defp prepare(context, state, args \\ []),
    do: context.behaviour_driver.prepare_behaviour(context, state, args)

  defp perform(context, state, args \\ []),
    do: context.behaviour_driver.perform_behaviour(context, state, args)

  defp outcome(context, state, args \\ []) do
    assert context.behaviour_driver.behaviour_outcome?(context, state, args)
    context
  end

  # BN-SIFAT-16: a rejected progress save keeps the earlier saved progress.

  step("a visitor with saved Sifat Allah progress studies the next pair", context,
    do: prepare(context, :sifat_saved_studying, [])
  )

  step("the progress store rejects saves", context,
    do: perform(context, :reject_progress_saves, [])
  )

  step("the visitor marks the current pair while saves fail", context,
    do: perform(context, :mark_pair_while_failing, [])
  )

  step("the page shows the failed save notice", context,
    do: outcome(context, :failed_save_notice, [])
  )

  step("the progress shows the earlier saved progress", context,
    do: outcome(context, :earlier_progress_shown, [])
  )

  # BN-SIFAT-17: where progress is stored for the account user and the local browser user.

  step("the signed-in child is ready", context, do: prepare(context, :sifat_account_ready, []))

  step("the local browser is ready", context, do: prepare(context, :sifat_browser_ready, []))

  step("the revision page opens", context, do: perform(context, :open_revision_page, []))

  step("the page shows the storage note {string}", %{args: [message]} = context,
    do: outcome(context, :storage_note_shown, [message])
  )

  # A pair is remembered by the study card's mark, or by a correct answer to the first quiz
  # question, and the visitor is back on the mission afterwards.
  defp remember_first_pair(context, "study mark") do
    driver = context.behaviour_driver

    context
    |> driver.start_learning()
    |> driver.mark_current_pair_remembered()
    |> driver.return_to_mission()
  end

  defp remember_first_pair(context, "a correct answer") do
    driver = context.behaviour_driver

    context
    |> driver.start_quiz()
    |> driver.answer_quiz("Ada")
    |> driver.return_to_mission()
  end
end
