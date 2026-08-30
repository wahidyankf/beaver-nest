defmodule BnestApp.Backup.Receipt do
  @moduledoc false

  @scope "bnest-production-backups-v1"
  @required_keys ~w(
    schemaVersion ownershipScope destinationId scheduleKey claimKind claimKey scheduledFor runId
    scheduleRevision createdAt sourceGeneration artifactBasename artifactSha256 artifactBytes quickCheck
    schemaVersions logicalProofSha256
  )

  @spec valid?(map(), String.t()) :: boolean()
  def valid?(receipt, destination_id) when is_map(receipt) do
    valid_shape?(receipt) and valid_owner?(receipt, destination_id) and
      valid_artifact?(receipt) and valid_proof?(receipt)
  end

  def valid?(_receipt, _destination_id), do: false

  defp valid_shape?(receipt), do: Enum.sort(Map.keys(receipt)) == Enum.sort(@required_keys)

  defp valid_owner?(receipt, destination_id) do
    receipt["schemaVersion"] == 1 and receipt["ownershipScope"] == @scope and
      receipt["destinationId"] == destination_id
  end

  defp valid_artifact?(receipt) do
    is_binary(receipt["artifactBasename"]) and
      Path.basename(receipt["artifactBasename"]) == receipt["artifactBasename"] and
      valid_digest?(receipt["artifactSha256"]) and is_integer(receipt["artifactBytes"]) and
      receipt["artifactBytes"] > 0
  end

  defp valid_proof?(receipt) do
    receipt["quickCheck"] == "ok" and valid_digest?(receipt["logicalProofSha256"]) and
      valid_utc?(receipt["createdAt"])
  end

  defp valid_digest?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value)

  defp valid_utc?(value) do
    match?({:ok, _instant, 0}, DateTime.from_iso8601(value))
  rescue
    FunctionClauseError -> false
  end
end
