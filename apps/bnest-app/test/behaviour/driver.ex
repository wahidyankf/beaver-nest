defmodule BnestApp.Behaviour.Driver do
  @moduledoc false

  @callback open(map(), String.t()) :: map()
  @callback heading_visible?(map(), String.t()) :: boolean()
  @callback text_visible?(map(), String.t()) :: boolean()
end
