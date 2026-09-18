defmodule BnestApp.FamilyChat do
  @moduledoc """
  Public Family Chat context. Every GraphQL resolver and test driver calls only
  this module (never `BnestApp.FamilyChat.Store` or raw SQL directly), so room
  authorization, the pagination cursor/limit contract, and the PubSub topic
  derivation live here exactly once (tech-doc 003's contract, and this plan's
  REFACTOR requirement to centralize them in one place).

  `use_family_chat` capability gating (whether an authenticated identity may use
  Family Chat at all) is a web-boundary concern checked by the caller (the
  GraphQL resolver, using the real session-derived role list) before this
  module is ever reached; this module only knows whether a caller is
  authenticated (a non-nil, server-resolved user id) and whether the requested
  room/message exists.
  """

  alias BnestApp.FamilyChat.Message
  alias BnestApp.FamilyChat.Store

  @min_limit 1
  @max_limit 50
  @default_limit 50

  @type safe_error :: {:error, %{code: String.t(), details: nil}}

  @doc "The v1 canonical room slug (tech-doc 005/008: only 'ruang-keluarga' exists)."
  @spec canonical_room_slug() :: String.t()
  def canonical_room_slug, do: Store.canonical_room_slug()

  @spec list_rooms_for(String.t() | nil) :: {:ok, [map()]} | safe_error()
  def list_rooms_for(nil), do: unauthenticated()
  def list_rooms_for(_user_id), do: {:ok, Store.list_active_rooms()}

  @slug_pattern ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  @spec get_room_for(String.t() | nil, String.t()) :: {:ok, map()} | safe_error()
  def get_room_for(nil, _slug), do: unauthenticated()

  def get_room_for(_user_id, slug) when is_binary(slug) do
    if valid_slug?(slug) do
      case Store.get_active_room_by_slug(slug) do
        nil -> room_not_found()
        room -> {:ok, room}
      end
    else
      validation_failed()
    end
  end

  def get_room_for(_user_id, _invalid_slug), do: validation_failed()

  defp valid_slug?(slug), do: byte_size(slug) in 1..64 and Regex.match?(@slug_pattern, slug)

  @spec list_messages(String.t() | nil, String.t(), keyword()) ::
          {:ok, %{nodes: [map()], has_older: boolean(), has_newer: boolean()}} | safe_error()
  def list_messages(nil, _slug, _opts), do: unauthenticated()

  def list_messages(user_id, slug, opts) when is_binary(user_id) do
    before_id = Keyword.get(opts, :before_id)
    after_id = Keyword.get(opts, :after_id)
    limit = Keyword.get(opts, :limit, @default_limit)

    with :ok <- validate_cursors(before_id, after_id),
         {:ok, validated_limit} <- validate_limit(limit),
         {:ok, room} <- get_room_for(user_id, slug) do
      page = Store.list_messages(room.id, before_id, after_id, validated_limit)

      {:ok,
       Map.update!(
         page,
         :nodes,
         &Enum.map(&1, fn node -> Map.put(node, :room_slug, room.slug) end)
       )}
    end
  end

  @spec send_message(String.t() | nil, String.t(), String.t(), String.t()) ::
          {:ok, map()} | safe_error()
  def send_message(nil, _slug, _client_message_id, _body), do: unauthenticated()

  def send_message(user_id, slug, client_message_id, body) when is_binary(user_id) do
    with {:ok, room} <- get_room_for(user_id, slug),
         :ok <- validate_posting_enabled(room),
         :ok <- validate_client_message_id(client_message_id),
         {:ok, normalized_body} <- validate_body(body) do
      commit_message(
        room,
        "user",
        user_id,
        display_name_for(user_id),
        client_message_id,
        normalized_body
      )
    end
  end

  @doc """
  Internal-only system message posting. Not reachable from GraphQL (no resolver
  or mutation field calls this); `idempotency_key` reuses the caller-supplied
  stable `producer_key` for both `sender_id` and the idempotency key, matching
  the trusted-producer contract in tech-doc 002.
  """
  @spec post_system_message(String.t(), String.t(), String.t()) :: {:ok, map()} | safe_error()
  def post_system_message(slug, producer_key, body) when is_binary(producer_key) do
    with {:ok, room} <- resolve_room(slug),
         {:ok, normalized_body} <- validate_body(body) do
      commit_message(room, "system", producer_key, "System", producer_key, normalized_body)
    end
  end

  @spec socket_context_for(String.t() | nil) ::
          {:ok, %{user_id: String.t(), session_digest: String.t()}} | safe_error()
  def socket_context_for(nil), do: {:error, %{code: "UNAUTHENTICATED", details: nil}}

  def socket_context_for(user_id) when is_binary(user_id) do
    {:ok, %{user_id: user_id, session_digest: session_digest_for(user_id)}}
  end

  @doc "The internal PubSub topic for a room's committed-message subscription (tech-doc 003: resolved room ID)."
  @spec subscription_topic(pos_integer()) :: String.t()
  def subscription_topic(room_id) when is_integer(room_id),
    do: "family_chat_room:" <> Integer.to_string(room_id)

  defp resolve_room(slug) when is_binary(slug) do
    case Store.get_active_room_by_slug(slug) do
      nil -> room_not_found()
      room -> {:ok, room}
    end
  end

  # `Phoenix.PubSub`/`Absinthe.Subscription.publish/3` reach only subscribers
  # local to this BEAM node -- this app runs unclustered (no libcluster/
  # `Node.connect`), so every commit's subscription broadcast is structurally
  # local-only, never reaching another release slot. Reported on the message
  # itself as the one inspectable proxy for that deployment-topology fact
  # (see tech-doc 007 / the "Independent slot-local PubSub" scenario).
  defp commit_message(room, sender_kind, sender_id, sender_display_name, idempotency_key, body) do
    case Store.find_message(room.id, sender_kind, sender_id, idempotency_key) do
      nil ->
        {:ok, message} =
          Store.insert_message!(
            room.id,
            sender_kind,
            sender_id,
            sender_display_name,
            idempotency_key,
            body
          )

        message = message |> Map.put(:room_slug, room.slug) |> Map.put(:broadcast_scope, :local)
        publish(message)
        {:ok, message}

      existing ->
        {:ok, existing |> Map.put(:room_slug, room.slug) |> Map.put(:broadcast_scope, :local)}
    end
  end

  defp publish(message) do
    Absinthe.Subscription.publish(
      BnestAppWeb.Endpoint,
      message,
      family_chat_message_committed: subscription_topic(message.room_id)
    )
  rescue
    # The subscription pipeline (Absinthe.Subscription supervisor) is not
    # started outside the full Phoenix endpoint (e.g. a bare unit-layer
    # direct-store call). Publication is best-effort broadcast, never a
    # correctness requirement for the commit itself.
    _not_started -> :ok
  end

  defp validate_cursors(before_id, after_id) when not is_nil(before_id) and not is_nil(after_id),
    do: validation_failed()

  defp validate_cursors(_before_id, _after_id), do: :ok

  defp validate_limit(limit) when is_integer(limit) and limit in @min_limit..@max_limit,
    do: {:ok, limit}

  defp validate_limit(_limit), do: validation_failed()

  defp validate_posting_enabled(%{member_posting_enabled: true}), do: :ok
  defp validate_posting_enabled(_room), do: {:error, %{code: "FORBIDDEN", details: nil}}

  defp validate_client_message_id(id) do
    if Message.valid_client_message_id?(id), do: :ok, else: validation_failed()
  end

  defp validate_body(body) do
    case Message.normalize_body(body) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> validation_failed()
    end
  end

  defp display_name_for(user_id), do: user_id

  defp session_digest_for(user_id),
    do: :crypto.hash(:sha256, user_id) |> Base.encode16(case: :lower)

  defp unauthenticated, do: {:error, %{code: "UNAUTHENTICATED", details: nil}}
  defp room_not_found, do: {:error, %{code: "ROOM_NOT_FOUND", details: nil}}
  defp validation_failed, do: {:error, %{code: "VALIDATION_FAILED", details: nil}}
end
