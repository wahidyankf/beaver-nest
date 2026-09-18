defmodule BnestAppWeb.Resolvers.FamilyChatResolver do
  @moduledoc """
  Thin GraphQL-boundary adapter: every resolver here does exactly two things —
  resolve/authorize the caller (`use_family_chat` capability, checked from the
  real server-resolved session, never a client-supplied field), then delegate
  to `BnestApp.FamilyChat`. No SQL and no room/pagination logic lives here
  (REFACTOR requirement); see `test/unit/bnest_app_web/schema_test.exs` for the
  dependency-direction check that keeps it that way.
  """

  alias BnestApp.FamilyChat
  alias BnestApp.Identity

  @spec family_chat_rooms(map(), Absinthe.Resolution.t()) :: {:ok, [map()]} | {:error, keyword()}
  def family_chat_rooms(_args, resolution) do
    with {:ok, user_id} <- authorize(resolution) do
      wrap(FamilyChat.list_rooms_for(user_id))
    end
  end

  @spec family_chat_room(map(), Absinthe.Resolution.t()) :: {:ok, map()} | {:error, keyword()}
  def family_chat_room(%{slug: slug}, resolution) do
    with {:ok, user_id} <- authorize(resolution) do
      wrap(FamilyChat.get_room_for(user_id, slug))
    end
  end

  @spec family_chat_messages(map(), Absinthe.Resolution.t()) :: {:ok, map()} | {:error, keyword()}
  def family_chat_messages(args, resolution) do
    with {:ok, user_id} <- authorize(resolution) do
      opts =
        [
          before_id: parse_id(args[:before_id]),
          after_id: parse_id(args[:after_id]),
          limit: args[:limit]
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      wrap(FamilyChat.list_messages(user_id, args.room_slug, opts))
    end
  end

  @spec send_family_chat_message(map(), Absinthe.Resolution.t()) ::
          {:ok, map()} | {:error, keyword()}
  def send_family_chat_message(args, resolution) do
    with {:ok, user_id} <- authorize(resolution) do
      wrap(
        FamilyChat.send_message(
          user_id,
          args.room_slug,
          to_string(args.client_message_id),
          args.body
        )
      )
    end
  end

  @spec subscription_config(map(), Absinthe.Resolution.t()) :: {:ok, keyword()} | {:error, term()}
  def subscription_config(args, resolution) do
    with {:ok, user_id} <- authorize(resolution),
         {:ok, room} <- FamilyChat.get_room_for(user_id, args.room_slug) do
      {:ok, topic: FamilyChat.subscription_topic(room.id)}
    else
      {:error, _safe_error} -> {:error, "forbidden"}
    end
  end

  # Matches on a bare `%{context: ...}` map, not `%Absinthe.Resolution{}`
  # specifically: `Absinthe.Phase.Subscription.SubscribeSelf` invokes a
  # `config/2` callback (subscription topic resolution) with a plain
  # `%{context: context, document: blueprint}` map, not a real
  # `%Absinthe.Resolution{}` struct — a struct-only pattern here would never
  # match for `subscription_config/2`, silently falling through to
  # UNAUTHENTICATED for every subscription regardless of a genuinely valid
  # session. Ordinary query/mutation resolutions still match fine: a real
  # `%Absinthe.Resolution{}` is itself a map with a `:context` field.
  defp authorize(%{context: %{current_user: %{"userId" => user_id} = user}}) do
    if Identity.authorize(user, :use_family_chat, user_id) do
      {:ok, user_id}
    else
      {:error, safe_error("FORBIDDEN")}
    end
  end

  defp authorize(_no_authenticated_context), do: {:error, safe_error("UNAUTHENTICATED")}

  defp wrap({:ok, value}), do: {:ok, value}
  defp wrap({:error, %{code: code}}), do: {:error, safe_error(code)}

  defp safe_error(code), do: [message: safe_message(code), extensions: %{code: code}]

  defp safe_message("UNAUTHENTICATED"), do: "Authentication required."
  defp safe_message("FORBIDDEN"), do: "Not authorized for this operation."
  defp safe_message("ROOM_NOT_FOUND"), do: "The requested room is unavailable."
  defp safe_message("VALIDATION_FAILED"), do: "The request is invalid."
  defp safe_message(_other), do: "The request could not be completed."

  defp parse_id(nil), do: nil
  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _invalid -> value
    end
  end
end
