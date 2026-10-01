defmodule BnestApp.CodexChat.Adapters do
  @moduledoc """
  Codex chat's outbound adapters: the Codex agent session and model discovery over the local
  Node runners, the transcript store over Storage's records, and the record kind that
  registers the transcript with Storage. Only configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.CodexChat, BnestApp.Storage, Jason],
    exports: :all
end
