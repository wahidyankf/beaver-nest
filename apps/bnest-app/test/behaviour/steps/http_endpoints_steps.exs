defmodule BnestApp.Behaviour.HttpEndpointsSteps do
  @moduledoc """
  Bindings for `specs/apps/bnest/app-be/behaviours/http_endpoints.feature`.

  Each step delegates to the adapter the layer installed
  (`HttpEndpoints.UnitAdapter` for the unit layer,
  `HttpEndpoints.IntegrationAdapter` for the integration layer). A Given
  records the scenario's release, session, or store, a When reaches the
  production boundary, and a Then asserts the recorded answer, so no step is
  a placeholder or a success literal.
  """

  use ExBdd.StepDefinition

  alias BnestApp.Behaviour.HttpEndpoints.IntegrationAdapter, as: Integration
  alias BnestApp.Behaviour.HttpEndpoints.UnitAdapter, as: Unit
  alias BnestApp.Behaviour.IntegrationHomePageDriver

  defp adapter(%{behaviour_driver: IntegrationHomePageDriver}), do: Integration
  defp adapter(_), do: Unit

  # The hooks install the web drivers, not the HTTP adapter: the first
  # HTTP step of a scenario installs it, later steps reuse the state.
  defp http(context) do
    if Map.has_key?(context, :http), do: context, else: adapter(context).install(context)
  end

  # Liveness reports its status, revision, and slot (BN-HTTP-01).

  step(
    "the release names revision {string} and slot {string}",
    %{args: [revision, slot]} = context
  ) do
    context |> http() |> adapter(context).set_release(revision, slot)
  end

  step("a visitor fetches the liveness probe", context) do
    context |> http() |> adapter(context).fetch_liveness()
  end

  step(
    "the probe answers live with revision {string} from slot {string}",
    %{args: [revision, slot]} = context
  ) do
    context |> http() |> adapter(context).assert_liveness(revision, slot)
  end

  step("the revision header carries {string}", %{args: [reported]} = context) do
    context |> http() |> adapter(context).assert_liveness_header(reported)
  end

  # A theme change is saved or refused as invalid (BN-HTTP-10).

  step("a visitor signed in as the scenario's owner", context) do
    context |> http() |> adapter(context).sign_in_owner()
  end

  step("the owner saved theme {string}", %{args: [saved]} = context) do
    context |> http() |> adapter(context).seed_theme(saved)
  end

  step("the visitor saves theme {string}", %{args: [theme]} = context) do
    context |> http() |> adapter(context).save_theme(theme)
  end

  step("the theme answer is {int} with body {string}", %{args: [status, body]} = context) do
    context |> http() |> adapter(context).assert_theme_answer(status, body)
  end

  step("the stored theme is {string}", %{args: [stored]} = context) do
    context |> http() |> adapter(context).assert_stored_theme(stored)
  end

  # A theme change is refused for a user without write rights or when the store rejects it (BN-HTTP-10).

  step("a visitor signed in with {string} roles", %{args: [roles]} = context) do
    context |> http() |> adapter(context).sign_in_roles(roles)
  end

  step("the preference store {string}", %{args: [store]} = context) do
    context |> http() |> adapter(context).set_store(store)
  end

  # A public static file is served without signing in (BN-HTTP-23).

  step("a visitor with no session", context) do
    context |> http() |> adapter(context).sign_out()
  end

  step("the visitor fetches {string}", %{args: [path]} = context) do
    context |> http() |> adapter(context).fetch_static(path)
  end

  step("the file answers 200 with its own {string} content", %{args: [media]} = context) do
    context |> http() |> adapter(context).assert_static(media)
  end

  # An unknown path gets the stock not found page, as HTML or JSON (BN-HTTP-24).

  step("a visitor asking for {string}", %{args: [media]} = context) do
    context |> http() |> adapter(context).ask_for(media)
  end

  step("the visitor opens the unknown path", context) do
    context |> http() |> adapter(context).open_unknown_path()
  end

  step("the unknown path answers 404 as {string}", %{args: [format]} = context) do
    context |> http() |> adapter(context).assert_unknown_path(format)
  end

  step("the not found detail is {string}", %{args: [detail]} = context) do
    context |> http() |> adapter(context).assert_unknown_detail(detail)
  end
end
