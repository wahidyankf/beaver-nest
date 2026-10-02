defmodule BnestApp.Storage.Domain.FlatMigration do
  @moduledoc """
  The rules of the one-time flat-file to SQLite migration: which source files it carries,
  their order, how each source is judged, the checksums that make a run's evidence, and the
  run's resulting state. `BnestApp.Storage.Migration` applies them over the Storage ports.
  """

  alias BnestApp.Storage.Domain.CanonicalJson
  alias BnestApp.Storage.Domain.RecordMap
  alias BnestApp.Storage.Domain.RecordSchema

  @migration_id "flat-files-v1-to-sqlite-v1"
  @id_pattern ~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z/u

  @type outcome :: :accepted | :invalid | :changed | :failed | :unsupported

  @spec migration_id() :: String.t()
  def migration_id, do: @migration_id

  @spec order_inventory([String.t()]) :: [String.t()]
  def order_inventory(relative_paths), do: Enum.sort(relative_paths)

  @doc "The supported sources among `relative_paths`, in migration order."
  @spec inventory([String.t()]) :: [String.t()]
  def inventory(relative_paths) do
    relative_paths
    |> Enum.filter(&match?({:ok, _classification}, classify_source(&1)))
    |> order_inventory()
  end

  @doc "The fingerprint of an inventory: each source path with its checksum, in order."
  @spec source_fingerprint([{String.t(), binary()}]) :: String.t()
  def source_fingerprint(sources) do
    sources
    |> Enum.map_join("\n", fn {relative_path, bytes} -> relative_path <> ":" <> sha256(bytes) end)
    |> sha256()
  end

  @doc "The checksum of the committed schema migration sources, given in version order."
  @spec ddl_checksum([binary()]) :: String.t()
  def ddl_checksum(schema_sources), do: schema_sources |> Enum.join() |> sha256()

  @doc """
  How a pass treats a source, given the item an earlier pass recorded for it: an accepted
  item with the same checksum is reused, an accepted item whose source changed is blocked,
  and anything else is judged again.
  """
  @spec resume_decision(map() | nil, String.t()) :: :reuse | :changed | :assess
  def resume_decision(%{outcome: "accepted", source_sha256: source_sha256}, source_sha256),
    do: :reuse

  def resume_decision(%{outcome: "accepted"}, _source_sha256), do: :changed
  def resume_decision(_recorded_item, _source_sha256), do: :assess

  @doc "Whether a stored legacy recovery payload is exactly the source's bytes."
  @spec recovery_matches?(map() | nil, binary()) :: boolean()
  def recovery_matches?(%{payload: bytes, payload_sha256: stored_sha256, byte_size: size}, bytes),
    do: stored_sha256 == sha256(bytes) and size == byte_size(bytes)

  def recovery_matches?(_stored, _source_bytes), do: false

  @doc "Classifies a source path as a record, a legacy recovery payload, or unsupported."
  @spec classify_source(String.t()) ::
          {:ok, {:record, map()} | {:recovery, map()}} | {:error, :unsupported_source}
  def classify_source(relative_path) do
    case RecordMap.classify(relative_path) do
      {:ok, classification} -> {:ok, {:record, classification}}
      {:error, :unsupported_source} -> classify_recovery_source(relative_path)
    end
  end

  @spec assess_record(String.t(), binary(), [module()]) ::
          {:accepted,
           %{
             classification: map(),
             identity: term(),
             record: map(),
             source_sha256: String.t(),
             target_sha256: String.t()
           }}
          | {:invalid, %{classification: map(), source_sha256: String.t()}}
          | {:unsupported, %{source_sha256: String.t()}}
  def assess_record(relative_path, source_bytes, kinds) do
    source_sha256 = sha256(source_bytes)

    case RecordMap.classify(relative_path) do
      {:ok, classification} ->
        assess_recognized_record(classification, source_bytes, source_sha256, kinds)

      {:error, :unsupported_source} ->
        {:unsupported, %{source_sha256: source_sha256}}
    end
  end

  @doc "Whether a flat source record still matches its migrated SQLite record."
  @spec record_matches?(binary(), {:ok, map()} | {:error, atom()}, atom(), [module()]) ::
          boolean()
  def record_matches?(source_bytes, target, phase, kinds) do
    with {:ok, source_record} <- Jason.decode(source_bytes),
         {:ok, ^source_record} <- RecordSchema.validate(source_record, kinds),
         {:ok, target_record} <- target do
      target_record == source_record or phase == :sqlite_primary
    else
      _mismatch -> false
    end
  end

  @spec outcome_counts([outcome()]) :: %{
          accepted: non_neg_integer(),
          blocked: non_neg_integer(),
          unsupported: non_neg_integer()
        }
  def outcome_counts(outcomes) do
    %{
      accepted: Enum.count(outcomes, &(&1 == :accepted)),
      blocked: Enum.count(outcomes, &(&1 in [:invalid, :changed, :failed])),
      unsupported: Enum.count(outcomes, &(&1 == :unsupported))
    }
  end

  @doc "The run state after a pass with `blocked` blocked items in storage `phase`."
  @spec run_state(non_neg_integer(), atom()) :: String.t()
  def run_state(blocked, _phase) when blocked > 0, do: "failed"
  def run_state(0, :sqlite_primary), do: "verified"
  def run_state(0, _phase), do: "copying"

  @doc "The repository identity of a classified record."
  @spec identity_of(map()) :: term()
  def identity_of(%{type: :bootstrap}), do: nil
  def identity_of(%{type: :schema_registry}), do: nil

  def identity_of(%{type: :browser_import, owner_id: owner, record_key: key}) do
    [_owner, import_id] = String.split(key, ":", parts: 2)
    {owner, import_id}
  end

  def identity_of(%{record_key: key}), do: key

  @doc "The migration-item classification of a classified source."
  @spec item_classification({:record, map()} | {:recovery, map()}) :: map()
  def item_classification({:record, classification}), do: classification

  def item_classification({:recovery, classification}) do
    %{
      record_type: "recovery-source",
      record_key:
        Enum.join(
          [classification.owner_kind, classification.owner_key, classification.import_id],
          ":"
        )
    }
  end

  @spec sha256(binary()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp assess_recognized_record(classification, source_bytes, source_sha256, kinds) do
    with {:ok, record} <- Jason.decode(source_bytes),
         {:ok, ^record} <- RecordSchema.validate(record, kinds) do
      {:accepted,
       %{
         classification: classification,
         identity: identity_of(classification),
         record: record,
         source_sha256: source_sha256,
         target_sha256: CanonicalJson.sha256(record)
       }}
    else
      _invalid -> {:invalid, %{classification: classification, source_sha256: source_sha256}}
    end
  end

  defp classify_recovery_source(relative_path) do
    case String.split(relative_path, "/") do
      ["apps", "beaver-nest", "legacy", import_id, "source.bin"] ->
        recovery_classification("app", "beaver-nest", import_id)

      ["users", owner_key, "legacy", import_id, "source.bin"] ->
        recovery_classification("user", owner_key, import_id)

      _unsupported ->
        {:error, :unsupported_source}
    end
  end

  defp recovery_classification(owner_kind, owner_key, import_id) do
    if Regex.match?(@id_pattern, owner_key) and Regex.match?(@id_pattern, import_id) do
      {:ok, {:recovery, %{owner_kind: owner_kind, owner_key: owner_key, import_id: import_id}}}
    else
      {:error, :unsupported_source}
    end
  end
end
