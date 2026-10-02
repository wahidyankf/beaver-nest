defmodule BnestApp.PushNotifications.Adapters.RetentionTask do
  @moduledoc """
  Inbound adapter: the scheduler task for Delivery Retention. A thin
  `BnestApp.Scheduler.Ports.Task` that configuration registers under
  `"family_chat_push_retention"`, mirroring `BnestApp.Backup.Run.execute/2`.
  Zero SQL here -- tech-doc 002: "the Scheduler handler contains no
  family-chat SQL" -- every mutation happens in
  `BnestApp.PushNotifications.retain_deliveries/1`.
  """

  @behaviour BnestApp.Scheduler.Ports.Task

  alias BnestApp.PushNotifications

  @impl BnestApp.Scheduler.Ports.Task
  def execute(_claim, %DateTime{} = now) do
    case PushNotifications.retain_deliveries(now) do
      {:ok, result} ->
        {:ok,
         %{
           "softDeleted" => result.soft_deleted,
           "purged" => result.purged,
           "remainingActive" => result.remaining_active
         }}
    end
  end
end
