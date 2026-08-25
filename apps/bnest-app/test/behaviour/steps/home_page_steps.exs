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

  step "the model selector lists every available Codex model", context do
    assert context.behaviour_driver.model_selector_lists_all?(context)
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

  step "the reasoning effort selector is available", context do
    assert context.behaviour_driver.effort_selector_available?(context)
    context
  end

  step "the reasoning effort selector is unavailable", context do
    assert context.behaviour_driver.effort_selector_unavailable?(context)
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

  step "the visitor attempts to send an empty message", context do
    context.behaviour_driver.attempt_empty_message(context)
  end

  step "the visitor sends {string}", %{args: [message]} = context do
    context.behaviour_driver.send_message(context, message)
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

  step "Codex reports the error {string}", %{args: [message]} = context do
    context.behaviour_driver.report_codex_error(context, message)
  end

  step "the page displays the alert {string}", %{args: [message]} = context do
    assert context.behaviour_driver.alert_visible?(context, message)
    context
  end

  step "the visitor reloads the page", context do
    context.behaviour_driver.reload(context)
  end

  step "the visitor clears the chat", context do
    context.behaviour_driver.clear_chat(context)
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

  step "the visitor swipes left on the study card", context do
    context.behaviour_driver.swipe_study_card_left(context)
  end

  step "the visitor swipes right on the study card", context do
    context.behaviour_driver.swipe_study_card_right(context)
  end

  step "the visitor returns to the mission", context do
    context.behaviour_driver.return_to_mission(context)
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

  step "the visitor starts a quiz", context do
    context.behaviour_driver.start_quiz(context)
  end

  step "the quiz puts correct answers in varied positions", context do
    assert context.behaviour_driver.quiz_answer_positions_vary?(context)
    context
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
end
