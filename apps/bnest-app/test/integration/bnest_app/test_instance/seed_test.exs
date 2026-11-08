defmodule BnestApp.TestInstance.SeedTest do
  # Seeds a really spawned instance through the production facades (ADR 001, section 2). Every
  # identity, password, message and key below is synthetic; nothing is read from production data.
  #
  # Setup and bootstrap run on a `flat_primary` instance. Production's identity emptiness check
  # (`RecordIdentityStore.empty?/1`) never claims a routed SQLite repository is empty, so an
  # `sqlite_primary` instance cannot open or bootstrap `/setup`. The `sqlite_primary` tests below
  # pin that production behaviour; they are the evidence for the blocker in the T7 report.
  use ExUnit.Case, async: false

  @moduletag :test_instance

  import Phoenix.ConnTest

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.FamilyChat
  alias BnestApp.Identity
  alias BnestApp.Preferences
  alias BnestApp.PushNotifications
  alias BnestApp.SifatAllah
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Records
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Error
  alias BnestApp.TestInstance.Seed

  @endpoint BnestAppWeb.Endpoint
  @room "ruang-keluarga"
  @password "Synthetic!Pass1"
  @other_password "Synthetic!Pass2"
  @first_id "5e6f7a8b9c0d1e2f"
  @second_id "9a8b7c6d5e4f3a2b"

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil

    # The backup configuration is one fixed file in the run base; every spawn and drop removes it.
    File.rm(backup_config_path(run))

    on_exit(fn ->
      case TestInstance.state() do
        nil -> :ok
        instance -> TestInstance.drop!(instance)
      end

      File.rm(backup_config_path(run))
    end)

    %{run: run}
  end

  describe "accounts on a flat_primary instance" do
    test "an admin seed closes setup, and its accounts log in through the identity API", %{
      run: run
    } do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, parent} = names(@first_id)

      assert {:ok, %{applied: true, accounts: accounts}} =
               Seed.apply(instance, "admins", account_seed(@first_id))

      assert [
               %{username: ^admin, user_id: admin_id, roles: ["admin", "parents"]},
               %{username: ^parent, user_id: parent_id, roles: ["parents"]}
             ] = accounts

      assert Identity.setup_status() == :closed
      assert build_conn() |> get("/setup") |> response(404)

      assert {:ok, token} = Identity.login(admin, @password)
      assert is_binary(token)
      assert {:ok, _token} = Identity.login(parent, @password)
      assert {:error, :invalid_credentials} = Identity.login(parent, @other_password)

      assert {:ok, %{"userId" => ^admin_id, "roles" => ["admin", "parents"]}} =
               Identity.account(admin_id)

      assert {:ok, %{"userId" => ^parent_id}} = Identity.account(parent_id)

      assert :ok = TestInstance.drop!(instance)
    end

    test "an empty spawn leaves setup open", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)

      assert Identity.setup_status() == :open
      assert build_conn() |> get("/setup") |> response(200)

      assert :ok = TestInstance.drop!(instance)
    end

    test "a seed with accounts but no admin leaves setup unopened, and its accounts log in", %{
      run: run
    } do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {_admin, parent} = names(@first_id)

      assert {:ok, %{applied: true}} =
               Seed.apply(instance, "parents", %{"accounts" => [parent_account(@first_id)]})

      # Production reads accounts without a bootstrap journal as a conflict, never as open.
      assert Identity.setup_status() == {:error, :conflict}
      assert build_conn() |> get("/setup") |> response(404)
      assert {:ok, _token} = Identity.login(parent, @password)

      assert :ok = TestInstance.drop!(instance)
    end

    test "accounts seeded after the first admin set go through the identity store", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, _parent} = names(@first_id)
      late = "test-user-#{short_id(@first_id)}-late"

      assert {:ok, %{applied: true}} = Seed.apply(instance, "admins", account_seed(@first_id))

      late_seed = %{
        "accounts" => [%{"username" => late, "password" => @password, "roles" => ["children"]}]
      }

      assert {:ok, %{applied: true, accounts: [%{username: ^late, user_id: late_id}]}} =
               Seed.apply(instance, "children", late_seed)

      assert Identity.setup_status() == :closed
      assert {:ok, _token} = Identity.login(late, @password)
      assert {:ok, %{"userId" => ^late_id, "roles" => ["children"]}} = Identity.account(late_id)
      assert {:ok, _token} = Identity.login(admin, @password)

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "accounts on the default sqlite_primary instance" do
    test "an empty spawn reports a setup conflict, not open", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id)

      assert instance.paths.db_file |> File.regular?()
      assert Identity.setup_status() == {:error, :conflict}
      assert build_conn() |> get("/setup") |> response(404)

      assert :ok = TestInstance.drop!(instance)
    end

    test "an admin seed is refused by production bootstrap, and the spawn rolls back", %{run: run} do
      before = snapshot()

      error =
        assert_raise Error, fn ->
          TestInstance.spawn!(run,
            instance_id: @first_id,
            seed: {"spawn", account_seed(@first_id)}
          )
        end

      assert error.reason == :spawn_failed
      assert error.step == :seed
      assert error.detail == {:facade, :identity, :conflict}
      assert_rolled_back(before)
    end

    test "accounts seeded without an admin are created through the identity store and log in", %{
      run: run
    } do
      instance = TestInstance.spawn!(run, instance_id: @first_id)
      {_admin, parent} = names(@first_id)

      assert {:ok, %{applied: true, accounts: [%{username: ^parent, user_id: user_id}]}} =
               Seed.apply(instance, "parents", %{"accounts" => [parent_account(@first_id)]})

      assert {:ok, _token} = Identity.login(parent, @password)
      assert {:ok, %{"userId" => ^user_id}} = Identity.account(user_id)

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "family chat" do
    test "users and the system read back in order through the production read path", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, parent} = names(@first_id)
      assert {:ok, %{applied: true}} = Seed.apply(instance, "accounts", account_seed(@first_id))

      messages = [
        message(admin, uuid(1), "Salam semua"),
        message("system", "slot-1", "Pengingat: doa malam"),
        message(parent, uuid(2), "Wa alaikum salam")
      ]

      assert {:ok, %{applied: true}} =
               Seed.apply(instance, "chat", %{"familyChat" => %{"messages" => messages}})

      assert {:ok, %{nodes: nodes}} = FamilyChat.list_messages(user_id(parent), @room, limit: 50)

      assert Enum.map(nodes, & &1.body) == [
               "Salam semua",
               "Pengingat: doa malam",
               "Wa alaikum salam"
             ]

      assert Enum.map(nodes, & &1.sender_kind) == ["user", "system", "user"]
      assert Enum.map(nodes, & &1.sender_display_name) == [admin, "System", parent]

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "push subscriptions" do
    test "a subscription is stored for its owner and reads as enabled", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, parent} = names(@first_id)
      endpoint = "https://push.allowed.example.com/seed-sub-1"

      assert {:ok, %{applied: true}} =
               Seed.apply(instance, "push", %{
                 "accounts" => accounts(@first_id),
                 "pushSubscriptions" => [subscription(parent, endpoint)]
               })

      session_key = Seed.push_session_key(endpoint)

      assert {:ok, %{enabled: true, expiration_time: nil}} =
               PushNotifications.current_subscription(user_id(parent), session_key)

      assert {:ok, %{enabled: false}} =
               PushNotifications.current_subscription(user_id(admin), session_key)

      assert :ok = TestInstance.drop!(instance)
    end

    test "two subscriptions of one owner both stay active", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {_admin, parent} = names(@first_id)
      first = "https://push.allowed.example.com/seed-sub-1"
      second = "https://push.allowed.example.com/seed-sub-2"

      assert {:ok, %{applied: true}} =
               Seed.apply(instance, "push", %{
                 "accounts" => accounts(@first_id),
                 "pushSubscriptions" => [
                   subscription(parent, first),
                   subscription(parent, second)
                 ]
               })

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(
                 user_id(parent),
                 Seed.push_session_key(first)
               )

      assert {:ok, %{enabled: true}} =
               PushNotifications.current_subscription(
                 user_id(parent),
                 Seed.push_session_key(second)
               )

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "records" do
    test "each record kind reads back through its production reader", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, parent} = names(@first_id)
      {:ok, snapshot} = transcript_snapshot("Salam")
      progress = Map.put(Quiz.progress(), "session", %{"mode" => "dashboard"})

      seed = %{
        "accounts" => accounts(@first_id),
        "records" => [
          %{"owner" => parent, "kind" => "sifatAllahProgress", "value" => progress},
          %{"owner" => parent, "kind" => "codexChatTranscript", "value" => snapshot},
          %{"owner" => admin, "kind" => "themePreference", "value" => %{"theme" => "dark"}}
        ]
      }

      assert {:ok, %{applied: true}} = Seed.apply(instance, "records", seed)

      parent_id = user_id(parent)

      assert {:ok, %{"ownerId" => ^parent_id, "progress" => stored, "session" => session}} =
               SifatAllah.load_progress(parent_id)

      assert session == %{"mode" => "dashboard"}
      assert {:ok, _restored} = Quiz.restore(stored)

      assert {:ok, restored, %{"ownerId" => ^parent_id}} = CodexChat.load_transcript(parent_id)
      # The snapshot keeps the visitor prompt first; the empty assistant placeholder follows it.
      assert [%{role: :visitor, content: "Salam"} | _] = restored.messages

      assert Preferences.theme(user_id(admin)) == "dark"

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "idempotency" do
    test "the same key and body applies once and reports applied false", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {_admin, parent} = names(@first_id)
      seed = full_seed(@first_id)

      assert {:ok, %{applied: true, accounts: accounts}} = Seed.apply(instance, "full", seed)
      parent_id = user_id(parent)
      messages = message_count(parent_id)
      {:ok, %{"revision" => revision}} = SifatAllah.load_progress(parent_id)

      assert {:ok, %{applied: false, accounts: ^accounts}} = Seed.apply(instance, "full", seed)

      assert message_count(parent_id) == messages
      assert {:ok, %{"revision" => ^revision}} = SifatAllah.load_progress(parent_id)
      assert {:ok, _token} = Identity.login(parent, @password)

      assert :ok = TestInstance.drop!(instance)
    end

    test "the same key with a different body is a conflict that changes nothing", %{run: run} do
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {_admin, parent} = names(@first_id)
      assert {:ok, %{applied: true}} = Seed.apply(instance, "full", full_seed(@first_id))
      messages = message_count(user_id(parent))

      other = %{"familyChat" => %{"messages" => [message("system", "slot-9", "Lain")]}}

      assert {:error, :seed_conflict} = Seed.apply(instance, "full", other)
      assert message_count(user_id(parent)) == messages

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "spawn with a seed" do
    test "the seed runs after migration, and a later apply of its key sees it", %{run: run} do
      seed = account_seed(@first_id)

      instance =
        TestInstance.spawn!(run,
          instance_id: @first_id,
          phase: :flat_primary,
          seed: {"spawn", seed}
        )

      {admin, _parent} = names(@first_id)
      assert Identity.setup_status() == :closed
      assert {:ok, _token} = Identity.login(admin, @password)
      assert {:ok, %{applied: false}} = Seed.apply(instance, "spawn", seed)

      assert :ok = TestInstance.drop!(instance)
    end

    test "a seed that fails validation rolls the whole spawn back at step seed", %{run: run} do
      before = snapshot()

      bad = %{
        "accounts" => [
          %{"username" => "test-user-zz", "password" => @password, "roles" => ["admin"]}
        ]
      }

      error =
        assert_raise Error, fn ->
          TestInstance.spawn!(run, instance_id: @first_id, seed: {"spawn", bad})
        end

      assert error.reason == :spawn_failed
      assert error.step == :seed

      assert error.detail == %{
               code: :seed_invalid,
               reason: :invalid_username,
               path: "accounts[0].username"
             }

      assert_rolled_back(before)
    end

    test "a seed whose writes are followed by a forced failure leaves no account behind", %{
      run: run
    } do
      before = snapshot()

      error =
        assert_raise Error, fn ->
          TestInstance.spawn!(run,
            instance_id: @first_id,
            phase: :flat_primary,
            seed: {"spawn", account_seed(@first_id)},
            fail_after: :seed
          )
        end

      assert error.reason == :spawn_failed
      assert error.step == :seed
      assert_rolled_back(before)

      # A new instance with the same id starts with setup open and none of the failed accounts.
      instance = TestInstance.spawn!(run, instance_id: @first_id, phase: :flat_primary)
      {admin, _parent} = names(@first_id)

      assert Identity.setup_status() == :open
      assert {:error, :invalid_credentials} = Identity.login(admin, @password)

      assert :ok = TestInstance.drop!(instance)
    end
  end

  describe "isolation" do
    test "a second instance does not see the accounts of the first", %{run: run} do
      first =
        TestInstance.spawn!(run,
          instance_id: @first_id,
          phase: :flat_primary,
          seed: {"spawn", account_seed(@first_id)}
        )

      {admin, parent} = names(@first_id)
      assert {:ok, _token} = Identity.login(admin, @password)
      assert :ok = TestInstance.drop!(first)

      second = TestInstance.spawn!(run, instance_id: @second_id, phase: :flat_primary)

      assert Identity.setup_status() == :open
      assert {:error, :invalid_credentials} = Identity.login(admin, @password)
      assert {:error, :invalid_credentials} = Identity.login(parent, @password)

      assert :ok = TestInstance.drop!(second)
    end
  end

  # Helpers. Usernames carry the instance short id, so each helper takes the instance id.

  defp short_id(instance_id), do: String.slice(instance_id, 0, 8)

  defp names(instance_id) do
    short = short_id(instance_id)
    {"test-user-#{short}-admin", "test-user-#{short}-parent"}
  end

  # The production login and session read give the user id, so no helper reads storage.
  defp user_id(username) do
    assert {:ok, token} = Identity.login(username, @password)
    assert {:ok, %{"userId" => user_id}} = Identity.current_user(token)
    user_id
  end

  defp accounts(instance_id), do: [admin_account(instance_id), parent_account(instance_id)]

  defp account_seed(instance_id), do: %{"accounts" => accounts(instance_id)}

  defp admin_account(instance_id) do
    {admin, _parent} = names(instance_id)
    %{"username" => admin, "password" => @password, "roles" => ["admin", "parents"]}
  end

  defp parent_account(instance_id) do
    {_admin, parent} = names(instance_id)
    %{"username" => parent, "password" => @password, "roles" => ["parents"]}
  end

  defp message(sender, key, body),
    do: %{"sender" => sender, "body" => body, "idempotencyKey" => key}

  defp subscription(owner, endpoint),
    do: %{"owner" => owner, "endpoint" => endpoint, "p256dh" => "BBBB", "auth" => "AAAA"}

  defp transcript_snapshot(prompt) do
    {:ok, transcript} = Transcript.submit(Transcript.new(), prompt)
    Transcript.snapshot(transcript)
  end

  defp full_seed(instance_id) do
    {admin, parent} = names(instance_id)
    {:ok, snapshot} = transcript_snapshot("Salam")

    %{
      "accounts" => accounts(instance_id),
      "familyChat" => %{
        "messages" => [message(admin, uuid(1), "Salam semua"), message("system", "slot-1", "Doa")]
      },
      "pushSubscriptions" => [subscription(parent, "https://push.allowed.example.com/full-1")],
      "records" => [
        %{"owner" => parent, "kind" => "sifatAllahProgress", "value" => Quiz.progress()},
        %{"owner" => parent, "kind" => "codexChatTranscript", "value" => snapshot},
        %{"owner" => admin, "kind" => "themePreference", "value" => %{"theme" => "light"}}
      ]
    }
  end

  defp message_count(user_id) do
    assert {:ok, %{nodes: nodes}} = FamilyChat.list_messages(user_id, @room, limit: 50)
    length(nodes)
  end

  defp uuid(n),
    do: "0b6c1d2e-3f4a-4b5c-8d6e-7f80910000" <> String.pad_leading(Integer.to_string(n), 2, "0")

  defp backup_config_path(run), do: Path.join([run.sqlite_path, "storage-config", "backup.json"])

  defp assert_rolled_back(before) do
    assert TestInstance.state() == nil
    assert snapshot() == before
    assert Process.whereis(SqliteRepo) == nil
  end

  defp snapshot do
    run = TestInstance.application_run!()

    %{
      audit: TestInstance.audit(),
      pointer: pointer_bytes(),
      runtime_root: Application.fetch_env(:bnest_app, :runtime_root),
      backup_repository_root: Application.fetch_env(:bnest_app, :backup_repository_root),
      family_chat_sqlite_path: Application.fetch_env(:bnest_app, :family_chat_sqlite_path),
      backup_config_present: File.exists?(backup_config_path(run)),
      records_store: :sys.get_state(Records).store
    }
  end

  defp pointer_bytes do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
    end
  end
end
