defmodule BnestApp.FamilyChat.Domain do
  @moduledoc """
  The Family Chat domain: the committed message and its quote, who may read and post in a
  room, and the pagination cursor. Pure: no file, process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
