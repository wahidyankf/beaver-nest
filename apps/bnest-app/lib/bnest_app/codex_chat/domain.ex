defmodule BnestApp.CodexChat.Domain do
  @moduledoc """
  The Codex chat domain: the conversation transcript and its snapshot, the stored transcript
  record, the preferred model and its labels, and who may pick models or let Codex write to
  the repository. Pure: no file, process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
