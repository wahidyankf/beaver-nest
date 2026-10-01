defmodule BnestApp.FamilyChat.Adapters.AbsintheMessagePublisher do
  @moduledoc """
  The `BnestApp.FamilyChat.Ports.MessagePublisher` over Absinthe subscriptions: publishes the
  committed message to the `familyChatMessageCommitted` field for the room's topic.

  `Phoenix.PubSub`/`Absinthe.Subscription.publish/3` reach only subscribers local to this
  BEAM node -- this app runs unclustered (no libcluster/`Node.connect`), so every broadcast
  is structurally local-only, never reaching another release slot.
  """

  @behaviour BnestApp.FamilyChat.Ports.MessagePublisher

  @impl true
  def publish(message, topic) do
    Absinthe.Subscription.publish(
      BnestAppWeb.Endpoint,
      message,
      family_chat_message_committed: topic
    )

    :ok
  rescue
    # The subscription pipeline (Absinthe.Subscription supervisor) is not
    # started outside the full Phoenix endpoint (e.g. a bare direct-store
    # call). Publication is best-effort broadcast, never a correctness
    # requirement for the commit itself.
    _not_started -> :ok
  end
end
