defmodule BnestApp.TestInstance.Seed do
  @moduledoc """
  Seeds one test instance through production facades only (ADR 001, section 2). The seed body
  is the wire shape `POST /instances` and `POST /instances/:id/seed` carry: string keys and JSON
  values. Nothing here writes SQL, a file or a fixture.

  ## API

    * `validate(seed_map, instance)` is pure. It returns `{:ok, normalized}` or
      `{:error, %{code: :seed_invalid, reason: reason, path: path}}`. `instance` is a map with
      `:instance_id`. An optional `:seeded` map (username => `%{user_id:, roles:}`) names the
      accounts an earlier seed created on the same instance, so a later seed can refer to them.
    * `apply(instance, seed_key, seed_map)` validates the body, then writes it through the
      facades. It returns `{:ok, %{seed_key:, applied:, accounts:}}`, where `accounts` is
      `[%{username:, user_id:, roles:}]` in seed order. The same key with the same body returns
      `applied: false` and writes nothing. The same key with another body returns
      `{:error, :seed_conflict}`. The registry of applied keys lives in the instance state
      (`BnestApp.TestInstance.seed_registry/1`), so `drop!/1` clears it.
    * `push_session_key/1` is the session key a seeded subscription is stored under, so a test
      can read it back through `PushNotifications.current_subscription/2`.

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

  ## Facades per section

    * accounts with an admin on a `flat_primary` instance, while setup is open:
      `BnestApp.Identity.bootstrap/1`, the admin set of the seed, so `/setup` closes as in production.
      Production refuses bootstrap on a `sqlite_primary` instance (the routed identity store is never
      empty), so there every account goes through the identity store.
    * every other account: `BnestApp.Identity.adapter(:identity_store)` with
      `IdentityStore.put_account/2` and `put_username/2`, and the configured credential hasher.
    * family chat user messages: `BnestApp.FamilyChat.send_message/5`, which the GraphQL
      `sendFamilyChatMessage` resolver calls.
    * family chat system messages: `BnestApp.FamilyChat.post_system_message/3`, the internal
      system-sender entry point (no GraphQL field reaches it).
    * push subscriptions: `BnestApp.PushNotifications.upsert_subscription/3`, the entry point the
      `upsertWebPushSubscription` resolver calls.
    * `sifatAllahProgress`: `BnestApp.SifatAllah.save_progress/3`.
    * `codexChatTranscript`: `BnestApp.CodexChat.save_transcript/3`.
    * `themePreference`: `BnestApp.Preferences.put_theme/3`, the call `PUT /preferences/theme` makes.
    * `browserImportInterrupted`: the manifest and envelope an import leaves when it stops after
      preserving the envelope, written through `Storage.Records` as `Storage.import_browser/2` reads.
      Only a `flat_primary` instance takes it, because that is the only instance whose records store
      is its own flat root.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  # `apply/3` is this module's own function, so `Kernel.apply/3` is not imported.
  import Kernel, except: [apply: 3]

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.CodexChat.Domain.TranscriptRecord
  alias BnestApp.FamilyChat
  alias BnestApp.FamilyChat.Domain.Message
  alias BnestApp.Identity
  alias BnestApp.Identity.Domain.Credentials
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.Preferences
  alias BnestApp.PushNotifications
  alias BnestApp.PushNotifications.Domain.Policy, as: PushPolicy
  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.ProgressRecord
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.Manifest
  alias BnestApp.Storage.Domain.Normalizer
  alias BnestApp.Storage.Domain.RecordSchema
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Storage.Records
  alias BnestApp.TestInstance

  @sections ~w(accounts familyChat pushSubscriptions records)
  @record_kinds ~w(sifatAllahProgress codexChatTranscript themePreference browserImportInterrupted)
  @roles ~w(children parents admin)
  @max_accounts 40
  @max_messages 500
  @max_subscriptions 40
  @max_records 40
  # The browser sources an import recognizes, with the largest payload each may hold. A copy of the
  # table `BnestApp.Storage.Import` keeps private; the integration test "the seed's source limits are
  # the production import's limits" holds the two equal.
  @browser_sources %{
    {"sessionStorage", "bnest.chat.v1"} => 500_000,
    {"localStorage", "bnest.sifat-allah.v1"} => 10_000,
    {"localStorage", "phx:theme"} => 16
  }
  @seed_key_pattern ~r/\A[a-z0-9][a-z0-9-]{0,63}\z/
  # 22 characters after `test-user-` make the 32 the production username rule and the login field allow in all.
  @username_pattern ~r/\Atest-user-([a-z0-9-]{1,22})\z/
  @system_sender "system"
  @max_system_key_bytes 128
  # Placeholder values used only to find which field a push policy refuses, and to check a record
  # against the production record schema. Neither is stored.
  @probe_endpoint "https://web.push.apple.com/seed-probe"
  @probe_key "AAAA"
  @probe_owner "user-probe"
  @probe_time ~U[2000-01-01 00:00:00Z]

  @type error :: %{code: :seed_invalid, reason: atom(), path: String.t()}
  @type account :: %{username: String.t(), user_id: String.t(), roles: [String.t()]}
  @type result :: %{seed_key: String.t(), applied: boolean(), accounts: [account()]}

  @doc """
  Checks a seed body against the instance without touching any state. See the moduledoc for the
  rules and the normalized shape.
  """
  @spec validate(term(), map()) :: {:ok, map()} | {:error, error()}
  def validate(seed, instance) when is_map(seed) do
    seeded = Map.get(instance, :seeded, %{})
    short = short_id(instance.instance_id)

    with :ok <- known_sections(seed),
         :ok <- database_sections(seed, instance),
         {:ok, accounts} <- accounts(seed, short, seeded),
         known = known_usernames(seeded, accounts),
         {:ok, messages} <- messages(seed, known),
         {:ok, subscriptions} <- subscriptions(seed, known),
         {:ok, records} <- records(seed, known, instance) do
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

  # Family Chat and push live in the SQLite database. An instance whose storage is unconfigured has none, so a
  # seed that fills either section is refused at that section instead of creating a database at a default place.
  defp database_sections(seed, %{storage: :unconfigured}) do
    case Enum.find(~w(familyChat pushSubscriptions), &filled?(Map.get(seed, &1))) do
      nil -> :ok
      section -> invalid(:wrong_phase, section)
    end
  end

  defp database_sections(_seed, _instance), do: :ok

  defp filled?(nil), do: false
  defp filled?(value) when value in [%{}, []], do: false
  defp filled?(_value), do: true

  @doc """
  Validates `seed_map` and writes it through the production facades, under `seed_key`. Idempotent
  per key: a repeated key with the same body is `applied: false`, and a repeated key with another
  body is `{:error, :seed_conflict}`. The instance must be the current one.
  """
  @spec apply(map(), term(), term()) ::
          {:ok, result()}
          | {:error,
             error() | :seed_conflict | :not_current | {:facade, atom(), atom() | String.t()}}
  def apply(instance, seed_key, seed) do
    with :ok <- check_seed_key(seed_key),
         :ok <- check_body(seed),
         {:ok, registry} <- TestInstance.seed_registry(instance) do
      fingerprint = fingerprint(seed)

      case Map.fetch(keys(registry), seed_key) do
        :error ->
          create(instance, registry, seed_key, seed, fingerprint)

        {:ok, %{fingerprint: ^fingerprint, accounts: accounts}} ->
          {:ok, %{seed_key: seed_key, applied: false, accounts: accounts}}

        {:ok, _other_body} ->
          {:error, :seed_conflict}
      end
    end
  end

  @doc "The session key a seeded push subscription is stored under."
  @spec push_session_key(String.t()) :: String.t()
  def push_session_key(endpoint) when is_binary(endpoint), do: "test-seed-push:" <> endpoint

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

  defp records(seed, known, instance) do
    phase = Map.get(instance, :phase)

    with {:ok, inputs} <- items(Map.get(seed, "records", []), "records", @max_records) do
      each(inputs, "records", &record(&1, &2, &3, known, phase))
    end
  end

  defp record(input, path, done, known, phase) do
    with :ok <- shape(input, path, ~w(owner kind value)),
         {:ok, owner} <- string(input["owner"], path, "owner"),
         :ok <- known_owner(owner, known, path),
         {:ok, kind} <- record_kind(input["kind"], path),
         :ok <- unique_record(owner, kind, path, done),
         {:ok, value} <- record_value(kind, input["value"], path, phase) do
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
  defp record_value("sifatAllahProgress", value, path, _phase) when is_map(value) do
    if stored_valid?(ProgressRecord.record(@probe_owner, value, nil, @probe_time)),
      do: {:ok, value},
      else: invalid(:invalid_payload, "#{path}.value")
  end

  defp record_value("codexChatTranscript", value, path, _phase) do
    with {:ok, transcript} <- Transcript.restore(value),
         {:ok, state} <- Transcript.snapshot(transcript),
         true <- stored_valid?(TranscriptRecord.record(@probe_owner, state, nil, @probe_time)) do
      {:ok, state}
    else
      _invalid -> invalid(:invalid_payload, "#{path}.value")
    end
  end

  defp record_value("themePreference", value, path, _phase) when is_map(value) do
    case Enum.find(Map.keys(value), &(&1 != "theme")) do
      nil -> theme_value(Map.get(value, "theme"), path)
      key -> invalid(:invalid_payload, field_path("#{path}.value", key))
    end
  end

  # An interrupted import is preserved in the store the production import reads, which only a
  # flat-primary instance keeps in its own root. On a SQLite instance that store is the run base,
  # which must stay data-free, so the kind is refused there.
  defp record_value("browserImportInterrupted", value, path, :flat_primary),
    do: interrupted_import(value, path)

  defp record_value("browserImportInterrupted", _value, path, _phase),
    do: invalid(:wrong_phase, "#{path}.kind")

  defp record_value(_kind, _value, path, _phase), do: invalid(:invalid_payload, "#{path}.value")

  defp interrupted_import(value, path) do
    value_path = "#{path}.value"

    with :ok <- shape(value, value_path, ~w(storageArea storageKey payload)),
         {:ok, limit} <- browser_source(value, value_path),
         :ok <- browser_payload(value["payload"], limit, value_path) do
      {:ok, Map.take(value, ~w(storageArea storageKey payload))}
    end
  end

  defp browser_source(value, value_path) do
    case Map.fetch(@browser_sources, {value["storageArea"], value["storageKey"]}) do
      {:ok, limit} -> {:ok, limit}
      :error -> invalid(:unsupported_source, "#{value_path}.storageKey")
    end
  end

  defp browser_payload(payload, limit, value_path) when is_binary(payload) do
    if byte_size(payload) <= limit,
      do: :ok,
      else: invalid(:oversized, "#{value_path}.payload")
  end

  defp browser_payload(_payload, _limit, value_path),
    do: invalid(:invalid_payload, "#{value_path}.payload")

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

  # Apply

  defp check_seed_key(key) when is_binary(key) do
    if Regex.match?(@seed_key_pattern, key),
      do: :ok,
      else: invalid(:unknown_seed_key, "seedKey")
  end

  defp check_seed_key(_key), do: invalid(:unknown_seed_key, "seedKey")

  defp check_body(seed) when is_map(seed), do: :ok
  defp check_body(_seed), do: invalid(:invalid_payload, "seed")

  defp create(instance, registry, seed_key, seed, fingerprint) do
    view = Map.put(instance, :seeded, accounts_of(registry))

    with {:ok, normalized} <- validate(seed, view),
         {:ok, created} <- write_accounts(normalized["accounts"], registry, instance.phase),
         users = Map.merge(accounts_of(registry), users_of(created)),
         :ok <- write_messages(normalized["familyChat"]["messages"], users),
         :ok <- write_subscriptions(normalized["pushSubscriptions"], users),
         :ok <- write_records(normalized["records"], users),
         :ok <- remember(instance, registry, seed_key, fingerprint, created) do
      {:ok, %{seed_key: seed_key, applied: true, accounts: created}}
    end
  end

  defp remember(instance, registry, seed_key, fingerprint, created) do
    updated = %{
      keys: Map.put(keys(registry), seed_key, %{fingerprint: fingerprint, accounts: created}),
      accounts: Map.merge(accounts_of(registry), users_of(created)),
      bootstrapped:
        bootstrapped?(registry) or
          (instance.phase == :flat_primary and Enum.any?(created, &("admin" in &1.roles)))
    }

    TestInstance.put_seed_registry(instance, updated)
  end

  defp keys(registry), do: Map.get(registry, :keys, %{})
  defp accounts_of(registry), do: Map.get(registry, :accounts, %{})
  defp bootstrapped?(registry), do: Map.get(registry, :bootstrapped, false)

  defp users_of(accounts) do
    Map.new(accounts, &{&1.username, %{user_id: &1.user_id, roles: &1.roles}})
  end

  # Accounts. On a `flat_primary` instance the first admin set goes through `Identity.bootstrap/1`,
  # which closes setup. Production refuses bootstrap on a `sqlite_primary` instance, because its
  # routed identity store never reads as empty, so there no account is bootstrapped: every account
  # goes through the identity store, and setup stays unopened. A refusal from bootstrap is returned,
  # not hidden. Every account that is not bootstrapped goes through the identity store.

  defp write_accounts([], _registry, _phase), do: {:ok, []}

  defp write_accounts(accounts, registry, phase) do
    with {:ok, bootstrapped} <- bootstrap(first_admin_set(accounts, registry, phase)),
         {:ok, stored} <-
           store_accounts(Enum.reject(accounts, &Map.has_key?(bootstrapped, &1["username"]))) do
      ids = Map.merge(bootstrapped, stored)

      {:ok,
       Enum.map(accounts, fn account ->
         %{
           username: account["username"],
           user_id: Map.fetch!(ids, account["username"]),
           roles: account["roles"]
         }
       end)}
    end
  end

  defp first_admin_set(accounts, registry, :flat_primary) do
    if bootstrapped?(registry),
      do: [],
      else: Enum.filter(accounts, &("admin" in &1["roles"]))
  end

  defp first_admin_set(_accounts, _registry, :sqlite_primary), do: []

  defp bootstrap([]), do: {:ok, %{}}

  defp bootstrap(accounts) do
    case Identity.bootstrap(accounts) do
      {:ok, public} ->
        ids =
          Enum.zip_with(accounts, public, fn account, %{"userId" => user_id} ->
            {account["username"], user_id}
          end)

        {:ok, Map.new(ids)}

      {:error, reason} ->
        facade_error(:identity, reason)
    end
  end

  defp store_accounts(accounts) do
    store = Identity.adapter(:identity_store).new(Storage.active_store())

    Enum.reduce_while(accounts, {:ok, %{}}, fn account, {:ok, ids} ->
      case store_account(store, account) do
        {:ok, user_id} -> {:cont, {:ok, Map.put(ids, account["username"], user_id)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # The records a bootstrap writes, built the same way. The read back checks the store kept them.
  defp store_account(store, %{"username" => name, "password" => password, "roles" => roles}) do
    user_id = "user-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
    now = Storage.now()

    with {:ok, verifier} <- Identity.adapter(:credential_hasher).hash(password),
         account = %{
           "schemaVersion" => 1,
           "recordType" => "account",
           "userId" => user_id,
           "displayUsername" => name,
           "normalizedUsername" => name,
           "roles" => roles,
           "passwordVerifier" => verifier,
           "createdAt" => now
         },
         index = %{
           "schemaVersion" => 1,
           "recordType" => "username-index",
           "normalizedUsername" => name,
           "userId" => user_id
         },
         {:ok, _account} <- IdentityStore.put_account(store, account),
         {:ok, _index} <- IdentityStore.put_username(store, index),
         {:ok, ^account} <- IdentityStore.read_account(store, user_id),
         {:ok, ^index} <- IdentityStore.read_username(store, name) do
      {:ok, user_id}
    else
      {:error, reason} -> facade_error(:identity, reason)
      _mismatch -> facade_error(:identity, :read_back_failed)
    end
  end

  # Family chat. A user message goes through the same entry point as the GraphQL resolver; a
  # system message through the internal system-sender entry point.

  defp write_messages(messages, users) do
    slug = FamilyChat.canonical_room_slug()

    Enum.reduce_while(messages, :ok, fn message, :ok ->
      case post_message(slug, message, users) do
        {:ok, _message} -> {:cont, :ok}
        {:error, reason} -> {:halt, facade_error(:family_chat, reason)}
      end
    end)
  end

  defp post_message(slug, %{"sender" => @system_sender} = message, _users) do
    FamilyChat.post_system_message(slug, message["idempotencyKey"], message["body"])
  end

  defp post_message(slug, message, users) do
    FamilyChat.send_message(
      user_id(users, message["sender"]),
      slug,
      message["idempotencyKey"],
      message["body"],
      message["sender"]
    )
  end

  defp write_subscriptions(subscriptions, users) do
    Enum.reduce_while(subscriptions, :ok, fn subscription, :ok ->
      input = Map.take(subscription, ~w(endpoint p256dh auth))
      owner = user_id(users, subscription["owner"])

      case PushNotifications.upsert_subscription(
             owner,
             push_session_key(input["endpoint"]),
             input
           ) do
        {:ok, _enabled} -> {:cont, :ok}
        {:error, reason} -> {:halt, facade_error(:push_notifications, reason)}
      end
    end)
  end

  # Records. Each kind is saved over the record its production reader returns, so its revision is
  # the one the store expects.

  defp write_records(records, users) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case write_record(record["kind"], user_id(users, record["owner"]), record["value"]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp write_record("sifatAllahProgress", user_id, value) do
    with {:ok, previous} <- previous_progress(user_id),
         {:ok, _record} <- SifatAllah.save_progress(user_id, value, previous) do
      :ok
    else
      {:error, reason} -> facade_error(:sifat_allah, reason)
    end
  end

  defp write_record("codexChatTranscript", user_id, value) do
    with {:ok, transcript} <- restore_transcript(value),
         {:ok, previous} <- previous_transcript(user_id),
         {:ok, _record} <- CodexChat.save_transcript(user_id, transcript, previous) do
      :ok
    else
      {:error, reason} when is_atom(reason) -> facade_error(:codex_chat, reason)
      _not_saved -> facade_error(:codex_chat, :not_saved)
    end
  end

  defp write_record("themePreference", user_id, %{"theme" => theme}) do
    case Preferences.put_theme(user_id, theme, DateTime.utc_now()) do
      :ok -> :ok
      {:error, reason} -> facade_error(:preferences, reason)
    end
  end

  # The steps `BnestApp.Storage.Import` takes before its read back fails: the pending manifest, the
  # envelope, then the manifest finished `retryable`. The import id and checksum come from
  # `Manifest.identity/4`, the same identity the production import derives, so a later browser
  # import of this payload resumes this manifest. Nothing reads the envelope back here.
  defp write_record(
         "browserImportInterrupted",
         user_id,
         %{"storageArea" => area, "storageKey" => key, "payload" => payload}
       ) do
    store = Records.store()
    now = Storage.now()
    pending = Manifest.new(user_id, area, key, payload, "pending", nil, now)
    import_id = pending["importId"]
    finished = Manifest.finished(pending, "retryable", :read_back_failed, now)

    with {:ok, _manifest} <- RecordBackend.put_new(store, :manifest, import_id, pending),
         {:ok, _envelope} <-
           RecordBackend.put_new(
             store,
             :browser_import,
             {user_id, import_id},
             envelope(user_id, area, key, payload, import_id, now)
           ),
         {:ok, _manifest} <- RecordBackend.replace(store, :manifest, import_id, finished) do
      :ok
    else
      {:error, reason} -> facade_error(:browser_import, reason)
    end
  end

  # The envelope `BnestApp.Storage.Import` preserves for a source, built the same way.
  defp envelope(user_id, area, key, payload, import_id, now) do
    {_id, checksum} = Manifest.identity(user_id, area, key, payload)

    %{
      "schemaVersion" => 1,
      "recordType" => "browser-import",
      "importId" => import_id,
      "ownerId" => user_id,
      "source" => %{
        "kind" => "browser-storage",
        "storageArea" => area,
        "storageKey" => key,
        "sourceSchemaVersion" => Normalizer.source_version(key, payload)
      },
      "payloadEncoding" => "utf8-string",
      "payload" => payload,
      "integrity" => %{"sha256" => checksum, "capturedAt" => now}
    }
  end

  defp previous_progress(user_id) do
    case SifatAllah.load_progress(user_id) do
      {:ok, record} -> {:ok, record}
      {:error, :missing} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp previous_transcript(user_id) do
    case CodexChat.load_transcript(user_id) do
      {:ok, _transcript, record} -> {:ok, record}
      {:error, :missing} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_transcript(value) do
    case Transcript.restore(value) do
      {:ok, transcript} -> {:ok, transcript}
      :error -> {:error, :invalid_transcript}
    end
  end

  defp user_id(users, username), do: users |> Map.fetch!(username) |> Map.fetch!(:user_id)

  # Facade failures keep only the reason atom or the production error code, never the input.

  defp facade_error(section, %{code: code}) when is_binary(code),
    do: {:error, {:facade, section, code}}

  defp facade_error(section, reason) when is_atom(reason),
    do: {:error, {:facade, section, reason}}

  defp facade_error(section, _reason), do: {:error, {:facade, section, :failed}}

  defp fingerprint(seed),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(canonical(seed)))

  # Maps are sorted by key, so the same body has the same fingerprint whatever the key order.
  defp canonical(%{} = map) do
    sorted = map |> Enum.map(fn {key, value} -> {key, canonical(value)} end) |> Enum.sort()
    {:map, sorted}
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(other), do: other
end
