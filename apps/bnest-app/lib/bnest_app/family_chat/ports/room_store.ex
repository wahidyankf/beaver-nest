defmodule BnestApp.FamilyChat.Ports.RoomStore do
  @moduledoc """
  The store of Family Chat's rooms, their committed messages, and the push deliveries each
  commit owes.

  Every callback except `new/0` takes the store's handle first. The handle is a map whose
  `:adapter` key names the implementing module, so the facade dispatches through the
  functions below without knowing which store is active.

  Semantics every implementation keeps:

    * `ensure_ready!/1` prepares the store and seeds the canonical room (ID 1,
      `"ruang-keluarga"`, "Ruang Keluarga", a conversation with member posting enabled)
      once; repeating it changes nothing. Every room and message callback ensures it first.
    * Messages are append-only: no callback changes or removes a committed message.
    * `insert_message!/8` commits a message whose ID is greater than every ID before it, and
      raises, committing nothing, when the room already holds a message with the same
      sender kind, sender ID and idempotency key, or when the reply target is no message.
      In the same commit it records one pending delivery for every active push
      subscription, except the sending user's own; it returns the message with those
      deliveries under `:deliveries`.
    * `find_message/5` finds a message by its room, sender kind, sender ID and idempotency
      key.
    * `list_messages/5` returns at most `limit` messages in ascending ID order: the latest
      ones without a cursor; those immediately below `before_id`; or those immediately
      above `after_id`. `has_older` is true when the room holds a message below the page
      (below `after_id` for an after page), and `has_newer` when it holds one above it
      (always for a before page, never for the latest page).
    * `quotes_for/3` resolves the distinct reply targets of a page to the messages with
      those IDs in that room; a target the room has no message for is absent.
    * `message_by_id/3` finds a message only within the given room.
    * `converge_after_drain!/1` enables the room's seeded push-retention schedule and
      converges the backup schedule's daily time, each at most once.

  A room is a map with `:id`, `:slug`, `:name`, `:room_kind`, `:member_posting_enabled`,
  the audit fields `:created_at`, `:created_by`, `:updated_at` and `:updated_by`. A message
  is a map with `:id`, `:room_id`, `:sender_kind`, `:sender_id`, `:sender_display_name`,
  `:idempotency_key`, `:body`, `:committed_at` (a `DateTime`) and `:reply_to_message_id`.
  """

  @type handle :: %{required(:adapter) => module(), optional(atom()) => term()}
  @type room :: map()
  @type message :: map()
  @type page :: %{nodes: [message()], has_older: boolean(), has_newer: boolean()}

  @doc "A handle over the rooms the running application serves."
  @callback new() :: handle()

  @callback ensure_ready!(handle()) :: :ok
  @callback list_active_rooms(handle()) :: [room()]
  @callback get_active_room(handle(), slug :: String.t()) :: room() | nil

  @callback list_messages(
              handle(),
              room_id :: pos_integer(),
              before_id :: pos_integer() | nil,
              after_id :: pos_integer() | nil,
              limit :: pos_integer()
            ) :: page()

  @callback find_message(
              handle(),
              room_id :: pos_integer(),
              sender_kind :: String.t(),
              sender_id :: String.t(),
              idempotency_key :: String.t()
            ) :: message() | nil

  @callback insert_message!(
              handle(),
              room_id :: pos_integer(),
              sender_kind :: String.t(),
              sender_id :: String.t(),
              sender_display_name :: String.t(),
              idempotency_key :: String.t(),
              body :: String.t(),
              reply_to_message_id :: pos_integer() | nil
            ) :: {:ok, message()}

  @callback quotes_for(handle(), room_id :: pos_integer(), [message()]) ::
              %{pos_integer() => message()}

  @callback message_by_id(handle(), room_id :: pos_integer(), message_id :: pos_integer()) ::
              message() | nil

  @callback converge_after_drain!(handle()) :: :ok

  @spec ensure_ready!(handle()) :: :ok
  def ensure_ready!(store), do: store.adapter.ensure_ready!(store)

  @spec list_active_rooms(handle()) :: [room()]
  def list_active_rooms(store), do: store.adapter.list_active_rooms(store)

  @spec get_active_room(handle(), String.t()) :: room() | nil
  def get_active_room(store, slug), do: store.adapter.get_active_room(store, slug)

  @spec list_messages(handle(), pos_integer(), term(), term(), pos_integer()) :: page()
  def list_messages(store, room_id, before_id, after_id, limit),
    do: store.adapter.list_messages(store, room_id, before_id, after_id, limit)

  @spec find_message(handle(), pos_integer(), String.t(), String.t(), String.t()) ::
          message() | nil
  def find_message(store, room_id, sender_kind, sender_id, idempotency_key),
    do: store.adapter.find_message(store, room_id, sender_kind, sender_id, idempotency_key)

  @spec insert_message!(
          handle(),
          pos_integer(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer() | nil
        ) :: {:ok, message()}
  def insert_message!(
        store,
        room_id,
        sender_kind,
        sender_id,
        sender_display_name,
        idempotency_key,
        body,
        reply_to_message_id
      ) do
    store.adapter.insert_message!(
      store,
      room_id,
      sender_kind,
      sender_id,
      sender_display_name,
      idempotency_key,
      body,
      reply_to_message_id
    )
  end

  @spec quotes_for(handle(), pos_integer(), [message()]) :: %{pos_integer() => message()}
  def quotes_for(store, room_id, messages), do: store.adapter.quotes_for(store, room_id, messages)

  @spec message_by_id(handle(), pos_integer(), pos_integer()) :: message() | nil
  def message_by_id(store, room_id, message_id),
    do: store.adapter.message_by_id(store, room_id, message_id)

  @spec converge_after_drain!(handle()) :: :ok
  def converge_after_drain!(store), do: store.adapter.converge_after_drain!(store)
end
