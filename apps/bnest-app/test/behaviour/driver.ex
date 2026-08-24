defmodule BnestApp.Behaviour.Driver do
  @moduledoc false

  @callback open(map(), String.t()) :: map()
  @callback heading_visible?(map(), String.t()) :: boolean()
  @callback text_visible?(map(), String.t()) :: boolean()
  @callback conversation_empty?(map()) :: boolean()
  @callback composer_available?(map()) :: boolean()
  @callback composer_unavailable?(map()) :: boolean()
  @callback attempt_empty_message(map()) :: map()
  @callback send_message(map(), String.t()) :: map()
  @callback attempt_message_before_finished(map(), String.t()) :: map()
  @callback visitor_message_visible?(map(), String.t()) :: boolean()
  @callback visitor_message_absent?(map(), String.t()) :: boolean()
  @callback stream_codex_response(map()) :: {boolean(), map()}
  @callback second_codex_response_visible?(map()) :: boolean()
  @callback reject_message(map(), String.t()) :: map()
  @callback report_codex_error(map(), String.t()) :: map()
  @callback alert_visible?(map(), String.t()) :: boolean()
  @callback reload(map()) :: map()
end
