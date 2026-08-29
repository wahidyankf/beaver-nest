defmodule BnestApp.Storage.RecordMap do
  @moduledoc false

  @sources [
    {~r{^system/bootstrap\.json$}, :bootstrap},
    {~r{^system/accounts/(?<id>[^/]+)\.json$}, :account},
    {~r{^system/usernames/(?<id>[^/]+)\.json$}, :username_index},
    {~r{^system/sessions/(?<id>[^/]+)\.json$}, :session},
    {~r{^system/manifests/(?<id>[^/]+)\.json$}, :manifest},
    {~r{^system/schema-registry\.json$}, :schema_registry},
    {~r{^users/(?<owner>[^/]+)/imports/(?<id>[^/]+)\.json$}, :browser_import},
    {~r{^users/(?<owner>[^/]+)/chat/current\.json$}, :chat},
    {~r{^users/(?<owner>[^/]+)/sifat-allah/progress\.json$}, :sifat_allah},
    {~r{^users/(?<owner>[^/]+)/preferences/theme\.json$}, :theme}
  ]

  @spec sources_for_migration() :: [{Regex.t(), atom()}]
  def sources_for_migration, do: @sources

  @spec classify(String.t()) ::
          {:ok,
           %{
             type: atom(),
             record_type: String.t(),
             owner_id: String.t() | nil,
             record_key: String.t()
           }}
          | {:error, :unsupported_source}
  def classify(relative_path) do
    Enum.find_value(@sources, {:error, :unsupported_source}, fn {pattern, type} ->
      case Regex.named_captures(pattern, relative_path) do
        nil -> nil
        captures -> {:ok, describe(type, captures)}
      end
    end)
  end

  defp describe(:bootstrap, _captures),
    do: %{type: :bootstrap, record_type: "bootstrap", owner_id: nil, record_key: "singleton"}

  defp describe(:schema_registry, _captures),
    do: %{
      type: :schema_registry,
      record_type: "schema-registry",
      owner_id: nil,
      record_key: "singleton"
    }

  defp describe(:account, %{"id" => id}),
    do: %{type: :account, record_type: "account", owner_id: id, record_key: id}

  defp describe(:username_index, %{"id" => id}),
    do: %{type: :username_index, record_type: "username-index", owner_id: nil, record_key: id}

  defp describe(:session, %{"id" => id}),
    do: %{type: :session, record_type: "browser-session", owner_id: nil, record_key: id}

  defp describe(:manifest, %{"id" => id}),
    do: %{type: :manifest, record_type: "import-manifest", owner_id: nil, record_key: id}

  defp describe(:browser_import, %{"owner" => owner, "id" => id}),
    do: %{
      type: :browser_import,
      record_type: "browser-import",
      owner_id: owner,
      record_key: "#{owner}:#{id}"
    }

  defp describe(:chat, %{"owner" => owner}),
    do: %{type: :chat, record_type: "chat", owner_id: owner, record_key: owner}

  defp describe(:sifat_allah, %{"owner" => owner}),
    do: %{
      type: :sifat_allah,
      record_type: "sifat-allah-progress",
      owner_id: owner,
      record_key: owner
    }

  defp describe(:theme, %{"owner" => owner}),
    do: %{type: :theme, record_type: "theme-preference", owner_id: owner, record_key: owner}

  @spec identity_for(atom(), term()) ::
          {:ok, %{record_type: String.t(), record_key: String.t(), owner_id: String.t() | nil}}
          | {:error, :unsupported_record_type}
  def identity_for(:bootstrap, nil),
    do: {:ok, %{record_type: "bootstrap", record_key: "singleton", owner_id: nil}}

  def identity_for(:schema_registry, nil),
    do: {:ok, %{record_type: "schema-registry", record_key: "singleton", owner_id: nil}}

  def identity_for(:account, user_id),
    do: {:ok, %{record_type: "account", record_key: user_id, owner_id: user_id}}

  def identity_for(:username_index, username),
    do: {:ok, %{record_type: "username-index", record_key: username, owner_id: nil}}

  def identity_for(:session, digest),
    do: {:ok, %{record_type: "browser-session", record_key: digest, owner_id: nil}}

  def identity_for(:manifest, import_id),
    do: {:ok, %{record_type: "import-manifest", record_key: import_id, owner_id: nil}}

  def identity_for(:browser_import, {owner_id, import_id}),
    do:
      {:ok,
       %{
         record_type: "browser-import",
         record_key: "#{owner_id}:#{import_id}",
         owner_id: owner_id
       }}

  def identity_for(:chat, user_id),
    do: {:ok, %{record_type: "chat", record_key: user_id, owner_id: user_id}}

  def identity_for(:sifat_allah, user_id),
    do: {:ok, %{record_type: "sifat-allah-progress", record_key: user_id, owner_id: user_id}}

  def identity_for(:theme, user_id),
    do: {:ok, %{record_type: "theme-preference", record_key: user_id, owner_id: user_id}}

  def identity_for(_type, _identity), do: {:error, :unsupported_record_type}

  @spec destination_key(String.t(), String.t() | nil) :: String.t()
  def destination_key(record_type, nil), do: record_type <> "/singleton"
  def destination_key(record_type, key), do: record_type <> "/" <> key
end
