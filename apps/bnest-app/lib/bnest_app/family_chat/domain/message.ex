defmodule BnestApp.FamilyChat.Domain.Message do
  @moduledoc """
  A committed Family Chat message: the rules for its body, client message ID and reply
  target, the quote a reply carries, and the sender name a reader sees.
  """

  @enforce_keys [
    :id,
    :room_id,
    :sender_kind,
    :sender_id,
    :sender_display_name,
    :idempotency_key,
    :body,
    :committed_at
  ]
  defstruct [
    :id,
    :room_id,
    :sender_kind,
    :sender_id,
    :sender_display_name,
    :idempotency_key,
    :body,
    :committed_at
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          room_id: pos_integer(),
          sender_kind: String.t(),
          sender_id: String.t(),
          sender_display_name: String.t(),
          idempotency_key: String.t(),
          body: String.t(),
          committed_at: DateTime.t()
        }

  @max_graphemes 4_000
  @max_bytes 16_384

  # Bounds a 50-message page near 8 KB of quote text instead of the 200 KB a
  # page of full 4,000-grapheme bodies would permit.
  @preview_graphemes 160

  # tech-doc 002's "Send Transactions" contract: normalized text, at most 4,000
  # graphemes, at most 16 KiB, non-blank. Rejects before any commit is attempted.
  @spec normalize_body(term()) :: {:ok, String.t()} | {:error, :blank | :too_long | :too_large}
  def normalize_body(body) when is_binary(body) do
    normalized = body |> String.trim() |> normalize_newlines()

    cond do
      normalized == "" -> {:error, :blank}
      String.length(normalized) > @max_graphemes -> {:error, :too_long}
      byte_size(normalized) > @max_bytes -> {:error, :too_large}
      true -> {:ok, normalized}
    end
  end

  def normalize_body(_not_a_string), do: {:error, :blank}

  # tech-doc 002: `idempotency_key` is the browser's `clientMessageId` (a UUID string)
  # for users. Validated as a UUID shape; producer keys for system messages are a
  # separate stable string and are not run through this check.
  @spec valid_client_message_id?(term()) :: boolean()
  def valid_client_message_id?(id) when is_binary(id) do
    Regex.match?(
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      id
    )
  end

  def valid_client_message_id?(_other), do: false

  # A reply target arrives from the browser as a GraphQL `ID`, which is a
  # string on the wire even when it names an integer row. Absent and `nil` both
  # mean "an ordinary message", which is why they succeed rather than failing:
  # the argument is optional, and only a *present* value can be malformed.
  @spec normalize_reply_to_message_id(term()) :: {:ok, pos_integer() | nil} | {:error, :invalid}
  def normalize_reply_to_message_id(nil), do: {:ok, nil}

  def normalize_reply_to_message_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  def normalize_reply_to_message_id(id) when is_binary(id) do
    case Integer.parse(id) do
      # `Integer.parse/1` stops at the first non-digit, so it accepts "12abc".
      # Requiring an empty remainder is what makes this a whole-string check.
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _otherwise -> {:error, :invalid}
    end
  end

  def normalize_reply_to_message_id(_other), do: {:error, :invalid}

  # `family_chat_messages.sender_display_name` is DB-trigger-enforced
  # append-only (see the migration): the value stamped in at commit time can
  # never be corrected retroactively once an account's real display name
  # changes (or, for pre-real-session historical rows, once a genuine account
  # exists at all). Resolving live at read time is therefore the only correct
  # fix; `lookup` is required rather than defaulted to the real account store
  # so a caller without one (e.g. a test boundary with no filesystem-backed
  # identity store) can supply a double for this one dependency -- the real
  # caller (the GraphQL type) passes `&Identity.display_name_for/1` itself.
  @doc "The sender name a reader sees: the live account name, else the stamped one."
  @spec live_sender_display_name(map(), (String.t() -> String.t() | nil)) :: String.t()
  def live_sender_display_name(%{sender_kind: "system"} = message, _lookup),
    do: message.sender_display_name

  def live_sender_display_name(message, lookup) do
    lookup.(message.sender_id) || message.sender_display_name
  end

  @doc """
  Puts the quote of `message`'s reply target under `:reply_to`, from `quotes`, the room's
  messages by ID. A target the room resolves nothing for leaves `:reply_to` nil.
  """
  @spec attach_quote(map(), %{pos_integer() => map()}) :: map()
  # A target this room resolves nothing for leaves `:reply_to` nil rather than
  # raising -- a reply whose target is not in this room renders as an ordinary
  # message, it does not break the page around it.
  def attach_quote(%{reply_to_message_id: nil} = message, _quotes),
    do: Map.put(message, :reply_to, nil)

  def attach_quote(%{reply_to_message_id: id} = message, quotes),
    do: Map.put(message, :reply_to, quote_of(Map.get(quotes, id)))

  defp quote_of(nil), do: nil

  defp quote_of(quoted) do
    %{
      id: quoted.id,
      sender_kind: quoted.sender_kind,
      # Carried for `live_sender_display_name/2`, not for the client: the quote
      # object exposes no `sender_id` field, so this never leaves the server. It
      # is what lets the quote resolve its name through the same seam the
      # message's own sender name already uses, so the two can never disagree.
      sender_id: quoted.sender_id,
      # Stamped name, and the fallback when no live account answers.
      sender_display_name: quoted.sender_display_name,
      body_preview: body_preview(quoted.body)
    }
  end

  # The one place truncation happens. Not in CSS, which a screen reader would
  # read straight through, and not in the browser, which would have to receive
  # the whole body to shorten it.
  defp body_preview(body) do
    collapsed = body |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.length(collapsed) > @preview_graphemes do
      String.slice(collapsed, 0, @preview_graphemes) <> "…"
    else
      collapsed
    end
  end

  defp normalize_newlines(text), do: String.replace(text, "\r\n", "\n")
end
