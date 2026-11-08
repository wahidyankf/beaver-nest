defmodule BnestApp.TestInstance.Seed do
  @moduledoc """
  Validates a test instance seed body (ADR 001, section 2) without touching any state. A seed is the
  wire shape `POST /instances` carries: string keys and JSON values. Nothing here writes SQL, a file
  or a fixture.

  ## API

    * `validate(seed_map, instance)` is pure. It returns `{:ok, normalized}` or
      `{:error, %{code: :seed_invalid, reason: reason, path: path}}`. `instance` is a map with
      `:instance_id`. An optional `:seeded` map (username => `%{user_id:, roles:}`) names the
      accounts an earlier seed created on the same instance, so a later seed can refer to them.

  Every error value holds the code, the reason and the path only. A password, a push key or an
  endpoint is never echoed.

  ## Normalized seed

      %{
        "accounts" => [%{"username", "password", "roles"}],
        "familyChat" => %{"messages" => [%{"sender", "body", "idempotencyKey"}]},
        "pushSubscriptions" => [%{"owner", "endpoint", "p256dh", "auth"}],
        "records" => [%{"owner", "kind", "value"}]
      }

  Every section is present; an absent section is empty. Roles are sorted and the message body is
  normalized the way Family Chat stores it.

  ## Limits

  At most 40 accounts per instance, 500 family chat messages, 40 push subscriptions and 40 records
  per seed. A username must be `test-user-` plus `[a-z0-9-]`, must carry the instance short id (the
  first eight characters of the instance id) as a whole hyphen-separated segment, and must pass
  the production username rule (at most 32 characters in all).
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.CodexChat.Domain.TranscriptRecord
  alias BnestApp.FamilyChat.Domain.Message
  alias BnestApp.Identity.Domain.Credentials
  alias BnestApp.Preferences
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Domain.Policy, as: PushPolicy
  alias BnestApp.SifatAllah.Domain.ProgressRecord
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.RecordSchema

  @sections ~w(accounts familyChat pushSubscriptions records)
  @record_kinds ~w(sifatAllahProgress codexChatTranscript themePreference)
  @roles ~w(children parents admin)
  @max_accounts 40
  @max_messages 500
  @max_subscriptions 40
  @max_records 40
  @username_pattern ~r/\Atest-user-([a-z0-9-]{1,48})\z/
  @system_sender "system"
  @max_system_key_bytes 128
  # Placeholder values used only to find which field a push policy refuses, and to check a record
  # against the production record schema. Neither is stored.
  @probe_endpoint "https://web.push.apple.com/seed-probe"
  @probe_key "AAAA"
  @probe_owner "user-probe"
  @probe_time ~U[2000-01-01 00:00:00Z]

  @type error :: %{code: :seed_invalid, reason: atom(), path: String.t()}

  @doc """
  Checks a seed body against the instance without touching any state. See the moduledoc for the
  rules and the normalized shape.
  """
  @spec validate(term(), map()) :: {:ok, map()} | {:error, error()}
  def validate(seed, instance) when is_map(seed) do
    seeded = Map.get(instance, :seeded, %{})
    short = short_id(instance.instance_id)

    with :ok <- known_sections(seed),
         {:ok, accounts} <- accounts(seed, short, seeded),
         known = known_usernames(seeded, accounts),
         {:ok, messages} <- messages(seed, known),
         {:ok, subscriptions} <- subscriptions(seed, known),
         {:ok, records} <- records(seed, known) do
      {:ok,
       %{
         "accounts" => accounts,
         "familyChat" => %{"messages" => messages},
         "pushSubscriptions" => subscriptions,
         "records" => records
       }}
    end
  end

  def validate(_seed, _instance), do: invalid(:invalid_payload, "seed")

  # Validation

  defp known_sections(seed) do
    case Enum.find(Map.keys(seed), &(&1 not in @sections)) do
      nil -> :ok
      key -> invalid(:invalid_payload, root_path(key))
    end
  end

  defp root_path(key) when is_binary(key), do: key
  defp root_path(_key), do: "seed"

  defp accounts(seed, short, seeded) do
    with {:ok, inputs} <-
           items(Map.get(seed, "accounts", []), "accounts", @max_accounts - map_size(seeded)) do
      each(inputs, "accounts", &account(&1, &2, &3, short, seeded))
    end
  end

  defp account(input, path, done, short, seeded) do
    with :ok <- shape(input, path, ~w(username password roles)),
         {:ok, name} <- username(input["username"], path, short),
         :ok <- unique_username(name, path, done, seeded),
         {:ok, roles} <- roles(input["roles"], path),
         {:ok, password} <- password(input["password"], path) do
      {:ok, %{"username" => name, "password" => password, "roles" => roles}}
    end
  end

  defp username(name, path, short) do
    with {:ok, name} <- string(name, path, "username") do
      if valid_username?(name, short),
        do: {:ok, name},
        else: invalid(:invalid_username, "#{path}.username")
    end
  end

  defp valid_username?(name, short) do
    case Regex.run(@username_pattern, name, capture: :all_but_first) do
      [suffix] ->
        short in String.split(suffix, "-") and
          match?({:ok, _}, Credentials.normalize_username(name))

      nil ->
        false
    end
  end

  defp unique_username(name, path, done, seeded) do
    if Map.has_key?(seeded, name) or Enum.any?(done, &(&1["username"] == name)),
      do: invalid(:duplicate_username, "#{path}.username"),
      else: :ok
  end

  defp roles(roles, path) when is_list(roles) do
    if roles != [] and Enum.uniq(roles) == roles and Enum.all?(roles, &(&1 in @roles)),
      do: {:ok, Enum.sort(roles)},
      else: invalid(:invalid_role, "#{path}.roles")
  end

  defp roles(_roles, path), do: invalid(:invalid_payload, "#{path}.roles")

  defp password(password, path) do
    if is_binary(password) and Credentials.valid_password?(password),
      do: {:ok, password},
      else: invalid(:invalid_payload, "#{path}.password")
  end

  defp messages(seed, known) do
    with {:ok, chat} <- family_chat(Map.get(seed, "familyChat", %{})),
         {:ok, inputs} <-
           items(Map.get(chat, "messages", []), "familyChat.messages", @max_messages) do
      each(inputs, "familyChat.messages", &message(&1, &2, &3, known))
    end
  end

  defp family_chat(chat) when is_map(chat) do
    case Enum.find(Map.keys(chat), &(&1 != "messages")) do
      nil -> {:ok, chat}
      key -> invalid(:invalid_payload, field_path("familyChat", key))
    end
  end

  defp family_chat(_chat), do: invalid(:invalid_payload, "familyChat")

  defp message(input, path, done, known) do
    with :ok <- shape(input, path, ~w(sender body idempotencyKey)),
         {:ok, sender} <- sender(input["sender"], path, known),
         {:ok, body} <- body(input["body"], path),
         {:ok, key} <- message_key(input["idempotencyKey"], sender, path),
         :ok <- unique_message(sender, key, path, done) do
      {:ok, %{"sender" => sender, "body" => body, "idempotencyKey" => key}}
    end
  end

  defp sender(sender, path, known) do
    with {:ok, sender} <- string(sender, path, "sender") do
      if sender == @system_sender or MapSet.member?(known, sender),
        do: {:ok, sender},
        else: invalid(:unknown_sender, "#{path}.sender")
    end
  end

  defp body(body, path) when is_binary(body) do
    case Message.normalize_body(body) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> invalid(:invalid_payload, "#{path}.body")
    end
  end

  defp body(_body, path), do: invalid(:invalid_payload, "#{path}.body")

  # A user message carries the browser's client message id, a UUID. A system message carries a
  # stable producer key, which Family Chat stores as both the sender id and the idempotency key.
  defp message_key(key, sender, path) do
    with {:ok, key} <- string(key, path, "idempotencyKey") do
      if valid_message_key?(sender, key),
        do: {:ok, key},
        else: invalid(:invalid_payload, "#{path}.idempotencyKey")
    end
  end

  defp valid_message_key?(@system_sender, key), do: byte_size(key) <= @max_system_key_bytes
  defp valid_message_key?(_user, key), do: Message.valid_client_message_id?(key)

  defp unique_message(sender, key, path, done) do
    if Enum.any?(done, &(&1["sender"] == sender and &1["idempotencyKey"] == key)),
      do: invalid(:invalid_payload, "#{path}.idempotencyKey"),
      else: :ok
  end

  defp subscriptions(seed, known) do
    hosts = PushNotifications.adapter(:push_sender).synthetic_provider_hosts()

    with {:ok, inputs} <-
           items(Map.get(seed, "pushSubscriptions", []), "pushSubscriptions", @max_subscriptions) do
      each(inputs, "pushSubscriptions", &subscription(&1, &2, &3, known, hosts))
    end
  end

  defp subscription(input, path, done, known, hosts) do
    with :ok <- shape(input, path, ~w(owner endpoint p256dh auth)),
         {:ok, owner} <- string(input["owner"], path, "owner"),
         :ok <- known_owner(owner, known, path),
         {:ok, endpoint} <- string(input["endpoint"], path, "endpoint"),
         {:ok, p256dh} <- string(input["p256dh"], path, "p256dh"),
         {:ok, auth} <- string(input["auth"], path, "auth"),
         :ok <- push_policy(endpoint, p256dh, auth, path, hosts),
         :ok <- unique_endpoint(endpoint, path, done) do
      {:ok, %{"owner" => owner, "endpoint" => endpoint, "p256dh" => p256dh, "auth" => auth}}
    end
  end

  # The production policy decides what a subscription may hold (https, an allowed host, a key
  # shape). A refusal is reported at the one field that causes it.
  defp push_policy(endpoint, p256dh, auth, path, hosts) do
    case PushPolicy.validate_subscription_input(
           %{"endpoint" => endpoint, "p256dh" => p256dh, "auth" => auth},
           hosts
         ) do
      {:ok, _subscription} ->
        :ok

      {:error, _reason} ->
        invalid(:invalid_payload, refused_field(endpoint, p256dh, auth, path, hosts))
    end
  end

  defp refused_field(endpoint, p256dh, auth, path, hosts) do
    cond do
      refused?(%{"endpoint" => endpoint, "p256dh" => @probe_key, "auth" => @probe_key}, hosts) ->
        "#{path}.endpoint"

      refused?(%{"endpoint" => @probe_endpoint, "p256dh" => p256dh, "auth" => @probe_key}, hosts) ->
        "#{path}.p256dh"

      refused?(%{"endpoint" => @probe_endpoint, "p256dh" => @probe_key, "auth" => auth}, hosts) ->
        "#{path}.auth"

      true ->
        path
    end
  end

  defp refused?(input, hosts),
    do: match?({:error, _reason}, PushPolicy.validate_subscription_input(input, hosts))

  defp unique_endpoint(endpoint, path, done) do
    if Enum.any?(done, &(&1["endpoint"] == endpoint)),
      do: invalid(:invalid_payload, "#{path}.endpoint"),
      else: :ok
  end

  defp records(seed, known) do
    with {:ok, inputs} <- items(Map.get(seed, "records", []), "records", @max_records) do
      each(inputs, "records", &record(&1, &2, &3, known))
    end
  end

  defp record(input, path, done, known) do
    with :ok <- shape(input, path, ~w(owner kind value)),
         {:ok, owner} <- string(input["owner"], path, "owner"),
         :ok <- known_owner(owner, known, path),
         {:ok, kind} <- record_kind(input["kind"], path),
         :ok <- unique_record(owner, kind, path, done),
         {:ok, value} <- record_value(kind, input["value"], path) do
      {:ok, %{"owner" => owner, "kind" => kind, "value" => value}}
    end
  end

  defp record_kind(kind, _path) when kind in @record_kinds, do: {:ok, kind}
  defp record_kind(_kind, path), do: invalid(:invalid_payload, "#{path}.kind")

  defp unique_record(owner, kind, path, done) do
    if Enum.any?(done, &(&1["owner"] == owner and &1["kind"] == kind)),
      do: invalid(:invalid_payload, path),
      else: :ok
  end

  # A progress value is checked as the record the progress store would hold, by the production
  # record schema and its kind. A transcript is normalized to the snapshot the transcript store
  # would hold. A theme is one of the themes a user may choose.
  defp record_value("sifatAllahProgress", value, path) when is_map(value) do
    if stored_valid?(ProgressRecord.record(@probe_owner, value, nil, @probe_time)),
      do: {:ok, value},
      else: invalid(:invalid_payload, "#{path}.value")
  end

  defp record_value("codexChatTranscript", value, path) do
    with {:ok, transcript} <- Transcript.restore(value),
         {:ok, state} <- Transcript.snapshot(transcript),
         true <- stored_valid?(TranscriptRecord.record(@probe_owner, state, nil, @probe_time)) do
      {:ok, state}
    else
      _invalid -> invalid(:invalid_payload, "#{path}.value")
    end
  end

  defp record_value("themePreference", value, path) when is_map(value) do
    case Enum.find(Map.keys(value), &(&1 != "theme")) do
      nil -> theme_value(Map.get(value, "theme"), path)
      key -> invalid(:invalid_payload, field_path("#{path}.value", key))
    end
  end

  defp record_value(_kind, _value, path), do: invalid(:invalid_payload, "#{path}.value")

  defp theme_value(theme, path) do
    if theme in Preferences.themes(),
      do: {:ok, %{"theme" => theme}},
      else: invalid(:invalid_payload, "#{path}.value.theme")
  end

  # The store assigns the revision, so a probe revision stands in for it.
  defp stored_valid?(record) do
    match?(
      {:ok, _record},
      RecordSchema.validate(Map.put(record, "revision", 1), Storage.record_kinds())
    )
  end

  defp known_owner(owner, known, path) do
    if MapSet.member?(known, owner),
      do: :ok,
      else: invalid(:unknown_owner, "#{path}.owner")
  end

  defp known_usernames(seeded, accounts) do
    MapSet.new(Map.keys(seeded) ++ Enum.map(accounts, & &1["username"]))
  end

  # Shared shape rules. A list section is refused when it is not a list, or when it holds more
  # than the limit. `limit` is the room left for it.

  defp items(value, path, limit) when is_list(value) do
    if length(value) <= limit, do: {:ok, value}, else: invalid(:too_many, path)
  end

  defp items(_value, path, _limit), do: invalid(:invalid_payload, path)

  # Checks one item's fields: an object, with exactly the required keys.
  defp shape(item, path, required) when is_map(item) do
    case Enum.find(Map.keys(item), &(&1 not in required)) do
      nil -> missing_field(item, path, required)
      key -> invalid(:invalid_payload, field_path(path, key))
    end
  end

  defp shape(_item, path, _required), do: invalid(:invalid_payload, path)

  defp missing_field(item, path, required) do
    case Enum.find(required, &(not Map.has_key?(item, &1))) do
      nil -> :ok
      key -> invalid(:invalid_payload, field_path(path, key))
    end
  end

  defp string(value, _path, _field) when is_binary(value) and value != "", do: {:ok, value}
  defp string(_value, path, field), do: invalid(:invalid_payload, "#{path}.#{field}")

  # Validates each item in order. `check.(input, path, done)` receives the items already accepted,
  # so a duplicate can be refused. Returns the normalized items in seed order.
  defp each(inputs, base, check) do
    inputs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {input, index}, {:ok, done} ->
      case check.(input, "#{base}[#{index}]", done) do
        {:ok, item} -> {:cont, {:ok, [item | done]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp field_path(path, key) when is_binary(key), do: "#{path}.#{key}"
  defp field_path(path, _key), do: path

  defp short_id(instance_id), do: String.slice(instance_id, 0, 8)

  defp invalid(reason, path),
    do: {:error, %{code: :seed_invalid, reason: reason, path: path}}
end
