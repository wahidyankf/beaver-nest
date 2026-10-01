defmodule BnestApp.Storage.NormalizerTest do
  use ExUnit.Case, async: true

  alias BnestApp.SifatAllah
  alias BnestApp.Storage
  alias BnestApp.Storage.Domain.Normalizer

  @now "2026-09-01T00:00:00Z"

  test "normalizes each allow-listed browser source without accepting client ownership" do
    import_id = "import-unit-normalizer"

    chat_payload =
      Jason.encode!(%{
        "version" => 2,
        "thread_id" => nil,
        "model" => "fixture-model",
        "reasoning_effort" => "medium",
        "messages" => []
      })

    assert {:ok, :chat, chat} =
             normalize("sessionStorage", "bnest.chat.v1", chat_payload, import_id)

    assert chat["sourceImportId"] == import_id
    refute Map.has_key?(chat, "ownerId")

    learning_payload =
      SifatAllah.progress()
      |> Map.put("session", %{"mode" => "dashboard"})
      |> Jason.encode!()

    assert {:ok, :sifat_allah, learning} =
             normalize(
               "localStorage",
               "bnest.sifat-allah.v1",
               learning_payload,
               import_id
             )

    assert learning["session"] == %{"mode" => "dashboard"}
    refute Map.has_key?(learning, "ownerId")

    assert {:ok, :theme, %{"theme" => "dark", "sourceImportId" => ^import_id}} =
             normalize("localStorage", "phx:theme", "dark", import_id)
  end

  test "uses a safe dashboard session when legacy learning session data is invalid" do
    payload =
      SifatAllah.progress()
      |> Map.put("session", %{"mode" => "unknown", "private" => "discard-me"})
      |> Jason.encode!()

    assert {:ok, :sifat_allah, %{"session" => %{"mode" => "dashboard"}}} =
             normalize(
               "localStorage",
               "bnest.sifat-allah.v1",
               payload,
               "import-invalid-session"
             )
  end

  test "rejects malformed values and sources outside the allow-list" do
    assert {:error, :malformed} =
             normalize(
               "sessionStorage",
               "bnest.chat.v1",
               "{not-json",
               "import-malformed-chat"
             )

    assert {:error, :malformed} =
             normalize(
               "localStorage",
               "bnest.sifat-allah.v1",
               "{not-json",
               "import-malformed-learning"
             )

    assert {:error, :malformed} =
             normalize(
               "localStorage",
               "phx:theme",
               "system",
               "import-invalid-theme"
             )

    assert {:error, :unsupported_source} =
             normalize(
               "localStorage",
               "private.other",
               "value",
               "import-unsupported"
             )
  end

  test "derives supported source versions and defaults malformed legacy payloads to version one" do
    assert Normalizer.source_version("phx:theme", "dark") == 1
    assert Normalizer.source_version("bnest.chat.v1", ~s({"version":2})) == 2
    assert Normalizer.source_version("bnest.chat.v1", ~s({"version":0})) == 1
    assert Normalizer.source_version("bnest.chat.v1", "{not-json") == 1
  end

  test "stamps the candidate with the given time" do
    assert {:ok, :theme, %{"updatedAt" => "2026-09-01T00:00:00Z"}} =
             normalize("localStorage", "phx:theme", "light", "import-unit-time")
  end

  defp normalize(area, key, payload, import_id),
    do: Normalizer.normalize(area, key, payload, import_id, @now, Storage.record_kinds())
end
