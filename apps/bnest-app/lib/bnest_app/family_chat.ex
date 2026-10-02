defmodule BnestApp.FamilyChat do
  @moduledoc """
  The Family Chat bounded context: the family's rooms, their committed messages and
  replies, and the subscription event each commit publishes.

  This module is the context's application-service facade. Every GraphQL resolver, the room
  controller, the subscription socket and the other contexts call only this module (never
  the room store or raw SQL directly). Its adapters come from application configuration
  under `config :bnest_app, BnestApp.FamilyChat`, one per port in
  `BnestApp.FamilyChat.Ports`, so a unit test can supply in-memory doubles. Room
  authorization, message validation and the pagination cursor are the pure
  `BnestApp.FamilyChat.Domain`; its `Message` rules are exported for the GraphQL types.

  `use_family_chat` capability gating (whether an authenticated identity may use Family
  Chat at all) is a web-boundary concern checked by the caller (the GraphQL resolver, using
  the real session-derived role list) before this module is ever reached; this module only
  knows whether a caller is authenticated (a non-nil, server-resolved user id) and whether
  the requested room/message exists.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [BnestApp.Scheduler],
    exports: [{Domain, []}, {Ports, []}]

  alias BnestApp.FamilyChat.Domain.{Cursor, Message, Policy}
  alias BnestApp.FamilyChat.Ports.RoomStore
  alias BnestApp.Scheduler

  @retention_schedule_key "family-chat-push-retention-daily"
  @backup_schedule_key "prod-sqlite-backup-daily"

  @type safe_error :: Policy.safe_error()

  @doc "The configured adapter for a Family Chat port: `:room_store` or `:message_publisher`."
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc "The v1 canonical room slug (tech-doc 005/008: only 'ruang-keluarga' exists)."
  @spec canonical_room_slug() :: String.t()
  def canonical_room_slug, do: Policy.canonical_room_slug()

  @doc """
  Prepares the room store and seeds the canonical room. The legacy contexts that keep their
  own tables in Family Chat's database call it before they touch them.
  """
  @spec ensure_ready!() :: :ok
  def ensure_ready!, do: RoomStore.ensure_ready!(store())

  @doc "The active room at the canonical slug, or nil."
  @spec canonical_room() :: RoomStore.room() | nil
  def canonical_room, do: RoomStore.get_active_room(store(), Policy.canonical_room_slug())

  @doc "Release-time migration: prepares the room store and returns the canonical room."
  @spec migrate!() :: {:ok, RoomStore.room() | nil}
  def migrate! do
    store = store()
    :ok = RoomStore.ensure_ready!(store)
    {:ok, RoomStore.get_active_room(store, Policy.canonical_room_slug())}
  end

  @doc """
  Release-time convergence after the prior slot drained: enables the seeded push-retention
  schedule and converges the backup schedule's daily time to 18:00 UTC, each at most once.

  Tech-doc 009 ("Backup Schedule Migration"): "After the compatibility revision is routed
  and every runnable slot supports the new Backup service, managed release calls a public
  Scheduler operation that force-converges this key once"; and "Push retention remains a
  separate fixed disabled seed at 00:15 WIB and becomes enabled only after old-slot drain."
  Both go through the Scheduler's compare-and-swap on `revision = 1`, so calling this again
  takes effect at most once and never overrides a later operator edit. It works on whatever
  database the caller (the release entry point) started.
  """
  @spec converge_after_drain!() :: :ok
  def converge_after_drain! do
    Scheduler.activate_if_pristine!(@retention_schedule_key, DateTime.utc_now())
    {:ok, _schedule} = Scheduler.converge_backup_time!(@backup_schedule_key, "18:00")
    :ok
  end

  @doc """
  Commits a message in `room_id` exactly as given, with no validation and no publish, and
  returns it with the push deliveries it created. For trusted internal producers only.
  """
  @spec insert_message!(
          pos_integer(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, RoomStore.message()}
  def insert_message!(room_id, sender_kind, sender_id, sender_display_name, idempotency_key, body) do
    RoomStore.insert_message!(
      store(),
      room_id,
      sender_kind,
      sender_id,
      sender_display_name,
      idempotency_key,
      body,
      nil
    )
  end

  @spec list_rooms_for(String.t() | nil) :: {:ok, [map()]} | safe_error()
  def list_rooms_for(nil), do: Policy.unauthenticated()
  def list_rooms_for(_user_id), do: {:ok, RoomStore.list_active_rooms(store())}

  @spec get_room_for(String.t() | nil, String.t()) :: {:ok, map()} | safe_error()
  def get_room_for(nil, _slug), do: Policy.unauthenticated()
  def get_room_for(_user_id, slug), do: room_for(store(), slug)

  @spec list_messages(String.t() | nil, String.t(), keyword()) ::
          {:ok, %{nodes: [map()], has_older: boolean(), has_newer: boolean()}} | safe_error()
  def list_messages(nil, _slug, _opts), do: Policy.unauthenticated()

  def list_messages(user_id, slug, opts) when is_binary(user_id) do
    with {:ok, cursor} <- cursor(opts),
         store = store(),
         {:ok, room} <- room_for(store, slug) do
      page =
        RoomStore.list_messages(store, room.id, cursor.before_id, cursor.after_id, cursor.limit)

      quotes = RoomStore.quotes_for(store, room.id, page.nodes)

      {:ok,
       Map.update!(
         page,
         :nodes,
         &Enum.map(&1, fn node ->
           node
           |> Map.put(:room_slug, room.slug)
           |> Message.attach_quote(quotes)
         end)
       )}
    end
  end

  # `sender_display_name` defaults to the raw user id for callers with no real
  # account to display (test drivers' synthetic load probes): only the
  # GraphQL resolver, which has a real session-derived `displayUsername`,
  # passes one explicitly.
  @spec send_message(
          String.t() | nil,
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          term()
        ) :: {:ok, map()} | safe_error()
  def send_message(
        user_id,
        slug,
        client_message_id,
        body,
        sender_display_name \\ nil,
        reply_to_message_id \\ nil
      )

  def send_message(nil, _slug, _client_message_id, _body, _sender_display_name, _reply_to),
    do: Policy.unauthenticated()

  def send_message(
        user_id,
        slug,
        client_message_id,
        body,
        sender_display_name,
        reply_to_message_id
      )
      when is_binary(user_id) do
    store = store()

    with {:ok, room} <- room_for(store, slug),
         :ok <- Policy.validate_posting_enabled(room),
         :ok <- Policy.validate_client_message_id(client_message_id),
         {:ok, normalized_body} <- Policy.validate_body(body),
         {:ok, reply_to} <- reply_target(store, room, reply_to_message_id) do
      commit_message(
        store,
        room,
        "user",
        user_id,
        sender_display_name || user_id,
        client_message_id,
        normalized_body,
        reply_to
      )
    end
  end

  @doc "The sender name a reader sees; see `BnestApp.FamilyChat.Domain.Message`."
  @spec live_sender_display_name(map(), (String.t() -> String.t() | nil)) :: String.t()
  defdelegate live_sender_display_name(message, lookup), to: Message

  @doc """
  Internal-only system message posting. Not reachable from GraphQL (no resolver
  or mutation field calls this); `idempotency_key` reuses the caller-supplied
  stable `producer_key` for both `sender_id` and the idempotency key, matching
  the trusted-producer contract in tech-doc 002.
  """
  @spec post_system_message(String.t(), String.t(), String.t()) :: {:ok, map()} | safe_error()
  def post_system_message(slug, producer_key, body) when is_binary(producer_key) do
    store = store()

    with {:ok, room} <- resolve_room(store, slug),
         {:ok, normalized_body} <- Policy.validate_body(body) do
      commit_message(store, room, "system", producer_key, "System", producer_key, normalized_body)
    end
  end

  @spec socket_context_for(String.t() | nil) ::
          {:ok, %{user_id: String.t(), session_digest: String.t()}} | safe_error()
  def socket_context_for(nil), do: Policy.unauthenticated()

  def socket_context_for(user_id) when is_binary(user_id) do
    {:ok, %{user_id: user_id, session_digest: Policy.session_digest(user_id)}}
  end

  @doc "The internal PubSub topic for a room's committed-message subscription (tech-doc 003: resolved room ID)."
  @spec subscription_topic(pos_integer()) :: String.t()
  def subscription_topic(room_id) when is_integer(room_id),
    do: "family_chat_room:" <> Integer.to_string(room_id)

  defp store, do: adapter(:room_store).new()

  defp room_for(store, slug) when is_binary(slug) do
    with :ok <- Policy.validate_slug(slug), do: resolve_room(store, slug)
  end

  defp room_for(_store, _invalid_slug), do: Policy.validation_failed()

  defp resolve_room(store, slug) when is_binary(slug) do
    case RoomStore.get_active_room(store, slug) do
      nil -> Policy.room_not_found()
      room -> {:ok, room}
    end
  end

  defp cursor(opts) do
    case Cursor.new(opts) do
      {:ok, cursor} -> {:ok, cursor}
      :error -> Policy.validation_failed()
    end
  end

  # Cross-room targets are refused even though v1 has one room: the column
  # outlives the single-room assumption, and a check added later is a check
  # that was missing in between.
  defp reply_target(store, room, raw_id) do
    case Policy.validate_reply_target(raw_id) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, id} ->
        case RoomStore.message_by_id(store, room.id, id) do
          nil -> Policy.validation_failed()
          %{id: found_id} -> {:ok, found_id}
        end

      error ->
        error
    end
  end

  # The configured publisher reaches only subscribers local to this BEAM node
  # -- this app runs unclustered (no libcluster/`Node.connect`), so every
  # commit's subscription broadcast is structurally local-only, never reaching
  # another release slot. Reported on the message itself as the one
  # inspectable proxy for that deployment-topology fact (see tech-doc 007 /
  # the "Independent slot-local PubSub" scenario).
  defp commit_message(
         store,
         room,
         sender_kind,
         sender_id,
         sender_display_name,
         idempotency_key,
         body,
         reply_to_message_id \\ nil
       ) do
    case RoomStore.find_message(store, room.id, sender_kind, sender_id, idempotency_key) do
      nil ->
        {:ok, message} =
          RoomStore.insert_message!(
            store,
            room.id,
            sender_kind,
            sender_id,
            sender_display_name,
            idempotency_key,
            body,
            reply_to_message_id
          )

        {:ok, decorate_committed(store, message, room)}
        |> tap(fn {:ok, decorated} -> publish(decorated) end)

      existing ->
        # The replay deliberately returns the row as it was first committed,
        # quote included: a client message ID identifies one intended message,
        # so a retry naming a different target must not change what it answers.
        {:ok, decorate_committed(store, existing, room)}
    end
  end

  defp decorate_committed(store, message, room) do
    message
    |> Map.put(:room_slug, room.slug)
    |> Map.put(:broadcast_scope, :local)
    |> Message.attach_quote(RoomStore.quotes_for(store, room.id, [message]))
  end

  defp publish(message),
    do: adapter(:message_publisher).publish(message, subscription_topic(message.room_id))
end
