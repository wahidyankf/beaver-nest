defmodule BnestApp.SifatAllah.Domain do
  @moduledoc """
  The Sifat Allah domain: the curriculum of the 20 attribute pairs, the learner's progress
  and its quiz rules, and the stored learning-progress record. Pure: no file, process,
  clock, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
