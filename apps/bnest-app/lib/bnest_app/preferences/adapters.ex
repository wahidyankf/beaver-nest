defmodule BnestApp.Preferences.Adapters do
  @moduledoc """
  Preferences' outbound adapters: the theme-preference store over Storage's records. Only
  configuration names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Preferences, BnestApp.Storage],
    exports: :all
end
