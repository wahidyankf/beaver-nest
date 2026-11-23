defmodule BnestApp.CodexChat.Domain.RunnerEvent do
  @moduledoc """
  The fixed lines a Codex runner failure shows: a runner exit and runner output the
  session cannot parse. Pure, so every layer proves the same lines the port session
  forwards to its owner.
  """

  @doc "The line a runner exit with `status` shows."
  @spec exit_message(integer()) :: String.t()
  def exit_message(status), do: "Codex runner exited with status #{status}."

  @doc "The line runner output the session cannot parse shows."
  @spec invalid_data_message() :: String.t()
  def invalid_data_message, do: "Codex runner returned invalid data."

  @doc "The fixed line the runner event a scenario names shows."
  @spec message_for(String.t()) :: String.t()
  def message_for("exits with status 3"), do: exit_message(3)
  def message_for("returns invalid runner data"), do: invalid_data_message()
end
