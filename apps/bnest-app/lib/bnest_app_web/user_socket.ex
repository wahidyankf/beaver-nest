defmodule BnestAppWeb.UserSocket do
  @moduledoc """
  The Absinthe GraphQL subscription socket at `/api/graphql/socket`. Identity is
  resolved only from the server-decoded session carried in `connect_info`
  (the same cookie/session configuration as HTTP); socket params are never
  trusted for identity, role, or authorization (tech-doc 008).
  """

  use Phoenix.Socket
  use Absinthe.Phoenix.Socket, schema: BnestAppWeb.Schema

  alias BnestApp.FamilyChat

  @impl Phoenix.Socket
  def connect(_params, socket, connect_info) do
    with %{"userId" => _user_id} = user <- session_user(connect_info),
         {:ok, resolved} <- FamilyChat.socket_context_for(user["userId"]) do
      socket =
        Absinthe.Phoenix.Socket.put_options(socket,
          context: Map.put(resolved, :current_user, user)
        )

      {:ok, socket}
    else
      _unauthenticated -> :error
    end
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil

  defp session_user(%{session: %{"current_user" => user}}) when is_map(user), do: user
  defp session_user(_connect_info), do: nil
end
