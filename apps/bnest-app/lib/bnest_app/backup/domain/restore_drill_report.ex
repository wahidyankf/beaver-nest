defmodule BnestApp.Backup.Domain.RestoreDrillReport do
  @moduledoc """
  The words of one restore drill: what `mix bnest.backup.restore_drill` prints and whether it
  exits zero. Every number is derived from the redacted evidence a restore returns
  (`BnestApp.Backup.Domain.RestoreEvidence`), so a report holds counts, an order and delivery
  states only: no path, artifact name, room name or identifier, message ID or body, and no
  push credential. A failure is one fixed line that never carries the failure's own message.

  A drill exits zero only when the copy held one readable room, its messages read back in
  strictly ascending order, and the restore left no root behind in the temporary directory.

  Pure: the evidence and the roots found are what the caller read.
  """

  @typedoc """
  What the drill found: a restore with its evidence document (JSON) and the restore roots left
  behind, a target the drill refused, or a failure.
  """
  @type outcome ::
          {:restored, evidence :: String.t(), left_behind :: [String.t()]}
          | :refused
          | {:error, :destination_unreadable | :restore_failed}

  @type report :: %{exit_status: 0 | 1, lines: [String.t()]}

  @restored "Restore drill: restored the artifact into a fresh isolated root"

  @doc "The lines and the exit status of an outcome."
  @spec report(outcome()) :: report()
  def report({:restored, evidence, left_behind}) do
    document = Jason.decode!(evidence)
    rooms = if is_map(document["room"]), do: 1, else: 0
    message_ids = document["orderedMessageIds"]
    ascending? = ascending?(message_ids)

    %{
      exit_status: if(rooms == 1 and ascending? and left_behind == [], do: 0, else: 1),
      lines: [
        @restored,
        "Rooms readable: #{rooms}",
        messages_line(length(message_ids), ascending?),
        "Push subscriptions: #{document["subscriptionCount"]}",
        "Delivery states: " <> states(document["deliveryStates"]),
        if(left_behind == [], do: "Restore root: removed", else: "Restore root: not removed")
      ]
    }
  end

  def report(:refused) do
    failure(
      "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."
    )
  end

  def report({:error, :destination_unreadable}),
    do: failure("Restore drill: the backup destination could not be read.")

  def report({:error, :restore_failed}),
    do: failure("Restore drill: the artifact could not be restored.")

  defp failure(line), do: %{exit_status: 1, lines: [line]}

  # Strictly ascending: an ID that repeats or goes back is an order the copy does not hold.
  defp ascending?(ids),
    do: ids |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a < b end)

  # No message has no order to state, and stating one would claim what was never read.
  defp messages_line(0, _ascending?), do: "Messages readable: 0"
  defp messages_line(count, true), do: "Messages readable: #{count}, in ascending order"
  defp messages_line(count, false), do: "Messages readable: #{count}, not in ascending order"

  defp states([]), do: "none"
  defp states(states), do: states |> Enum.sort() |> Enum.join(", ")
end
