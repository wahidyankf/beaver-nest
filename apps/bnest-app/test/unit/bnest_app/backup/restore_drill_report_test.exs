defmodule BnestApp.Backup.RestoreDrillReportTest do
  use ExUnit.Case, async: true

  alias BnestApp.Backup.Domain.RestoreDrillReport
  alias BnestApp.Backup.Domain.RestoreEvidence

  @restored "Restore drill: restored the artifact into a fresh isolated root"
  @refused "Restore drill: refused. The artifact must be a regular file inside the configured backup destination."

  @facts %{
    room: %{
      id: 41,
      slug: "test-user-room",
      name: "Synthetic Family Room",
      member_posting_enabled: true
    },
    message_ids: [4, 5, 9],
    subscription_count: 2,
    delivery_states: ["pending", "delivered"]
  }

  describe "report/1 of a restore" do
    test "states what the restored copy holds and that its root is gone" do
      assert RestoreDrillReport.report({:restored, evidence(@facts), []}) == %{
               exit_status: 0,
               lines: [
                 @restored,
                 "Rooms readable: 1",
                 "Messages readable: 3, in ascending order",
                 "Push subscriptions: 2",
                 "Delivery states: delivered, pending",
                 "Restore root: removed"
               ]
             }
    end

    test "carries no identifier, name or message ID of what it read" do
      %{lines: lines} = RestoreDrillReport.report({:restored, evidence(@facts), []})
      text = Enum.join(lines, "\n")

      for private <- ["test-user-room", "Synthetic Family Room", "41", "4, 5, 9"] do
        refute text =~ private
      end
    end

    test "counts one message as ordered and none as a count without an order" do
      assert RestoreDrillReport.report({:restored, evidence(%{@facts | message_ids: [7]}), []}).lines
             |> Enum.at(2) == "Messages readable: 1, in ascending order"

      assert %{exit_status: 0, lines: lines} =
               RestoreDrillReport.report({:restored, evidence(%{@facts | message_ids: []}), []})

      assert Enum.at(lines, 2) == "Messages readable: 0"
    end

    test "names no delivery state when the copy holds none" do
      assert %{exit_status: 0, lines: lines} =
               RestoreDrillReport.report(
                 {:restored, evidence(%{@facts | delivery_states: []}), []}
               )

      assert Enum.at(lines, 4) == "Delivery states: none"
    end

    test "fails messages that are not in strictly ascending order" do
      for ids <- [[3, 1, 2], [1, 1], [2, 1]] do
        assert %{exit_status: 1, lines: lines} =
                 RestoreDrillReport.report(
                   {:restored, evidence(%{@facts | message_ids: ids}), []}
                 )

        assert Enum.at(lines, 2) ==
                 "Messages readable: #{length(ids)}, not in ascending order"

        assert hd(lines) == @restored
        assert List.last(lines) == "Restore root: removed"
      end
    end

    test "fails a copy that holds no readable room" do
      document = @facts |> RestoreEvidence.document() |> Map.delete("room") |> Jason.encode!()

      assert %{exit_status: 1, lines: lines} =
               RestoreDrillReport.report({:restored, document, []})

      assert Enum.at(lines, 1) == "Rooms readable: 0"
    end

    test "fails and says so when a restore root was left behind" do
      assert %{exit_status: 1, lines: lines} =
               RestoreDrillReport.report(
                 {:restored, evidence(@facts), ["bnest-restore-left-behind"]}
               )

      assert List.last(lines) == "Restore root: not removed"
      assert length(lines) == 6
      refute Enum.any?(lines, &String.contains?(&1, "bnest-restore-"))
    end
  end

  describe "report/1 of a failure" do
    test "words each as one fixed line and a non-zero exit" do
      assert RestoreDrillReport.report(:refused) == %{exit_status: 1, lines: [@refused]}

      assert RestoreDrillReport.report({:error, :destination_unreadable}) ==
               %{
                 exit_status: 1,
                 lines: ["Restore drill: the backup destination could not be read."]
               }

      assert RestoreDrillReport.report({:error, :restore_failed}) ==
               %{exit_status: 1, lines: ["Restore drill: the artifact could not be restored."]}
    end
  end

  defp evidence(facts), do: facts |> RestoreEvidence.document() |> Jason.encode!()
end
