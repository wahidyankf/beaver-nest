defmodule BnestAppWeb.EntrypointTest do
  # The web entrypoint is pure quoting: every `use BnestAppWeb, which` expands to the
  # quoted framework wiring below, so calling each quote covers the module.
  use ExUnit.Case, async: true

  defmodule SupportController do
    use BnestAppWeb, :controller

    def used?, do: true
  end

  test "static paths serve the app shell including the service worker" do
    assert BnestAppWeb.static_paths() ==
             ~w(assets fonts images favicon.ico manifest.webmanifest robots.txt service-worker.js)
  end

  test "every interface quote wires its framework" do
    assert BnestAppWeb.router() |> Macro.to_string() =~ "Phoenix.Router"
    assert BnestAppWeb.channel() |> Macro.to_string() =~ "Phoenix.Channel"

    assert BnestAppWeb.controller() |> Macro.to_string() =~ "Phoenix.Controller"
    assert BnestAppWeb.live_view() |> Macro.to_string() =~ "Phoenix.LiveView"
    assert BnestAppWeb.live_component() |> Macro.to_string() =~ "Phoenix.LiveComponent"
    assert BnestAppWeb.html() |> Macro.to_string() =~ "Phoenix.Component"
    assert BnestAppWeb.verified_routes() |> Macro.to_string() =~ "VerifiedRoutes"
  end

  test "using dispatches to the named interface quote" do
    assert SupportController.used?()
  end
end
