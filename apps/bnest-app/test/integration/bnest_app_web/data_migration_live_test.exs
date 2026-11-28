defmodule BnestAppWeb.DataMigrationLiveIntegrationTest do
  @moduledoc """
  Integration tests for the `centralized_data.feature` migration scenarios. The
  routed `/data-migration` page is driven through LiveViewTest: the browser report
  arrives through the page's hook event and the confirmation through its button,
  against the test instance's record repository.
  """

  use BnestAppWeb.ConnCase, async: false

  # Browser import keeps its envelopes and manifests in the records store, which is a flat
  # store (`Records.store/0`), so these tests run on a flat-primary instance whose flat root
  # is its own. A SQLite-primary instance would leave the imports in the data-free run base,
  # tripping the end-of-suite leak audit. This mirrors the `@flat-primary` tag on the
  # centralized_data scenarios and the `BrowserImportTest` phase tag.
  @moduletag phase: :flat_primary

  import Phoenix.LiveViewTest

  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Records

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: The migration page lists each recognized browser source
  test "the migration page lists each recognized browser source", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/data-migration")

    render_hook(view, "browser-sources", %{
      "sources" => [
        Map.put(chat_source(), "present", true),
        Map.put(learning_source(), "present", true),
        %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "present" => false},
        %{
          "storageArea" => "localStorage",
          "storageKey" => "unknown.key",
          "present" => true,
          "payload" => "keep"
        }
      ]
    })

    html = render(view)

    assert html =~ "Chat conversation"
    assert html =~ "Ready to preserve"
    assert html =~ "Sifat Allah progress"
    assert html =~ "Theme preference"
    assert html =~ "Uses system default"
    refute html =~ "unknown.key"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  # One test per outline row: each row imports under its own manifest, and the
  # centralized chat record holds a single revision per user, so rows that file
  # different payloads cannot share a test user.
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  test "an accepted import shows its label and status", %{conn: conn} do
    assert import_line(conn, present(chat_source())) ==
             "Chat conversation: accepted and verified"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  test "a rejected import shows its label and status", %{conn: conn} do
    malformed = %{chat_source() | "payload" => "{malformed"}

    assert import_line(conn, present(malformed)) ==
             "Chat conversation: rejected safely; browser source retained"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each retryable or stale import outcome shows its label and its status
  test "a retryable import shows its label and status", %{
    conn: conn,
    test_identity: identity
  } do
    store = Records.store()
    retryable = with_model("retryable-model")
    {:ok, %{import_id: import_id}} = Import.browser(store, identity.user_id, retryable)

    import_id
    |> manifest_path(store)
    |> File.write!("{corrupted")

    assert import_line(conn, present(retryable)) ==
             "Chat conversation: not completed; retry without re-entering data"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/centralized_data.feature: A stale browser cannot overwrite a newer centralized record
  test "a stale import shows its label and status", %{conn: conn, test_identity: identity} do
    store = Records.store()
    {:ok, _accepted} = Import.browser(store, identity.user_id, with_model("stale-base-model"))

    assert import_line(conn, present(with_model("stale-model"))) ==
             "Chat conversation: newer server data exists; refresh before retrying"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: A browser acting as the local user is told to log in before importing
  @tag :unauthenticated
  test "a browser acting as the local user is told to log in before importing", %{conn: _conn} do
    previous = Application.fetch_env!(:bnest_app, :identity_cutover_enabled)

    on_exit(fn -> Application.put_env(:bnest_app, :identity_cutover_enabled, previous) end)
    Application.put_env(:bnest_app, :identity_cutover_enabled, false)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(Phoenix.ConnTest.build_conn(), "/data-migration")

    redirected = Phoenix.ConnTest.build_conn() |> get("/data-migration")
    assert redirected_to(redirected) == "/"

    home = redirected |> recycle() |> get("/")
    assert html_response(home, 200) =~ "Log in before importing browser data."
    refute html_response(home, 200) =~ "Preserve and verify recognized data"
  end

  defp import_line(conn, source) do
    {:ok, view, _html} = live(conn, "/data-migration")
    render_hook(view, "browser-sources", %{"sources" => [source]})
    html = view |> element("button[phx-click=confirm-imports]") |> render_click()

    lines =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[aria-live=polite] p")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert length(lines) == 1
    hd(lines)
  end

  defp manifest_path(import_id, store),
    do: Path.join(store.root, "system/manifests/#{import_id}.json")

  defp present(source), do: Map.put(source, "present", true)

  defp with_model(model) do
    %{
      chat_source()
      | "payload" => String.replace(chat_source()["payload"], "fixture-model", model)
    }
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
        Jason.encode!(%{
          "version" => 2,
          "learned_ids" => [],
          "review_ids" => [],
          "mastered_key_ids" => [],
          "review_key_ids" => [],
          "correct_answers" => 0,
          "incorrect_answers" => 0,
          "session" => %{"mode" => "dashboard"}
        })
    }
  end
end
