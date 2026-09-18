defmodule BnestAppWeb.Schema do
  @moduledoc """
  The public GraphQL schema. Every UI-facing Family Chat operation is declared
  here; internal service boundaries (Scheduler, Backup, retention, the system
  message producer) are intentionally absent (tech-doc 008).
  """

  use Absinthe.Schema

  import_types(Absinthe.Type.Custom)
  import_types(BnestAppWeb.Schema.Types.FamilyChatTypes)
  import_types(BnestAppWeb.Schema.Types.WebPushTypes)

  alias BnestAppWeb.Resolvers.FamilyChatResolver
  alias BnestAppWeb.Resolvers.WebPushResolver

  query do
    field :family_chat_rooms, non_null(list_of(non_null(:family_chat_room))) do
      resolve(&FamilyChatResolver.family_chat_rooms/2)
    end

    field :family_chat_room, :family_chat_room do
      arg(:slug, non_null(:string))
      resolve(&FamilyChatResolver.family_chat_room/2)
    end

    field :family_chat_messages, non_null(:family_chat_message_connection) do
      arg(:room_slug, non_null(:string))
      arg(:before_id, :id)
      arg(:after_id, :id)
      arg(:limit, :integer)
      resolve(&FamilyChatResolver.family_chat_messages/2)
    end

    field :web_push_configuration, non_null(:web_push_configuration) do
      resolve(&WebPushResolver.web_push_configuration/2)
    end

    field :current_web_push_subscription, non_null(:web_push_subscription) do
      resolve(&WebPushResolver.current_web_push_subscription/2)
    end
  end

  mutation do
    field :send_family_chat_message, :family_chat_message do
      arg(:room_slug, non_null(:string))
      arg(:client_message_id, non_null(:id))
      arg(:body, non_null(:string))
      resolve(&FamilyChatResolver.send_family_chat_message/2)
    end

    field :upsert_web_push_subscription, :web_push_subscription do
      arg(:endpoint, non_null(:string))
      arg(:p256dh, non_null(:string))
      arg(:auth, non_null(:string))
      resolve(&WebPushResolver.upsert_web_push_subscription/2)
    end

    field :disable_current_web_push_subscription, :web_push_subscription do
      resolve(&WebPushResolver.disable_current_web_push_subscription/2)
    end
  end

  subscription do
    field :family_chat_message_committed, :family_chat_message do
      arg(:room_slug, non_null(:string))

      config(&FamilyChatResolver.subscription_config/2)
    end
  end

  @doc """
  The declared mutation field names on the public schema, as GraphQL field
  names (camelCase, matching the wire contract). Used to prove the internal
  system-message producer has no public mutation (tech-doc 002/007: it is a
  typed Elixir service call, never GraphQL).
  """
  @spec mutation_field_names() :: [String.t()]
  def mutation_field_names do
    __MODULE__
    |> Absinthe.Schema.lookup_type(:mutation)
    |> Map.fetch!(:fields)
    |> Map.keys()
    |> Enum.map(&Absinthe.Utils.camelize(Atom.to_string(&1), lower: true))
  end
end
