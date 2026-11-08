defmodule BnestApp.TestInstance.SeedValidateTest do
  # Pure checks of a seed body (ADR 001, section 2). Every name, password and key is synthetic.
  use ExUnit.Case, async: true

  @moduletag :test_instance

  alias BnestApp.CodexChat.Domain.Transcript
  alias BnestApp.SifatAllah.Domain.Quiz
  alias BnestApp.TestInstance.Seed

  # The instance short id is the first eight characters of its id.
  @instance %{instance_id: "a1b2c3d4e5f6g7h8"}
  @admin "test-user-a1b2c3d4-admin"
  @parent "test-user-a1b2c3d4-parent"
  @password "Synthetic!Pass1"
  @key "3f2b8c1e-6d4a-4b7e-9a1f-0c2d3e4f5a6b"

  # Push subscriptions carry endpoint URLs, which the unit boundary policy refuses. Their checks live in
  # test/integration/bnest_app/test_instance/seed_push_validate_test.exs.

  defp account(name, roles \\ ["parents"]),
    do: %{"username" => name, "password" => @password, "roles" => roles}

  defp message(sender, key \\ @key, body \\ "Assalamu alaikum"),
    do: %{"sender" => sender, "body" => body, "idempotencyKey" => key}

  defp record(owner, kind, value), do: %{"owner" => owner, "kind" => kind, "value" => value}

  defp seeded(usernames) do
    Map.put(
      @instance,
      :seeded,
      Map.new(usernames, &{&1, %{user_id: "user-" <> &1, roles: ["parents"]}})
    )
  end

  defp rejected(seed, instance \\ @instance) do
    assert {:error, %{code: :seed_invalid} = error} = Seed.validate(seed, instance)
    error
  end

  # An interrupted import is a flat-primary kind: its store is the instance's own flat root.
  @chat_payload ~s({"version":2,"messages":[]})

  defp interrupted(value, owner \\ @parent),
    do: record(owner, "browserImportInterrupted", value)

  defp source(area, key, payload),
    do: %{"storageArea" => area, "storageKey" => key, "payload" => payload}

  defp flat_seeded, do: Map.merge(Map.put(@instance, :phase, :flat_primary), seeded([@parent]))

  describe "validate/2 accepts a valid seed" do
    test "returns every section in its normalized shape" do
      seed = %{
        "accounts" => [account(@admin, ["parents", "admin"]), account(@parent)],
        "familyChat" => %{
          "messages" => [message(@admin, @key, "  Salam  "), message("system", "slot-1")]
        },
        "records" => [record(@parent, "themePreference", %{"theme" => "dark"})]
      }

      assert {:ok, normalized} = Seed.validate(seed, @instance)

      assert normalized["accounts"] == [
               %{"username" => @admin, "password" => @password, "roles" => ["admin", "parents"]},
               %{"username" => @parent, "password" => @password, "roles" => ["parents"]}
             ]

      assert normalized["familyChat"] == %{
               "messages" => [
                 %{"sender" => @admin, "body" => "Salam", "idempotencyKey" => @key},
                 %{
                   "sender" => "system",
                   "body" => "Assalamu alaikum",
                   "idempotencyKey" => "slot-1"
                 }
               ]
             }

      assert normalized["records"] == [
               %{"owner" => @parent, "kind" => "themePreference", "value" => %{"theme" => "dark"}}
             ]
    end

    test "normalizes an empty seed to empty sections" do
      assert {:ok, normalized} = Seed.validate(%{}, @instance)

      assert normalized == %{
               "accounts" => [],
               "familyChat" => %{"messages" => []},
               "pushSubscriptions" => [],
               "records" => []
             }
    end

    test "accepts a seeded sender or owner that an earlier seed created" do
      instance = seeded([@admin])

      assert {:ok, _seed} =
               Seed.validate(
                 %{
                   "familyChat" => %{"messages" => [message(@admin)]},
                   "records" => [record(@admin, "themePreference", %{"theme" => "light"})]
                 },
                 instance
               )
    end

    test "accepts a short id that is one hyphen-separated segment of the name" do
      assert {:ok, _seed} =
               Seed.validate(%{"accounts" => [account("test-user-a1b2c3d4")]}, @instance)

      assert {:ok, _seed} =
               Seed.validate(%{"accounts" => [account("test-user-kid-a1b2c3d4-x")]}, @instance)
    end

    test "accepts a name of exactly 32 characters, the production username limit" do
      name = "test-user-a1b2c3d4-" <> String.duplicate("x", 13)
      assert byte_size(name) == 32
      assert {:ok, _seed} = Seed.validate(%{"accounts" => [account(name)]}, @instance)
    end
  end

  describe "invalid_username" do
    for {label, name} <- [
          {"an uppercase letter", "Test-User-a1b2c3d4"},
          {"no test-user- prefix", "admin-a1b2c3d4"},
          {"no instance short id", "test-user-x1y2z3w4"},
          {"a short id that is only part of a segment", "test-user-a1b2c3d4e5"},
          {"an underscore", "test-user-a1b2c3d4_x"},
          {"more than 32 characters in all", "test-user-a1b2c3d4-" <> String.duplicate("x", 30)},
          {"more than 48 characters after the prefix",
           "test-user-a1b2c3d4-" <> String.duplicate("a", 40)}
        ] do
      test "refuses a name with #{label} at accounts[0].username" do
        assert %{reason: :invalid_username, path: "accounts[0].username"} =
                 rejected(%{"accounts" => [account(unquote(name))]})
      end
    end

    test "names the field of the second account" do
      assert %{reason: :invalid_username, path: "accounts[1].username"} =
               rejected(%{"accounts" => [account(@admin), account("test-user-zzzz")]})
    end
  end

  describe "invalid_role" do
    for {label, roles} <- [
          {"a role outside the known set", ["owner"]},
          {"a repeated role", ["parents", "parents"]},
          {"an empty list", []}
        ] do
      test "refuses #{label} at accounts[0].roles" do
        assert %{reason: :invalid_role, path: "accounts[0].roles"} =
                 rejected(%{"accounts" => [account(@parent, unquote(roles))]})
      end
    end

    test "a roles value that is not a list is invalid_payload" do
      assert %{reason: :invalid_payload, path: "accounts[0].roles"} =
               rejected(%{"accounts" => [%{account(@parent) | "roles" => "parents"}]})
    end
  end

  describe "duplicate_username" do
    test "refuses a name that appears twice in one seed" do
      assert %{reason: :duplicate_username, path: "accounts[1].username"} =
               rejected(%{"accounts" => [account(@parent), account(@parent)]})
    end

    test "refuses a name that an earlier seed already created on the instance" do
      assert %{reason: :duplicate_username, path: "accounts[0].username"} =
               rejected(%{"accounts" => [account(@admin, ["admin"])]}, seeded([@admin]))
    end
  end

  describe "unknown senders, owners and seed keys" do
    test "a family chat sender that is neither system nor a seeded username is unknown_sender" do
      assert %{reason: :unknown_sender, path: "familyChat.messages[0].sender"} =
               rejected(%{"familyChat" => %{"messages" => [message("test-user-a1b2c3d4-ghost")]}})
    end

    test "system is always a valid sender" do
      assert {:ok, _seed} =
               Seed.validate(
                 %{"familyChat" => %{"messages" => [message("system", "slot-2")]}},
                 @instance
               )
    end

    test "a record owner that is not seeded is unknown_owner" do
      assert %{reason: :unknown_owner, path: "records[0].owner"} =
               rejected(%{
                 "records" => [record(@parent, "themePreference", %{"theme" => "dark"})]
               })
    end

    test "a seed key that is not a slug is unknown_seed_key at seedKey" do
      assert {:error, %{code: :seed_invalid, reason: :unknown_seed_key, path: "seedKey"}} =
               Seed.apply(@instance, "Not A Key!", %{})
    end

    test "a seed key that is empty is unknown_seed_key" do
      assert {:error, %{code: :seed_invalid, reason: :unknown_seed_key, path: "seedKey"}} =
               Seed.apply(@instance, "", %{})
    end
  end

  describe "too_many" do
    test "refuses 41 accounts in one seed at accounts" do
      accounts = for i <- 1..41, do: account("test-user-a1b2c3d4-u#{i}")

      assert %{reason: :too_many, path: "accounts"} = rejected(%{"accounts" => accounts})
    end

    test "counts the accounts an instance already holds" do
      existing = for i <- 1..25, do: "test-user-a1b2c3d4-e#{i}"
      accounts = for i <- 1..16, do: account("test-user-a1b2c3d4-n#{i}")

      assert %{reason: :too_many, path: "accounts"} =
               rejected(%{"accounts" => accounts}, seeded(existing))
    end

    test "accepts exactly 40 accounts" do
      accounts = for i <- 1..40, do: account("test-user-a1b2c3d4-u#{i}")

      assert {:ok, %{"accounts" => normalized}} =
               Seed.validate(%{"accounts" => accounts}, @instance)

      assert length(normalized) == 40
    end

    test "refuses 501 family chat messages at familyChat.messages" do
      messages = for i <- 1..501, do: message("system", "slot-#{i}")

      assert %{reason: :too_many, path: "familyChat.messages"} =
               rejected(%{"familyChat" => %{"messages" => messages}})
    end

    test "accepts exactly 500 family chat messages" do
      messages = for i <- 1..500, do: message("system", "slot-#{i}")

      assert {:ok, %{"familyChat" => %{"messages" => normalized}}} =
               Seed.validate(%{"familyChat" => %{"messages" => messages}}, @instance)

      assert length(normalized) == 500
    end

    test "refuses 41 records at records" do
      records = for i <- 1..41, do: record(@parent, "themePreference", %{"theme" => "light#{i}"})

      assert %{reason: :too_many, path: "records"} =
               rejected(%{"records" => records}, seeded([@parent]))
    end
  end

  describe "invalid_payload" do
    test "a seed that is not an object is refused at seed" do
      assert %{reason: :invalid_payload, path: "seed"} = rejected([])
    end

    test "an unknown top-level key is refused by its name" do
      assert %{reason: :invalid_payload, path: "bogus"} = rejected(%{"bogus" => []})
    end

    test "accounts that are not a list are refused at accounts" do
      assert %{reason: :invalid_payload, path: "accounts"} = rejected(%{"accounts" => %{}})
    end

    test "an account with an unknown key is refused at that key" do
      seed = %{"accounts" => [Map.put(account(@parent), "email", "test-user@example.invalid")]}

      assert %{reason: :invalid_payload, path: "accounts[0].email"} = rejected(seed)
    end

    test "an account without a password is refused at its password" do
      seed = %{"accounts" => [Map.delete(account(@parent), "password")]}

      assert %{reason: :invalid_payload, path: "accounts[0].password"} = rejected(seed)
    end

    test "a password that is not a valid password is refused at its password" do
      seed = %{"accounts" => [%{account(@parent) | "password" => "letters only"}]}

      assert %{reason: :invalid_payload, path: "accounts[0].password"} = rejected(seed)
    end

    test "a password that is not a string is refused at its password" do
      seed = %{"accounts" => [%{account(@parent) | "password" => 123_456}]}

      assert %{reason: :invalid_payload, path: "accounts[0].password"} = rejected(seed)
    end

    test "a familyChat that is not an object is refused at familyChat" do
      assert %{reason: :invalid_payload, path: "familyChat"} = rejected(%{"familyChat" => []})
    end

    test "a familyChat with an unknown key is refused at that key" do
      assert %{reason: :invalid_payload, path: "familyChat.rooms"} =
               rejected(%{"familyChat" => %{"rooms" => []}})
    end

    test "a message without a body is refused at its body" do
      seed = %{"familyChat" => %{"messages" => [Map.delete(message("system", "slot-1"), "body")]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].body"} = rejected(seed)
    end

    test "a blank message body is refused at its body" do
      seed = %{"familyChat" => %{"messages" => [message("system", "slot-1", "   ")]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].body"} = rejected(seed)
    end

    test "a sender that is not a string is refused at its sender" do
      seed = %{"familyChat" => %{"messages" => [%{message("system") | "sender" => 7}]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].sender"} = rejected(seed)
    end

    test "a user message whose key is not a client message id is refused at its key" do
      seed = %{"familyChat" => %{"messages" => [message(@admin, "not-a-uuid")]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].idempotencyKey"} =
               rejected(seed, seeded([@admin]))
    end

    test "a system key that is empty is refused at its key" do
      seed = %{"familyChat" => %{"messages" => [message("system", "")]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].idempotencyKey"} =
               rejected(seed)
    end

    test "the same sender and key twice in one seed is refused at the second key" do
      seed = %{
        "familyChat" => %{
          "messages" => [message("system", "slot-1"), message("system", "slot-1")]
        }
      }

      assert %{reason: :invalid_payload, path: "familyChat.messages[1].idempotencyKey"} =
               rejected(seed)
    end

    test "a record kind outside the three known kinds is refused at its kind" do
      seed = %{"records" => [record(@parent, "sifatAllahLegacy", %{})]}

      assert %{reason: :invalid_payload, path: "records[0].kind"} =
               rejected(seed, seeded([@parent]))
    end

    test "a second record of one kind for one owner is refused at the record" do
      seed = %{
        "records" => [
          record(@parent, "themePreference", %{"theme" => "dark"}),
          record(@parent, "themePreference", %{"theme" => "light"})
        ]
      }

      assert %{reason: :invalid_payload, path: "records[1]"} = rejected(seed, seeded([@parent]))
    end

    test "a theme outside the chooseable themes is refused at the theme" do
      seed = %{"records" => [record(@parent, "themePreference", %{"theme" => "purple"})]}

      assert %{reason: :invalid_payload, path: "records[0].value.theme"} =
               rejected(seed, seeded([@parent]))
    end

    test "a theme record with an unknown key is refused at that key" do
      seed = %{"records" => [record(@parent, "themePreference", %{"theme" => "dark", "x" => 1})]}

      assert %{reason: :invalid_payload, path: "records[0].value.x"} =
               rejected(seed, seeded([@parent]))
    end

    test "a sifat progress value that is not a progress snapshot is refused at the value" do
      seed = %{"records" => [record(@parent, "sifatAllahProgress", %{"version" => 9})]}

      assert %{reason: :invalid_payload, path: "records[0].value"} =
               rejected(seed, seeded([@parent]))
    end

    test "a sifat progress value with a session that is not an object is refused at the value" do
      progress = Quiz.progress()

      seed = %{
        "records" => [record(@parent, "sifatAllahProgress", Map.put(progress, "session", "x"))]
      }

      assert %{reason: :invalid_payload, path: "records[0].value"} =
               rejected(seed, seeded([@parent]))
    end

    test "a codex transcript value that is not a transcript snapshot is refused at the value" do
      seed = %{"records" => [record(@parent, "codexChatTranscript", %{"version" => 4})]}

      assert %{reason: :invalid_payload, path: "records[0].value"} =
               rejected(seed, seeded([@parent]))
    end

    test "a codex transcript value that is a valid snapshot is accepted" do
      {:ok, snapshot} = Transcript.snapshot(Transcript.new())
      seed = %{"records" => [record(@parent, "codexChatTranscript", snapshot)]}

      assert {:ok, _seed} = Seed.validate(seed, seeded([@parent]))
    end
  end

  describe "refusals at the shape and value level" do
    test "a top-level key that is not a string is invalid_payload at seed" do
      assert %{reason: :invalid_payload, path: "seed"} = rejected(%{accounts: []})
    end

    test "an item that is not an object is invalid_payload at its position" do
      assert %{reason: :invalid_payload, path: "accounts[0]"} =
               rejected(%{"accounts" => ["test-user-a1b2c3d4-admin"]})
    end

    test "an item with a non-string key is invalid_payload at its position" do
      seed = %{"accounts" => [Map.put(account(@parent), :extra, 1)]}

      assert %{reason: :invalid_payload, path: "accounts[0]"} = rejected(seed)
    end

    test "a family chat body that is not a string is invalid_payload at its field" do
      seed = %{"familyChat" => %{"messages" => [message("system", "slot-1", 5)]}}

      assert %{reason: :invalid_payload, path: "familyChat.messages[0].body"} = rejected(seed)
    end

    test "a sifat progress value that is not an object is invalid_payload at the value" do
      seed = %{"records" => [record(@parent, "sifatAllahProgress", "not progress")]}

      assert %{reason: :invalid_payload, path: "records[0].value"} =
               rejected(seed, seeded([@parent]))
    end
  end

  describe "browserImportInterrupted" do
    test "accepts an interrupted import of a recognized source and keeps its three fields" do
      value = source("sessionStorage", "bnest.chat.v1", @chat_payload)

      assert {:ok, %{"records" => [record]}} =
               Seed.validate(%{"records" => [interrupted(value)]}, flat_seeded())

      assert record == %{
               "owner" => @parent,
               "kind" => "browserImportInterrupted",
               "value" => value
             }
    end

    test "is refused on a sqlite_primary instance at its kind, because its store is the run base" do
      value = source("sessionStorage", "bnest.chat.v1", @chat_payload)
      sqlite = Map.put(seeded([@parent]), :phase, :sqlite_primary)

      assert %{reason: :wrong_phase, path: "records[0].kind"} =
               rejected(%{"records" => [interrupted(value)]}, sqlite)
    end

    test "refuses a source pair the production import does not recognize, at the key" do
      for {area, key} <- [
            {"localStorage", "bnest.chat.v1"},
            {"sessionStorage", "phx:theme"},
            {"sessionStorage", "bnest.sifat-allah.v1"},
            {"sessionStorage", "unrelated"}
          ] do
        assert %{reason: :unsupported_source, path: "records[0].value.storageKey"} =
                 rejected(%{"records" => [interrupted(source(area, key, "{}"))]}, flat_seeded())
      end
    end

    test "accepts a payload of exactly the source's limit and refuses one byte more" do
      for {key, area, limit} <- [
            {"bnest.chat.v1", "sessionStorage", 500_000},
            {"bnest.sifat-allah.v1", "localStorage", 10_000},
            {"phx:theme", "localStorage", 16}
          ] do
        at_limit = source(area, key, String.duplicate("a", limit))
        over = source(area, key, String.duplicate("a", limit + 1))

        assert {:ok, _seed} =
                 Seed.validate(%{"records" => [interrupted(at_limit)]}, flat_seeded())

        assert %{reason: :oversized, path: "records[0].value.payload"} =
                 rejected(%{"records" => [interrupted(over)]}, flat_seeded())
      end
    end

    test "refuses a payload that is not a string at the payload" do
      value = source("sessionStorage", "bnest.chat.v1", %{"version" => 2})

      assert %{reason: :invalid_payload, path: "records[0].value.payload"} =
               rejected(%{"records" => [interrupted(value)]}, flat_seeded())
    end

    test "refuses a value without its payload at the missing field" do
      value = Map.delete(source("sessionStorage", "bnest.chat.v1", "{}"), "payload")

      assert %{reason: :invalid_payload, path: "records[0].value.payload"} =
               rejected(%{"records" => [interrupted(value)]}, flat_seeded())
    end

    test "refuses a value with a key outside its three fields at that key" do
      value = Map.put(source("sessionStorage", "bnest.chat.v1", "{}"), "owner", "x")

      assert %{reason: :invalid_payload, path: "records[0].value.owner"} =
               rejected(%{"records" => [interrupted(value)]}, flat_seeded())
    end

    test "refuses a value that is not an object at the value" do
      assert %{reason: :invalid_payload, path: "records[0].value"} =
               rejected(%{"records" => [interrupted("{}")]}, flat_seeded())
    end

    test "refuses an owner that the instance does not hold" do
      value = source("sessionStorage", "bnest.chat.v1", "{}")

      assert %{reason: :unknown_owner, path: "records[0].owner"} =
               rejected(%{"records" => [interrupted(value, @admin)]}, flat_seeded())
    end
  end

  describe "errors never echo a secret" do
    test "a refused password is not in the error" do
      secret = "Secret-Probe-9!"

      seed = %{
        "accounts" => [%{"username" => @admin, "password" => secret, "roles" => ["owner"]}]
      }

      error = rejected(seed)

      assert error.reason == :invalid_role
      refute inspect(error) =~ secret
    end
  end

  test "a seed that is not an object is refused by apply before any state is read" do
    assert {:error, %{code: :seed_invalid, reason: :invalid_payload, path: "seed"}} =
             Seed.apply(@instance, "bootstrap-a", [])
  end

  describe "apply/3 refusals that need no facade" do
    test "a seed key that is not a slug is unknown_seed_key at seedKey" do
      assert {:error, %{code: :seed_invalid, reason: :unknown_seed_key, path: "seedKey"}} =
               Seed.apply(@instance, "Not A Slug", %{})

      assert {:error, %{reason: :unknown_seed_key}} = Seed.apply(@instance, 7, %{})
    end

    test "a valid body on an instance that is not current is :not_current and writes nothing" do
      assert {:error, :not_current} = Seed.apply(@instance, "bootstrap-a", %{})
    end
  end
end
