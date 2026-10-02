defmodule BnestApp.Backup.Domain.CapacityPolicy do
  @moduledoc """
  Whether a destination has room for a snapshot. A `VACUUM INTO` output is bounded by the
  source's live logical size (`page_count * page_size`) plus whatever is still resident in
  its WAL file (pages not yet checkpointed into the main file, which a consistent read still
  has to account for), never twice the whole source file, which would over-reject
  destinations that are in fact large enough. A fixed reserve stays free on top.
  """

  @reserve_bytes 256 * 1024 * 1024

  @typedoc "What a capacity probe measured: the destination's free bytes and the source's size."
  @type measurement :: %{
          available_bytes: non_neg_integer(),
          page_count: non_neg_integer(),
          page_size: pos_integer(),
          wal_bytes: non_neg_integer()
        }

  @doc "The free bytes a snapshot of the measured source needs, reserve included."
  @spec required_bytes(measurement()) :: non_neg_integer()
  def required_bytes(%{page_count: page_count, page_size: page_size, wal_bytes: wal_bytes}),
    do: page_count * page_size + wal_bytes + @reserve_bytes

  @doc "Whether the measured destination has the free bytes the snapshot needs."
  @spec sufficient?(measurement()) :: boolean()
  def sufficient?(%{available_bytes: available_bytes} = measurement),
    do: available_bytes >= required_bytes(measurement)
end
