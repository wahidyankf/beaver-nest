defmodule BnestApp.Behaviour.OperatorConfigurationTest do
  @moduledoc """
  Unit tests for the operator_configuration.feature model and adapter.
  """

  use ExUnit.Case, async: false

  alias BnestApp.Behaviour.OperatorConfiguration.UnitAdapter, as: Adapter
  alias BnestApp.Behaviour.OperatorConfigurationModel, as: Model

  defp context, do: Adapter.install(%{})

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: A production start refuses missing or unsafe push configuration
  test "production refuses missing or unsafe push configuration" do
    for {public_file, private_file, subject, boot} <- [
          {"(unset)", "/keys/private", "mailto:ops@example.com",
           "environment variable BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE is missing"},
          {"/keys/public", "(unset)", "mailto:ops@example.com",
           "environment variable BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE is missing"},
          {"/keys/public", "/keys/private", "(unset)",
           "environment variable BNEST_WEB_PUSH_SUBJECT is missing"},
          {"/keys/public", "/keys/private", "ops@example.com",
           "BNEST_WEB_PUSH_SUBJECT must be a mailto: or https: contact"},
          {"/keys/public", "/keys/private", "mailto:ops@example.com",
           "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE/BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must not be empty"}
        ] do
      context()
      |> Adapter.push_env(public_file, private_file, subject)
      |> Adapter.derive_push()
      |> Adapter.assert_push(boot)
    end

    assert Model.missing_public() =~ "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: Stable mode turns off code reload and asset watchers
  test "stable mode turns off reload and watchers" do
    for {stable, reload, watchers} <- [
          {"true", "off", "none"},
          {"(unset)", "on", "esbuild,Tailwind"},
          {"false", "on", "esbuild,Tailwind"}
        ] do
      context()
      |> Adapter.stable_env(stable)
      |> Adapter.derive_dev()
      |> Adapter.assert_dev(reload, watchers)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: Readiness fails closed while the named peer slot does not answer
  test "readiness fails closed while the peer does not answer" do
    loop = Model.loopback_string()

    for {peer, reachable, live, ready, health} <- [
          {"(unset)", "(n/a)", "live", "ready", "200 ready"},
          {"test-peer@test-host", "no", "live", "not_ready", "503 not_ready"},
          {"test-peer@test-host", "yes", "live", "ready", "200 ready"}
        ] do
      _ = loop

      context()
      |> Adapter.peer_env(peer, reachable)
      |> Adapter.check_readiness()
      |> Adapter.assert_readiness(live, ready, health)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: A slot deployment refuses to start without its deployment files and origin
  test "deploy prepare refuses without files and origin" do
    good = Model.good_origin()
    bad = Model.bad_origin()

    for {missing, origin, message} <- [
          {"BNEST_DEPLOY_COOKIE_FILE", good,
           "BNEST_DEPLOY_COOKIE_FILE must point to machine-local deployment state."},
          {"BNEST_DEPLOY_SECRET_KEY_BASE_FILE", good,
           "BNEST_DEPLOY_SECRET_KEY_BASE_FILE must point to machine-local deployment state."},
          {"BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE", good,
           "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE must point to machine-local deployment state."},
          {"BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE", good,
           "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must point to machine-local deployment state."},
          {"(none)", "(unset)", "BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin."},
          {"(none)", bad, "Production origin must be a bare HTTPS origin"}
        ] do
      context()
      |> Adapter.deploy_env(missing, origin)
      |> Adapter.attempt_prepare()
      |> Adapter.assert_prepare(message)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: A production node joins the cluster named by DNS_CLUSTER_QUERY
  test "cluster follows the DNS query" do
    for {query, cluster} <- [
          {"bnest-prod.example", "DNS bnest-prod.example"},
          {"(unset)", "no cluster"}
        ] do
      context()
      |> Adapter.cluster_env(query)
      |> Adapter.derive_cluster()
      |> Adapter.assert_cluster(cluster)
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-be/behaviours/operator_configuration.feature: Production listens on loopback and redirects plain HTTP to HTTPS
  test "production binds loopback and redirects plain HTTP" do
    loop = Model.loopback_string()
    local_host = Model.localhost_string()
    public_host = Model.public_host_string()

    for {host, scheme, answer} <- [
          {public_host, "http", "redirect to HTTPS + HSTS"},
          {public_host, "https", "serve"},
          {local_host, "http", "serve"},
          {loop, "http", "serve"}
        ] do
      context()
      |> Adapter.transport_env(host, scheme)
      |> Adapter.derive_transport()
      |> Adapter.assert_transport(loop, answer)
    end
  end
end
