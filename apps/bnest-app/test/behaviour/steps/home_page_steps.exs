defmodule BnestApp.Behaviour.ChatSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step "a visitor opens {string}", %{args: [route]} = context do
    context.behaviour_driver.open(context, route)
  end

  step "the page displays the heading {string}", %{args: [heading]} = context do
    assert context.behaviour_driver.heading_visible?(context, heading)
    context
  end

  step "the page displays the text {string}", %{args: [text]} = context do
    assert context.behaviour_driver.text_visible?(context, text)
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
end
