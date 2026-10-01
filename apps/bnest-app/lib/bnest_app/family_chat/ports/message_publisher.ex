defmodule BnestApp.FamilyChat.Ports.MessagePublisher do
  @moduledoc """
  Broadcasts a committed message to the subscribers of its room's topic.

  Publication is best effort: it never fails the commit that triggered it, so an
  implementation returns `:ok` even when no subscriber can be reached. A broadcast reaches
  only subscribers connected to this node.
  """

  @callback publish(message :: map(), topic :: String.t()) :: :ok
end
