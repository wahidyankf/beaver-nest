defmodule BnestApp.DataRepository.Schema do
  @moduledoc false

  alias BnestApp.Chat
  alias BnestApp.SifatAllah

  @roles ~w(children parents admin)
  @statuses ~w(pending retryable rejected accepted)
  @failures ~w(unsupported-version unsupported-source oversized malformed owner-unresolved stale-revision write-failed read-back-failed cleanup-pending)
  @id_pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/u
  @username_pattern ~r/\A[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?\z/u
  @sha_pattern ~r/\A[0-9a-f]{64}\z/u

  @spec validate(term()) :: {:ok, map()} | {:error, atom()}
  def validate(%{"schemaVersion" => version}) when version != 1,
    do: {:error, :unsupported_version}

  def validate(%{"schemaVersion" => 1, "recordType" => type} = record) do
    case validate_type(type, record) do
      true -> {:ok, record}
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_schema}
    end
  end

  def validate(_record), do: {:error, :invalid_schema}

  @spec structural_projection(map()) :: map()
  def structural_projection(record) when is_map(record) do
    %{
      "recordType" => record["recordType"],
      "schemaVersion" => record["schemaVersion"],
      "fields" => Map.new(record, fn {key, value} -> {key, type_name(value)} end)
    }
  end

  @spec audit_root(String.t()) :: {:ok, [map()]} | {:error, atom()}
  def audit_root(root) when is_binary(root) do
    root = Path.expand(root)

    with :ok <- audit_root_allowed(root) do
      results =
        root
        |> Path.join("**/*.json")
        |> Path.wildcard()
        |> Enum.reject(&(Path.basename(&1) == ".bnest-test-run.json"))
        |> Enum.map(&audit_file/1)
        |> Enum.uniq()
        |> Enum.sort_by(&{&1["recordType"], &1["schemaVersion"], &1["result"]})

      {:ok, results}
    end
  end

  defp validate_type("bootstrap", record) do
    exact?(record, ~w(schemaVersion recordType state attemptId startedAt closedAt accounts)) and
      record["state"] in ~w(pending closed) and id?(record["attemptId"]) and
      timestamp?(record["startedAt"]) and bootstrap_closed_at?(record) and
      nonempty_list?(record["accounts"], &bootstrap_account?/1)
  end

  defp validate_type("account", record) do
    exact?(
      record,
      ~w(schemaVersion recordType userId displayUsername normalizedUsername roles passwordVerifier createdAt)
    ) and
      id?(record["userId"]) and display_username?(record["displayUsername"]) and
      username?(record["normalizedUsername"]) and roles?(record["roles"]) and
      argon2id?(record["passwordVerifier"]) and timestamp?(record["createdAt"])
  end

  defp validate_type("username-index", record) do
    exact?(record, ~w(schemaVersion recordType normalizedUsername userId)) and
      username?(record["normalizedUsername"]) and id?(record["userId"])
  end

  defp validate_type("browser-session", record) do
    exact?(record, ~w(schemaVersion recordType tokenDigest userId issuedAt revokedAt)) and
      sha?(record["tokenDigest"]) and id?(record["userId"]) and timestamp?(record["issuedAt"]) and
      nullable_timestamp?(record["revokedAt"])
  end

  defp validate_type("browser-import", record) do
    if browser_import_shape?(record), do: validate_browser_import_content(record), else: false
  end

  defp validate_type("chat", record) do
    exact?(record, ~w(schemaVersion recordType ownerId sourceImportId revision state updatedAt)) and
      id?(record["ownerId"]) and nullable_id?(record["sourceImportId"]) and
      revision?(record["revision"]) and match?({:ok, _chat}, Chat.restore(record["state"])) and
      timestamp?(record["updatedAt"])
  end

  defp validate_type("sifat-allah-progress", record) do
    exact?(
      record,
      ~w(schemaVersion recordType ownerId sourceImportId revision progress session updatedAt)
    ) and
      id?(record["ownerId"]) and nullable_id?(record["sourceImportId"]) and
      revision?(record["revision"]) and valid_progress?(record["progress"]) and
      valid_learning_session?(record["session"]) and timestamp?(record["updatedAt"])
  end

  defp validate_type("theme-preference", record) do
    exact?(record, ~w(schemaVersion recordType ownerId sourceImportId revision theme updatedAt)) and
      id?(record["ownerId"]) and nullable_id?(record["sourceImportId"]) and
      revision?(record["revision"]) and record["theme"] in ~w(light dark) and
      timestamp?(record["updatedAt"])
  end

  defp validate_type("import-manifest", record) do
    manifest_shape?(record) and manifest_identity?(record) and manifest_lifecycle?(record)
  end

  defp validate_type("schema-registry", record) do
    exact?(record, ~w(schemaVersion recordType supported migrations)) and
      is_map(record["supported"]) and map_size(record["supported"]) > 0 and
      Enum.all?(record["supported"], fn {type, versions} ->
        is_binary(type) and nonempty_list?(versions, &positive?/1)
      end) and is_list(record["migrations"]) and
      Enum.all?(record["migrations"], &migration?/1)
  end

  defp validate_type("bnest-test-run", record) do
    exact?(record, ~w(schemaVersion recordType runId createdAt owner)) and id?(record["runId"]) and
      timestamp?(record["createdAt"]) and record["owner"] == "bnest-test-harness"
  end

  defp validate_type(_type, _record), do: false

  defp browser_import_shape?(record) do
    exact?(
      record,
      ~w(schemaVersion recordType importId ownerId source payloadEncoding payload integrity)
    ) and
      id?(record["importId"]) and id?(record["ownerId"]) and
      record["payloadEncoding"] == "utf8-string" and is_binary(record["payload"]) and
      exact?(record["integrity"], ~w(sha256 capturedAt)) and
      sha?(record["integrity"]["sha256"]) and timestamp?(record["integrity"]["capturedAt"])
  end

  defp validate_browser_import_content(record) do
    cond do
      not supported_source?(record["source"]) ->
        {:error, :unsupported_source}

      byte_size(record["payload"]) > source_limit(record["source"]["storageKey"]) ->
        {:error, :oversized}

      digest(record["payload"]) != record["integrity"]["sha256"] ->
        {:error, :checksum_mismatch}

      true ->
        true
    end
  end

  defp manifest_shape?(record) do
    exact?(
      record,
      ~w(schemaVersion recordType importId ownerId source destination recoverySource status attempt startedAt completedAt failureCategory)
    )
  end

  defp manifest_identity?(record) do
    id?(record["importId"]) and nullable_id?(record["ownerId"]) and
      manifest_source?(record["source"]) and destination?(record["destination"]) and
      recovery_source?(record["recoverySource"])
  end

  defp manifest_lifecycle?(record) do
    record["status"] in @statuses and positive?(record["attempt"]) and
      timestamp?(record["startedAt"]) and nullable_timestamp?(record["completedAt"]) and
      (is_nil(record["failureCategory"]) or record["failureCategory"] in @failures)
  end

  defp audit_file(path) do
    case File.read(path) do
      {:ok, bytes} -> audit_bytes(bytes)
      {:error, _reason} -> audit_result(nil, nil, "fail")
    end
  end

  defp audit_bytes(bytes) do
    case Jason.decode(bytes) do
      {:ok, record} when is_map(record) ->
        result = if match?({:ok, _record}, validate(record)), do: "pass", else: "fail"
        audit_result(record["recordType"], record["schemaVersion"], result)

      _invalid ->
        audit_result(nil, nil, "fail")
    end
  end

  defp audit_result(record_type, schema_version, result) do
    %{
      "recordType" => record_type || "unknown",
      "schemaVersion" => schema_version || "unknown",
      "result" => result
    }
  end

  defp audit_root_allowed(root) do
    cond do
      symlink?(root) -> {:error, :symlink}
      not File.dir?(root) -> {:error, :missing_root}
      String.ends_with?(root, "/data/prod") -> :ok
      String.contains?(root, "/data/test/runs/") -> marked_test_root?(root)
      true -> {:error, :unsupported_root}
    end
  end

  defp marked_test_root?(root) do
    with {:ok, bytes} <- File.read(Path.join(root, ".bnest-test-run.json")),
         {:ok, marker} <- Jason.decode(bytes),
         {:ok, ^marker} <- validate(marker),
         true <- marker["runId"] == Path.basename(root) do
      :ok
    else
      _invalid -> {:error, :invalid_test_marker}
    end
  end

  defp bootstrap_account?(account) do
    exact?(account, ~w(userId normalizedUsername accountSha256 indexSha256)) and
      id?(account["userId"]) and username?(account["normalizedUsername"]) and
      sha?(account["accountSha256"]) and sha?(account["indexSha256"])
  end

  defp bootstrap_closed_at?(%{"state" => "pending", "closedAt" => nil}), do: true
  defp bootstrap_closed_at?(%{"state" => "closed", "closedAt" => value}), do: timestamp?(value)
  defp bootstrap_closed_at?(_record), do: false

  defp supported_source?(source) do
    exact?(source, ~w(kind storageArea storageKey sourceSchemaVersion)) and
      source["kind"] == "browser-storage" and positive?(source["sourceSchemaVersion"]) and
      {source["storageArea"], source["storageKey"]} in [
        {"sessionStorage", "bnest.chat.v1"},
        {"localStorage", "bnest.sifat-allah.v1"},
        {"localStorage", "phx:theme"}
      ]
  end

  defp source_limit("bnest.chat.v1"), do: 500_000
  defp source_limit("bnest.sifat-allah.v1"), do: 10_000
  defp source_limit("phx:theme"), do: 16

  defp valid_progress?(progress) do
    exact?(
      progress,
      ~w(version learned_ids review_ids mastered_key_ids review_key_ids correct_answers incorrect_answers)
    ) and
      match?({:ok, _progress}, SifatAllah.restore(progress))
  end

  defp valid_learning_session?(nil), do: true
  defp valid_learning_session?(%{"mode" => "dashboard"} = session), do: exact?(session, ~w(mode))

  defp valid_learning_session?(%{"mode" => "study"} = session),
    do:
      exact?(session, ~w(mode lesson_ids lesson_index feedback)) and
        nonempty_list?(session["lesson_ids"], &id?/1) and revision?(session["lesson_index"]) and
        session["feedback"] in [nil, "remembered"]

  defp valid_learning_session?(%{"mode" => "quiz"} = session),
    do:
      exact?(session, ~w(mode quiz_pair_id quiz_kind quiz_scope feedback)) and
        id?(session["quiz_pair_id"]) and is_binary(session["quiz_kind"]) and
        session["quiz_scope"] in ~w(all learned) and
        session["feedback"] in [nil, "success", "retry"]

  defp valid_learning_session?(%{"mode" => "review"} = session),
    do:
      exact?(session, ~w(mode review_pair_id review_kind feedback)) and
        id?(session["review_pair_id"]) and is_binary(session["review_kind"]) and
        session["feedback"] in [nil, "success", "retry"]

  defp valid_learning_session?(_session), do: false

  defp manifest_source?(source),
    do:
      exact?(source, ~w(kind reference sha256)) and is_binary(source["kind"]) and
        is_binary(source["reference"]) and sha?(source["sha256"])

  defp destination?(destination),
    do:
      exact?(destination, ~w(recordType relativePathTemplate)) and
        is_binary(destination["recordType"]) and is_binary(destination["relativePathTemplate"])

  defp recovery_source?(source),
    do:
      exact?(source, ~w(kind relativePathTemplate sha256)) and is_binary(source["kind"]) and
        is_binary(source["relativePathTemplate"]) and sha?(source["sha256"])

  defp migration?(migration),
    do:
      exact?(migration, ~w(recordType from to migrationId)) and
        is_binary(migration["recordType"]) and positive?(migration["from"]) and
        positive?(migration["to"]) and migration["to"] > migration["from"] and
        id?(migration["migrationId"])

  defp exact?(map, keys) when is_map(map), do: Map.keys(map) |> Enum.sort() == Enum.sort(keys)
  defp exact?(_map, _keys), do: false

  defp id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)
  defp nullable_id?(nil), do: true
  defp nullable_id?(value), do: id?(value)
  defp sha?(value), do: is_binary(value) and Regex.match?(@sha_pattern, value)
  defp username?(value), do: is_binary(value) and Regex.match?(@username_pattern, value)
  defp display_username?(value), do: is_binary(value) and String.length(value) in 1..32
  defp argon2id?(value), do: is_binary(value) and String.starts_with?(value, "$argon2id$")
  defp revision?(value), do: is_integer(value) and value >= 0
  defp positive?(value), do: is_integer(value) and value > 0

  defp roles?(roles),
    do: nonempty_list?(roles, &(&1 in @roles)) and Enum.uniq(roles) == roles

  defp nonempty_list?(values, predicate),
    do: is_list(values) and values != [] and Enum.all?(values, predicate)

  defp timestamp?(value) when is_binary(value),
    do: match?({:ok, _time, 0}, DateTime.from_iso8601(value))

  defp timestamp?(_value), do: false
  defp nullable_timestamp?(nil), do: true
  defp nullable_timestamp?(value), do: timestamp?(value)

  defp symlink?(path) do
    match?({:ok, %File.Stat{type: :symlink}}, File.lstat(path))
  end

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp type_name(nil), do: "null"
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "number"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_list(value), do: "array"
  defp type_name(value) when is_map(value), do: "object"
end
