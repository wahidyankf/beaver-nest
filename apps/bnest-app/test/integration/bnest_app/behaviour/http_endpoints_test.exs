defmodule BnestApp.Behaviour.HttpEndpointsIntegrationTest do
  @moduledoc """
  Integration tests for the `http_endpoints.feature` scenarios. Every scenario
  of the feature carries a `@scenario` reference below, so the behaviour
  coverage check sees the integration binding the review requires. The adapter
  drives the real endpoint over a fresh test instance. The refused-write
  scenario needs no marker here; its `@e2e-exempt` tag is the e2e proof the
  review records.
  """

  # The adapter reaches the endpoint and the instance records, both global to
  # the VM, so scenarios run sequentially. ConnCase spawns each test its own
  # fresh instance and signs its conn in.
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.Behaviour.HttpEndpoints.IntegrationAdapter, as: Adapter

  defp installed(context), do: Adapter.install(context)

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: Liveness reports its status, revision, and slot
  test "liveness reports live with the release revision and slot, or the defaults", context do
    for {revision, slot, reported, reported_slot} <- [
          {"test-revision", "blue", "test-revision", "blue"},
          {"(unset)", "(unset)", "development", "standalone"}
        ] do
      installed(context)
      |> Adapter.set_release(revision, slot)
      |> Adapter.fetch_liveness()
      |> Adapter.assert_liveness(reported, reported_slot)
      |> Adapter.assert_liveness_header(reported)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: A theme change is saved or refused as invalid
  test "a valid theme is saved and read back, an invalid one is refused", context do
    for {saved, theme, status, body, stored} <- [
          {"dark", "light", 204, "(empty)", "light"},
          {"(none)", "dark", 204, "(empty)", "dark"},
          {"dark", "system", 204, "(empty)", "system"},
          {"dark", "neon", 422, "Invalid theme.", "dark"},
          {"dark", "(empty)", 422, "Invalid theme.", "dark"}
        ] do
      installed(context)
      |> Adapter.sign_in_owner()
      |> Adapter.seed_theme(saved)
      |> Adapter.save_theme(theme)
      |> Adapter.assert_theme_answer(status, body)
      |> Adapter.assert_stored_theme(stored)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: A theme change is refused for a user without write rights or when the store rejects it
  test "a role without write rights is forbidden and a rejected write conflicts", context do
    for {roles, store, status, body} <- [
          {"(empty)", "accepts writes", 403, "Forbidden"},
          {"unknown", "accepts writes", 403, "Forbidden"},
          {"admin", "rejects writes", 409, "Theme preference was not changed."}
        ] do
      installed(context)
      |> Adapter.sign_in_roles(roles)
      |> Adapter.set_store(store)
      |> Adapter.save_theme("dark")
      |> Adapter.assert_theme_answer(status, body)
      |> Adapter.assert_stored_theme("system")
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: A public static file is served without signing in
  test "the public files are served with their own content", context do
    for {path, media} <- [
          {"/robots.txt", "text/plain"},
          {"/manifest.webmanifest", "application/manifest+json"}
        ] do
      installed(context)
      |> Adapter.sign_out()
      |> Adapter.fetch_static(path)
      |> Adapter.assert_static(media)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: An unknown path gets the stock not found page, as HTML or JSON
  test "the stock not found page renders as HTML and as JSON", context do
    for {media, format} <- [{"text/html", "HTML"}, {"application/json", "JSON"}] do
      installed(context)
      |> Adapter.ask_for(media)
      |> Adapter.open_unknown_path()
      |> Adapter.assert_unknown_path(format)
      |> Adapter.assert_unknown_detail("Not Found")
    end
  end
end
