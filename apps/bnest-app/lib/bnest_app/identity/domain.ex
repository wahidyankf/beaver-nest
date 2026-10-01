defmodule BnestApp.Identity.Domain do
  @moduledoc """
  The Identity domain: the username and password rules, browser-session records, and the
  authorization policy. Pure: no file, process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
