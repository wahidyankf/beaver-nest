defmodule BnestApp.FamilyChat.Domain.Policy do
  @moduledoc """
  Who may reach a room and what they may send there: the canonical room, slug validation,
  the posting gate, message validation, the socket's session digest, and the safe error
  every refusal returns.

  `use_family_chat` capability gating (whether an authenticated identity may use Family Chat
  at all) is a web-boundary concern checked by the GraphQL resolver before the facade is
  reached; this policy only knows whether a caller is authenticated (a non-nil,
  server-resolved user id) and whether what they sent is valid.
  """

  alias BnestApp.FamilyChat.Domain.Message

  @type safe_error :: {:error, %{code: String.t(), details: nil}}

  @canonical_room_slug "ruang-keluarga"
  @slug_pattern ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  @doc "The v1 canonical room slug (tech-doc 005/008: only 'ruang-keluarga' exists)."
  @spec canonical_room_slug() :: String.t()
  def canonical_room_slug, do: @canonical_room_slug

  @doc "Accepts a slug of 1 to 64 bytes of lowercase words joined by single hyphens."
  @spec validate_slug(term()) :: :ok | safe_error()
  def validate_slug(slug) when is_binary(slug) do
    if byte_size(slug) in 1..64 and Regex.match?(@slug_pattern, slug),
      do: :ok,
      else: validation_failed()
  end

  def validate_slug(_invalid_slug), do: validation_failed()

  @doc "Members may post only in a room with member posting enabled."
  @spec validate_posting_enabled(map()) :: :ok | safe_error()
  def validate_posting_enabled(%{member_posting_enabled: true}), do: :ok
  def validate_posting_enabled(_room), do: forbidden()

  @spec validate_client_message_id(term()) :: :ok | safe_error()
  def validate_client_message_id(id) do
    if Message.valid_client_message_id?(id), do: :ok, else: validation_failed()
  end

  @spec validate_body(term()) :: {:ok, String.t()} | safe_error()
  def validate_body(body) do
    case Message.normalize_body(body) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> validation_failed()
    end
  end

  @doc """
  The reply target ID a client named, or nil for an ordinary message. Whether the target is
  a message in the same room is the caller's lookup.
  """
  @spec validate_reply_target(term()) :: {:ok, pos_integer() | nil} | safe_error()
  def validate_reply_target(raw_id) do
    case Message.normalize_reply_to_message_id(raw_id) do
      {:ok, id} -> {:ok, id}
      {:error, :invalid} -> validation_failed()
    end
  end

  @doc "The digest a subscription socket carries in place of the user ID."
  @spec session_digest(String.t()) :: String.t()
  def session_digest(user_id),
    do: :crypto.hash(:sha256, user_id) |> Base.encode16(case: :lower)

  @spec unauthenticated() :: safe_error()
  def unauthenticated, do: {:error, %{code: "UNAUTHENTICATED", details: nil}}

  @spec room_not_found() :: safe_error()
  def room_not_found, do: {:error, %{code: "ROOM_NOT_FOUND", details: nil}}

  @spec validation_failed() :: safe_error()
  def validation_failed, do: {:error, %{code: "VALIDATION_FAILED", details: nil}}

  @spec forbidden() :: safe_error()
  def forbidden, do: {:error, %{code: "FORBIDDEN", details: nil}}
end
