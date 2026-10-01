defmodule BnestApp.SifatAllah.Adapters do
  @moduledoc """
  Sifat Allah's outbound adapters: the learning-progress store over Storage's records, and
  the record kind that registers that progress with Storage. Only configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.SifatAllah, BnestApp.Storage],
    exports: :all
end
