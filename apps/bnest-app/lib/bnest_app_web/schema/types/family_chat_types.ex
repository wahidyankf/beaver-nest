defmodule BnestAppWeb.Schema.Types.FamilyChatTypes do
  @moduledoc false

  use Absinthe.Schema.Notation

  object :family_chat_room do
    field(:id, non_null(:id))
    field(:slug, non_null(:string))
    field(:name, non_null(:string))
    field(:room_kind, non_null(:string))
    field(:member_posting_enabled, non_null(:boolean))
  end

  object :family_chat_message do
    field(:id, non_null(:id))
    field(:room_slug, non_null(:string))
    field(:sender_kind, non_null(:string))
    field(:sender_id, non_null(:id))
    field(:sender_display_name, non_null(:string))
    field(:body, non_null(:string))
    field(:committed_at, non_null(:datetime))
  end

  object :family_chat_message_connection do
    field(:nodes, non_null(list_of(non_null(:family_chat_message))))
    field(:has_older, non_null(:boolean))
    field(:has_newer, non_null(:boolean))
  end
end
