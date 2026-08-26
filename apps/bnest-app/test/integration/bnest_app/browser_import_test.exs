defmodule BnestApp.BrowserImportTest do
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.DataRepository
  alias BnestApp.DataRepository.Import
  alias BnestApp.DataRepository.RecoverySource
  alias BnestApp.DataRepository.Store

  test "preserves and accepts each recognized browser source" do
    store = DataRepository.store()
    owner_id = owner_id(store)

    assert {:ok, chat} = Import.browser(store, owner_id, chat_source())
    assert {:ok, learning} = Import.browser(store, owner_id, learning_source())
    assert {:ok, theme} = Import.browser(store, owner_id, theme_source())

    for result <- [chat, learning, theme] do
      assert result.status == :accepted

      assert {:ok, envelope} =
               Store.read(store, :browser_import, {owner_id, result.import_id})

      assert envelope["ownerId"] == owner_id
      assert {:ok, %{"status" => "accepted"}} = Store.read(store, :manifest, result.import_id)
    end

    assert {:ok, %{"recordType" => "chat"}} = Store.read(store, :chat, owner_id)

    assert {:ok, %{"recordType" => "sifat-allah-progress"}} =
             Store.read(store, :sifat_allah, owner_id)

    assert {:ok, %{"theme" => "dark"}} = Store.read(store, :theme, owner_id)
  end

  test "reuses an accepted import identity without duplicating its envelope" do
    store = DataRepository.store()
    owner_id = owner_id(store)
    source = chat_source()
    import_directory = Path.join([store.root, "users", owner_id, "imports"])
    before_count = length(Path.wildcard(Path.join(import_directory, "*.json")))

    assert {:ok, first} = Import.browser(store, owner_id, source)
    after_first_count = length(Path.wildcard(Path.join(import_directory, "*.json")))
    assert {:ok, second} = Import.browser(store, owner_id, source)
    assert first.import_id == second.import_id

    assert after_first_count in [before_count, before_count + 1]
    assert length(Path.wildcard(Path.join(import_directory, "*.json"))) == after_first_count
  end

  test "rejects malformed and oversized sources without replacing accepted data" do
    store = DataRepository.store()
    owner_id = owner_id(store)
    assert {:ok, accepted} = Import.browser(store, owner_id, chat_source())
    assert {:ok, before} = Store.read(store, :chat, owner_id)

    malformed = Map.put(chat_source(), "payload", "{not-json")

    assert {:error, :malformed, %{"status" => "rejected"}} =
             Import.browser(store, owner_id, malformed)

    oversized = Map.put(chat_source(), "payload", String.duplicate("x", 500_001))

    assert {:error, :oversized, %{"status" => "rejected"}} =
             Import.browser(store, owner_id, oversized)

    assert {:ok, ^before} = Store.read(store, :chat, owner_id)

    assert {:ok, _envelope} =
             Store.read(store, :browser_import, {owner_id, accepted.import_id})
  end

  test "rejects an unrecognized client-selected source before writing an envelope" do
    store = DataRepository.store()
    owner_id = owner_id(store)

    assert {:error, :unsupported_source, %{"status" => "rejected"}} =
             Import.browser(store, owner_id, %{
               "storageArea" => "localStorage",
               "storageKey" => "private.other",
               "payload" => "value"
             })
  end

  test "keeps a newer accepted record when another browser presents a different legacy source" do
    store = DataRepository.store()
    owner_id = owner_id(store)
    assert {:ok, _accepted} = Import.browser(store, owner_id, chat_source())
    assert {:ok, before} = Store.read(store, :chat, owner_id)

    stale_payload =
      chat_source()["payload"]
      |> Jason.decode!()
      |> Map.put("reasoning_effort", "high")
      |> Jason.encode!()

    stale_source = Map.put(chat_source(), "payload", stale_payload)

    assert {:error, :stale_revision, %{"status" => "retryable"}} =
             Import.browser(store, owner_id, stale_source)

    assert {:ok, ^before} = Store.read(store, :chat, owner_id)
  end

  test "records absent system theme without creating a preference" do
    store = DataRepository.store()
    owner_id = owner_id(store)
    before = Store.read(store, :theme, owner_id)

    assert {:ok, %{status: :accepted, cleanup: %{"storageKey" => nil}}} =
             Import.absent_theme(store, owner_id)

    assert Store.read(store, :theme, owner_id) == before
  end

  test "rehearses browser restore from the verified immutable envelope" do
    store = DataRepository.store()
    owner_id = owner_id(store)
    assert {:ok, accepted} = Import.browser(store, owner_id, learning_source())

    assert {:ok, :sifat_allah, candidate} =
             RecoverySource.normalize_browser(store, owner_id, accepted.import_id)

    assert candidate["recordType"] == "sifat-allah-progress"
    assert candidate["sourceImportId"] == accepted.import_id
    assert candidate["progress"] == BnestApp.SifatAllah.progress()
  end

  defp chat_source do
    %{
      "storageArea" => "sessionStorage",
      "storageKey" => "bnest.chat.v1",
      "payload" =>
        Jason.encode!(%{
          "version" => 2,
          "thread_id" => nil,
          "model" => "fixture-model",
          "reasoning_effort" => "medium",
          "messages" => []
        })
    }
  end

  defp learning_source do
    %{
      "storageArea" => "localStorage",
      "storageKey" => "bnest.sifat-allah.v1",
      "payload" =>
        Jason.encode!(
          BnestApp.SifatAllah.progress()
          |> Map.put("session", %{"mode" => "dashboard"})
        )
    }
  end

  defp theme_source do
    %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "payload" => "dark"}
  end

  defp owner_id(store) do
    {:ok, %{"userId" => owner_id}} =
      Store.read(store, :username_index, "test-user-integration")

    owner_id
  end
end
