defmodule BnestApp.Operations.Adapters do
  @moduledoc """
  Operations' outbound adapters: the release environment read from the operating system's
  environment variables, the local process registry and the peer node. Only configuration
  names them.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Operations],
    exports: :all
end
