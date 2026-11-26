defmodule BnestAppWeb.Schema.Types.WebPushTypes do
  @moduledoc false

  use Absinthe.Schema.Notation

  object :web_push_configuration do
    field(:available, non_null(:boolean))
    field(:public_key, :string)
  end

  object :web_push_subscription do
    field(:enabled, non_null(:boolean))
    field(:expiration_time, :datetime)
  end
end
