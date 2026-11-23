defmodule BnestApp.Behaviour.OperatorConfigurationModel do
  @moduledoc """
  Shared expectations for operator_configuration.feature.

  Both layers drive scenarios through this model. The unit adapter feeds it
  the scenario data over pure doubles; the integration adapter feeds it values
  read back from the real implementation where a boundary exists.
  """

  @missing_public "environment variable BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE is missing"
  @missing_private "environment variable BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE is missing"
  @missing_subject "environment variable BNEST_WEB_PUSH_SUBJECT is missing"
  @bad_subject "BNEST_WEB_PUSH_SUBJECT must be a mailto: or https: contact"
  @empty_keys "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE/BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must not be empty"

  def missing_public, do: @missing_public
  def missing_private, do: @missing_private
  def missing_subject, do: @missing_subject
  def bad_subject, do: @bad_subject
  def empty_keys, do: @empty_keys

  def push_boot("(unset)", _private, _subject, _read), do: {:error, @missing_public}
  def push_boot(_public, "(unset)", _subject, _read), do: {:error, @missing_private}
  def push_boot(_public, _private, "(unset)", _read), do: {:error, @missing_subject}
  def push_boot(_public, _private, "", _read), do: {:error, @missing_subject}

  def push_boot(_public, _private, subject, _read) do
    if subject =~ ~r/^(mailto:|https:\/\/)\S+$/ do
      {:ok, :configured}
    else
      {:error, @bad_subject}
    end
  end

  def push_empty_boot, do: {:error, @empty_keys}

  def dev_config("true"), do: {:off, :none}
  def dev_config(_other), do: {:on, :watchers}

  def readiness("(unset)", _reachable), do: {:live, :ready, :ready_200}
  def readiness("", _reachable), do: {:live, :ready, :ready_200}
  def readiness(_peer, "yes"), do: {:live, :ready, :ready_200}
  def readiness(_peer, _no), do: {:live, :not_ready, :not_ready_503}

  def deploy_message("BNEST_DEPLOY_COOKIE_FILE"),
    do: "BNEST_DEPLOY_COOKIE_FILE must point to machine-local deployment state."

  def deploy_message("BNEST_DEPLOY_SECRET_KEY_BASE_FILE"),
    do: "BNEST_DEPLOY_SECRET_KEY_BASE_FILE must point to machine-local deployment state."

  def deploy_message("BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE"),
    do: "BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE must point to machine-local deployment state."

  def deploy_message("BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE"),
    do: "BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must point to machine-local deployment state."

  def deploy_message(_other), do: :origin

  def origin_message("(unset)"),
    do: "BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin."

  def origin_message("http://service.example"),
    do: "Production origin must be a bare HTTPS origin"

  def origin_message(_ok), do: :ok

  def cluster_for("(unset)"), do: :no_cluster
  def cluster_for(""), do: :no_cluster
  def cluster_for(query), do: {:dns, query}

  def loopback_string, do: "127.0.0.1"
  def localhost_string, do: "localhost"
  def public_host_string, do: "service.example"
  def good_origin, do: "https://service.example"
  def bad_origin, do: "http://service.example"

  def transport(_host, "https"), do: :serve
  def transport("localhost", _scheme), do: :serve
  def transport("127.0.0.1", _scheme), do: :serve
  def transport(_host, "http"), do: :redirect
  def transport(_host, _other), do: :serve

  def loopback_bind?(bind), do: bind == "127.0.0.1"
end
