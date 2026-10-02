defmodule BnestApp.Operations.Domain do
  @moduledoc """
  The Operations domain: the admin settings panels the contexts declare. Pure: no file,
  process, clock, environment, or database access.
  """

  use Boundary, type: :strict, deps: [], exports: :all
end
