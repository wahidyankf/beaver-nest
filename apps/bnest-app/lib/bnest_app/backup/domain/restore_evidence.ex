defmodule BnestApp.Backup.Domain.RestoreEvidence do
  @moduledoc """
  The redacted evidence a restore reports: the restored active room, its message IDs in
  order, how many push subscriptions it holds and which delivery states occur. Structural
  counts, IDs and states only, never a message body or push credential.
  """

  @typedoc "What a restored copy holds, as a database snapshot reads it back."
  @type facts :: %{
          room: %{
            id: pos_integer(),
            slug: String.t(),
            name: String.t(),
            member_posting_enabled: boolean()
          },
          message_ids: [pos_integer()],
          subscription_count: non_neg_integer(),
          delivery_states: [String.t()]
        }

  @doc "The evidence document of what a restored copy holds."
  @spec document(facts()) :: map()
  def document(%{room: room} = facts) do
    %{
      "room" => %{
        "id" => room.id,
        "slug" => room.slug,
        "name" => room.name,
        "memberPostingEnabled" => room.member_posting_enabled
      },
      "orderedMessageIds" => facts.message_ids,
      "subscriptionCount" => facts.subscription_count,
      "deliveryStates" => facts.delivery_states
    }
  end
end
