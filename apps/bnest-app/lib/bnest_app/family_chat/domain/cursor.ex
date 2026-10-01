defmodule BnestApp.FamilyChat.Domain.Cursor do
  @moduledoc """
  The message-page cursor contract: a page names at most one of `before_id` and `after_id`,
  and a limit from 1 to 50, which is 50 when the caller names none.
  """

  @min_limit 1
  @max_limit 50
  @default_limit 50

  @type t :: %{before_id: term(), after_id: term(), limit: pos_integer()}

  @doc "The cursor `options` name, or `:error` when they break the contract."
  @spec new(keyword()) :: {:ok, t()} | :error
  def new(options) do
    before_id = Keyword.get(options, :before_id)
    after_id = Keyword.get(options, :after_id)
    limit = Keyword.get(options, :limit, @default_limit)

    if (is_nil(before_id) or is_nil(after_id)) and valid_limit?(limit),
      do: {:ok, %{before_id: before_id, after_id: after_id, limit: limit}},
      else: :error
  end

  defp valid_limit?(limit), do: is_integer(limit) and limit in @min_limit..@max_limit
end
