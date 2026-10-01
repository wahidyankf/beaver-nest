defmodule BnestApp.Preferences.Domain do
  @moduledoc """
  The Preferences domain: the allowed theme values and the stored theme-preference record.
  Pure: no file, process, clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
