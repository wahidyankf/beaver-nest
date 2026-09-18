defmodule BnestApp.PushNotifications.RetentionJob do
  @moduledoc """
  Thin Scheduler-callable adapter (`BnestApp.Scheduler.Run.execute/2`'s
  `handler.execute(claim, now)` contract, mirroring
  `BnestApp.Backup.Run.execute/2`). Zero SQL here -- tech-doc 002: "the
  Scheduler handler contains no family-chat SQL" -- every mutation happens in
  `BnestApp.PushNotifications.retain_deliveries/1`.
  """

  alias BnestApp.PushNotifications

  @spec execute(map(), DateTime.t()) :: {:ok, map()} | {:error, atom()}
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
