defmodule BnestAppWeb.TestingControl.InstanceController do
  @moduledoc """
  The testing-control routes for the instance lifecycle (ADR 001, section 2): state, spawn, seed and
  teardown.

  The router mounts these routes only in the test build (see `BnestAppWeb.TestingRoutes`), and this
  module lives in `test/support`, so a production beam never contains it. Every request has passed
  `BnestAppWeb.TestingControl.Guard` before an action runs. Paths come only from the run and the
  instance, through `BnestApp.TestInstance`; nothing the request sends names a path.

  Concurrency. Each request runs in its own process. A spawn, a delete and a seed of the current
  instance each take the switch lock without waiting, so an overlapping one is answered 409
  `instance_active` at once and changes nothing. A spawn while a scheduler task runs is answered 409
  `instance_busy`. `GET /state` takes no lock: it reads the state a finished switch left, and a
  spawn becomes visible once it is current, before its seed runs.

  Failure injection. `:testing_control_fail_after` in the application environment names a spawn step
  to fail after its work, so a test can check the rollback. Only code in the test build reads it, and
  no request can set it.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]
  use BnestAppWeb, :controller

  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Error
  alias BnestAppWeb.TestingControl.ErrorBody
  alias BnestAppWeb.TestingControl.Request

  @seed_key "spawn"

  def state(conn, _params) do
    run = TestInstance.application_run!()

    json(conn, %{
      "schemaVersion" => 1,
      "runId" => run.run_id,
      "instance" => summary(TestInstance.info())
    })
  end

  def create(conn, _params) do
    run = TestInstance.application_run!()

    with :ok <- envelope(conn),
         {:ok, body} <- Request.spawn_body(conn.body_params),
         :ok <- same_run(body.run_id, run.run_id) do
      guarded(conn, fn -> spawn_instance(conn, run, body) end)
    else
      {:error, reason} -> answer_error(conn, reason)
    end
  end

  def seed(conn, %{"id" => id}) do
    with :ok <- envelope(conn),
         {:ok, body} <- Request.seed_body(conn.body_params) do
      guarded(conn, fn -> seed_current(conn, id, body) end)
    else
      {:error, reason} -> answer_error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    guarded(conn, fn ->
      case TestInstance.state() do
        %{instance_id: ^id} = instance ->
          :ok = TestInstance.drop!(instance)
          send_resp(conn, 204, "")

        _other ->
          answer_error(conn, :not_current)
      end
    end)
  end

  defp spawn_instance(conn, run, body) do
    instance = TestInstance.spawn!(run, spawn_opts(body))

    conn
    |> put_status(201)
    |> json(spawned(instance))
  end

  defp spawn_opts(body) do
    [
      phase: body.phase,
      label: body.label,
      fail_after: Application.get_env(:bnest_app, :testing_control_fail_after)
    ] ++ instance_id_opts(body.instance_id) ++ seed_opts(body.seed)
  end

  # Absent, the server generates the id. Present, it is the client's id, already checked by the
  # request shape rules.
  defp instance_id_opts(nil), do: []
  defp instance_id_opts(instance_id), do: [instance_id: instance_id]

  defp seed_opts(:absent), do: []
  defp seed_opts({:present, seed}), do: [seed: {@seed_key, seed}]

  defp seed_current(conn, id, body) do
    case TestInstance.seed_current(id, body.seed_key, body.seed) do
      {:ok, %{seed_key: seed_key, applied: applied}} ->
        json(conn, %{"seedKey" => seed_key, "applied" => applied})

      {:error, reason} ->
        answer_error(conn, seed_refusal(reason))
    end
  end

  # A seed refusal keeps the code, the reason and the path. A production facade's failure keeps
  # nothing of the input, so it is one fixed answer.
  defp seed_refusal(:not_current), do: :not_current
  defp seed_refusal(:seed_conflict), do: :seed_conflict

  defp seed_refusal(%{code: :seed_invalid, reason: reason, path: path}),
    do: {:seed_invalid, reason, path}

  defp seed_refusal(_facade_failure), do: :seed_failed

  defp spawned(instance) do
    %{label: label} = TestInstance.info()

    %{
      "instanceId" => instance.instance_id,
      "label" => label,
      "phase" => Atom.to_string(instance.phase),
      "generation" => instance.paths.generation,
      "accounts" => spawned_accounts(instance),
      "environment" => environment(instance)
    }
  end

  # The accounts the spawn's own seed created. An instance spawned without a seed has none.
  defp spawned_accounts(instance) do
    {:ok, registry} = TestInstance.seed_registry(instance)

    registry
    |> Map.get(:keys, %{})
    |> Map.get(@seed_key, %{})
    |> Map.get(:accounts, [])
    |> Enum.map(fn account ->
      %{"username" => account.username, "userId" => account.user_id, "roles" => account.roles}
    end)
  end

  # The environment a secondary BEAM needs to read the instance: a flat instance root for a flat
  # instance, the run base for a SQLite one (ADR 001, section 1), and the storage pointer.
  defp environment(instance) do
    %{
      "BNEST_TEST_INSTANCE_ID" => instance.instance_id,
      "BNEST_RUNTIME_ROOT" => runtime_root(instance),
      "BNEST_STORAGE_CONFIG" => instance.paths.storage_pointer_path
    }
  end

  defp runtime_root(%{phase: :flat_primary, paths: paths}), do: paths.flat_instance_root
  defp runtime_root(%{paths: paths}), do: paths.flat_run_root

  defp summary(nil), do: nil

  defp summary(%{instance: instance, label: label, created_at: created_at}) do
    %{
      "instanceId" => instance.instance_id,
      "label" => label,
      "phase" => Atom.to_string(instance.phase),
      "generation" => instance.paths.generation,
      "createdAt" => created_at
    }
  end

  # Runs an action that may raise a lifecycle refusal or failure, and answers that error.
  defp guarded(conn, action) do
    action.()
  rescue
    error in Error -> answer_error(conn, lifecycle_reason(error))
  end

  defp lifecycle_reason(%Error{
         reason: :spawn_failed,
         step: :seed,
         detail: %{code: :seed_invalid} = detail
       }),
       do: {:seed_invalid, detail.reason, detail.path}

  defp lifecycle_reason(%Error{reason: :spawn_failed, step: step}), do: {:spawn_failed, step}
  defp lifecycle_reason(%Error{reason: :cleanup_failed, path: path}), do: {:cleanup_failed, path}

  # A refused removal leaves the instance and its directories in place, so its path is retained.
  defp lifecycle_reason(%Error{reason: :refused, path: path}), do: {:cleanup_failed, path}

  defp lifecycle_reason(%Error{reason: reason})
       when reason in [
              :instance_active,
              :instance_busy,
              :instance_exists,
              :not_current,
              :run_mismatch
            ],
       do: reason

  # A preflight refusal that is not a wire state (an invalid instance or a storage pointer that is
  # not the instance's) happens before anything is created, so it is a failed create.
  defp lifecycle_reason(%Error{}), do: {:spawn_failed, :create}

  defp answer_error(conn, reason) do
    {status, body} = ErrorBody.render(reason)

    conn
    |> put_status(status)
    |> json(body)
  end

  defp envelope(conn) do
    Request.envelope(
      get_req_header(conn, "content-type"),
      get_req_header(conn, "content-length")
    )
  end

  defp same_run(run_id, run_id), do: :ok
  defp same_run(_requested, _run_id), do: {:error, :run_mismatch}
end
