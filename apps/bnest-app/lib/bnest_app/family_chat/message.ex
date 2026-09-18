defmodule BnestApp.FamilyChat.Message do
  @moduledoc false

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

  defp normalize_newlines(text), do: String.replace(text, "\r\n", "\n")
end
