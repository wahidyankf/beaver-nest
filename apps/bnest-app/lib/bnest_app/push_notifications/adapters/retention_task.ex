defmodule BnestApp.PushNotifications.Adapters.RetentionTask do
  @moduledoc """
  Inbound adapter: the scheduler task for Delivery Retention. A thin
  `BnestApp.Scheduler.Ports.Task` that configuration registers under
  `"family_chat_push_retention"`, mirroring Backup's `Adapters.ScheduledBackupTask`.
  Zero SQL here -- tech-doc 002: "the Scheduler handler contains no
  family-chat SQL" -- every mutation happens in
  `BnestApp.PushNotifications.retain_deliveries/1`. Like every task, it records
  its finished run through the Scheduler facade, with a receipt that names no
  artifact, so the run is not recovered and run again once its lease ends.
  """

  @behaviour BnestApp.Scheduler.Ports.Task

  alias BnestApp.PushNotifications
  alias BnestApp.Scheduler

  @receipt %{"artifactBasename" => nil, "artifactSha256" => nil, "artifactBytes" => nil}

  @impl Scheduler.Ports.Task
  def execute(claim, %DateTime{} = now) do
    with {:ok, result} <- PushNotifications.retain_deliveries(now),
         :ok <- Scheduler.complete_run(claim.run_id, claim.attempt, @receipt, now) do
      {:ok,
       %{
         "softDeleted" => result.soft_deleted,
         "purged" => result.purged,
         "remainingActive" => result.remaining_active
       }}
    end
  end
end
