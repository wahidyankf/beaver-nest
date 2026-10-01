defmodule BnestApp.Test.InMemory.MessagePublisher do
  @moduledoc """
  A recording `BnestApp.FamilyChat.Ports.MessagePublisher`. A commit publishes in the
  caller's process, so each publish is sent to that process as
  `{:family_chat_published, topic, message}` for the test to assert.
  """

  @behaviour BnestApp.FamilyChat.Ports.MessagePublisher

  @impl true
  def publish(message, topic) do
    send(self(), {:family_chat_published, topic, message})
    :ok
  end

  @doc """
  Drops every publish recorded in the calling process so far, so a retried scenario starts
  with none left over from its failed attempt.
  """
  @spec forget_published() :: :ok
  def forget_published do
    receive do
      {:family_chat_published, _topic, _message} -> forget_published()
    after
      0 -> :ok
    end
  end
end
