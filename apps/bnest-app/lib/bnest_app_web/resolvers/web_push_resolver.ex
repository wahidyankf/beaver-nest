defmodule BnestAppWeb.Resolvers.WebPushResolver do
  @moduledoc """
  Thin GraphQL-boundary adapter for Web Push, mirroring
  `BnestAppWeb.Resolvers.FamilyChatResolver`'s shape exactly. `user_id` and
  `session_digest` are read only from the server-resolved session context
  (`router.ex`'s `put_absinthe_context/2`), never from a client-supplied
  argument (tech-doc 002: "Derive user_id, session_digest ... server-side").
  """

  alias BnestApp.Identity
  alias BnestApp.PushNotifications

  @spec web_push_configuration(map(), Absinthe.Resolution.t()) :: {:ok, map()}
  def web_push_configuration(_args, _resolution), do: PushNotifications.configuration()

  @spec current_web_push_subscription(map(), Absinthe.Resolution.t()) ::
          {:ok, map()} | {:error, keyword()}
  def current_web_push_subscription(_args, resolution) do
    with {:ok, user_id, session_digest} <- authorize(resolution) do
      wrap(PushNotifications.current_subscription(user_id, session_digest))
    end
  end

  @spec upsert_web_push_subscription(map(), Absinthe.Resolution.t()) ::
          {:ok, map()} | {:error, keyword()}
  def upsert_web_push_subscription(args, resolution) do
    with {:ok, user_id, session_digest} <- authorize(resolution) do
      input = %{"endpoint" => args.endpoint, "p256dh" => args.p256dh, "auth" => args.auth}
      wrap(PushNotifications.upsert_subscription(user_id, session_digest, input))
    end
  end

  @spec disable_current_web_push_subscription(map(), Absinthe.Resolution.t()) ::
          {:ok, map()} | {:error, keyword()}
  def disable_current_web_push_subscription(_args, resolution) do
    with {:ok, user_id, session_digest} <- authorize(resolution) do
      wrap(PushNotifications.disable_subscription(user_id, session_digest))
    end
  end

  # Web Push exists only in service of family chat, so it is gated behind
  # the same `:use_family_chat` capability as `FamilyChatResolver` rather
  # than a separate capability atom.
  defp authorize(%{
         context: %{current_user: %{"userId" => user_id} = user, session_digest: session_digest}
       })
       when is_binary(session_digest) do
    if Identity.authorize(user, :use_family_chat, user_id) do
      {:ok, user_id, session_digest}
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
  defp safe_message("VALIDATION_FAILED"), do: "The request is invalid."
  defp safe_message(_other), do: "The request could not be completed."
end
