defmodule BnestAppWeb.TestingControl.ErrorBody do
  @moduledoc """
  The answer to each refusal and failure of the testing-control routes (ADR 001, section 2, error
  codes). Every body is `{"error": {"code", "detail", "path"}}`. A spawn failure also names its
  `step`.

  No text of the input is echoed. A detail is fixed text, or for `seed_invalid` the reason from the
  seed validator's closed vocabulary. A seed path is returned only when each of its names is a field
  the seed schema defines (an index is allowed), so a key a caller invented, which could be any text,
  is reported as `unknown`. The one path that can be returned is a retained path a failed cleanup
  names, which the controller takes from inside the run roots.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @seed_reasons ~w(invalid_payload invalid_username invalid_role duplicate_username unknown_sender
                   unknown_owner unknown_seed_key too_many wrong_phase unsupported_source oversized)a
  @seed_fields ~w(seed seedKey accounts username password roles familyChat messages sender body
                  idempotencyKey pushSubscriptions owner endpoint p256dh auth records kind value theme
                  storageArea storageKey payload)
  @steps ~w(create activate migrate seed)a

  @type reason ::
          {:invalid_request, String.t()}
          | :run_mismatch
          | :instance_active
          | :instance_exists
          | :not_current
          | :instance_busy
          | :seed_conflict
          | {:seed_invalid, atom(), String.t()}
          | {:spawn_failed, atom()}
          | {:cleanup_failed, String.t()}
          | :seed_failed

  @spec render(reason()) :: {pos_integer(), map()}
  def render({:invalid_request, detail}) when is_binary(detail),
    do: {400, error("invalid_request", detail, nil)}

  def render(:run_mismatch),
    do: {409, error("run_mismatch", "the run id is not this run", nil)}

  def render(:instance_active),
    do: {409, error("instance_active", "an instance is already current", nil)}

  # A client-chosen id whose directories already exist: no existing 409 code names it better, so it
  # keeps `instance_active` (ADR 001, section 2) with its own fixed detail.
  def render(:instance_exists),
    do: {409, error("instance_active", "an instance with that id already exists", nil)}

  def render(:not_current),
    do: {409, error("not_current", "the instance is not the current instance", nil)}

  def render(:instance_busy),
    do: {409, error("instance_busy", "a scheduler task is running", nil)}

  def render(:seed_conflict),
    do: {409, error("seed_conflict", "the seed key was used with another body", nil)}

  def render({:seed_invalid, reason, path}),
    do: {422, error("seed_invalid", reason_text(reason), seed_path(path))}

  def render({:spawn_failed, step}) do
    body = error("spawn_failed", "the spawn failed and was undone", nil)
    {500, put_in(body, ["error", "step"], step_text(step))}
  end

  def render({:cleanup_failed, path}) when is_binary(path),
    do:
      {500, error("cleanup_failed", "the instance could not be removed; it fails the run", path)}

  def render(:seed_failed),
    do:
      {500, error("seed_failed", "a production write refused the seed; delete the instance", nil)}

  defp error(code, detail, path),
    do: %{"error" => %{"code" => code, "detail" => detail, "path" => path}}

  defp reason_text(reason) when reason in @seed_reasons, do: Atom.to_string(reason)
  defp reason_text(_reason), do: "invalid_payload"

  # Every path the seed validator produces is a string, so the check needs no other clause.
  defp seed_path(path) do
    if path |> String.split(".") |> Enum.all?(&schema_name?/1), do: path, else: "unknown"
  end

  defp schema_name?(segment) do
    name = String.replace(segment, ~r/\[[0-9]+\]/, "")
    name in @seed_fields
  end

  defp step_text(step) when step in @steps, do: Atom.to_string(step)
  defp step_text(_step), do: "unknown"
end
