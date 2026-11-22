defmodule BnestApp.Behaviour.TestIsolation.UnitAdapter do
  @moduledoc """
  The unit layer's adapter for `test_isolation.feature` (ADR 001, section 6). It drives the pure test-side
  port `BnestApp.Test.InMemory.TestInstancePort` and the production guard decision
  `BnestAppWeb.TestingControl.Guard.decide/1`. It touches no file, socket or process, so it lives in
  `test/unit/support`, where the boundary policy scans it.

  Every answer is a model answer. The unit layer cannot see SQLite, so only the integration adapter proves
  the real database.

  Scope of the lifecycle rows (spawn, failed spawn, rollback, teardown): they run the in-memory port, whose
  spawn order and rollback follow `BnestApp.TestInstance`. The unit layer cannot run the switch, because
  the switch writes the storage pointer and the run roots, which the unit boundary forbids. So these rows
  prove the model's contract. The integration adapter runs the production switch and proves the same
  steps on real files and a real repository.
  """

  alias BnestApp.Behaviour.TestIsolation.Fixtures
  alias BnestApp.Test.InMemory.TestInstancePort, as: Lifecycle
  alias BnestAppWeb.TestingControl.ErrorBody
  alias BnestAppWeb.TestingControl.Guard
  alias BnestAppWeb.TestingControl.Secret

  @route_prefix "/__bnest_testing/v1"
  # The stock missing-route answer: the exception the router raises for a route it does not know.
  @missing_route_answer {:raised, Phoenix.Router.NoRouteError}
  @loopback {127, 0, 0, 1}
  @outside_peer {203, 0, 113, 9}

  @doc "Installs the model and this adapter in the scenario context. The unit layer starts with no instance."
  def prepare(context) do
    context
    |> Map.put(:isolation_adapter, __MODULE__)
    |> Map.put(:isolation, %{port: Lifecycle.new(), instance_id: nil, fail_after: nil})
  end

  @doc "Nothing to release: the model is discarded with the scenario context."
  def release(context), do: context

  @doc "The current instance's id and generation, or nil."
  def current(context), do: Lifecycle.current(context.isolation.port)

  @doc "What `GET /state` reports as the current instance: the model's answer."
  def server_state(context), do: Lifecycle.current(context.isolation.port)

  def choose_instance_id(context),
    do: put_isolation(context, :instance_id, Fixtures.new_instance_id())

  def inject_failure(context, step), do: put_isolation(context, :fail_after, step)

  @doc "The previous test ends: its instance is dropped and the next test chooses its own id."
  def end_test(context) do
    port = context.isolation.port

    dropped =
      case Lifecycle.current(port) do
        nil -> port
        %{instance_id: id} -> port_after_drop(Lifecycle.drop(port, id))
      end

    context
    |> Map.put(:previous_spawn, Map.get(context, :spawn))
    |> put_port(dropped)
    |> put_isolation(:instance_id, nil)
  end

  @doc """
  The approved admin that `test_instances.feature` starts from: a fresh instance seeded with one admin
  account, and that account logged in through the port. The credentials are kept so a later login can
  present them. A login that the model refuses fails the Given, so the Then never starts from nothing.
  """
  def establish_admin(context) do
    context = spawn_with_admin(context)
    {:ok, %{accounts: [username]}} = context.spawn
    password = Fixtures.password()

    case Lifecycle.login(context.isolation.port, username, password) do
      {:ok, port} ->
        context
        |> put_port(port)
        |> Map.put(:previous_admin, %{username: username, password: password})

      :error ->
        raise "the approved admin cannot log in to its own instance"
    end
  end

  @doc """
  Replaces the current instance: the current one is dropped, then a fresh instance seeded with its own
  admin is spawned. The dropped spawn is kept as `previous_spawn`, and the previous admin's credentials
  stay in the context for the refusal check.
  """
  def replace_instance(context), do: context |> end_test() |> spawn_with_admin()

  @doc """
  Presents the previous admin's credentials to the current instance: `:ok` when the model opens a session,
  `:error` when it refuses.
  """
  def login_as_previous_admin(context) do
    %{username: username, password: password} = context.previous_admin

    case Lifecycle.login(context.isolation.port, username, password) do
      {:ok, _port} -> :ok
      :error -> :error
    end
  end

  @doc """
  Spawns through the port. `opts`: `:phase`, `:seed` (a seed map), and `:usernames` (the usernames the
  seed sends, kept for the comparison with what the spawn lists).
  """
  def spawn_instance(context, opts) do
    spawn_opts =
      [
        instance_id: context.isolation.instance_id,
        phase: Keyword.get(opts, :phase, :sqlite_primary),
        fail_after: context.isolation.fail_after
      ] ++ seed_option(opts)

    {observed, port} =
      case Lifecycle.spawn(context.isolation.port, spawn_opts) do
        {:ok, port, observation} -> {{:ok, observation}, port}
        {:error, port, refusal} -> {{:error, refusal}, port}
      end

    context
    |> put_port(port)
    |> Map.put(:spawn, observed)
    |> Map.put(:sent_usernames, Keyword.get(opts, :usernames, []))
  end

  @doc "Deletes the current instance, then deletes it again. Answers the two statuses the endpoint gives."
  def delete_current(context) do
    id = context.isolation.instance_id
    first = drop_answer(context.isolation.port, id)
    again = drop_answer(first.port, id)

    context
    |> put_port(again.port)
    |> Map.put(:delete, %{first: first.status, again: again.status})
  end

  @doc """
  A client's create request under one variant: `:no_header`, `:wrong_header`, `:forwarded` or
  `:non_loopback`. The guard decides it; the answer is what the refusal raises.
  """
  def create_request(context, variant) do
    decision = variant |> guard_request() |> Guard.decide()

    Map.put(context, :request, %{
      response: answer(decision),
      missing: @missing_route_answer,
      decision: decision
    })
  end

  def setup_open?(context), do: Lifecycle.setup_open?(context.isolation.port)

  def account_present?(context, username),
    do: Lifecycle.account?(context.isolation.port, username)

  def readiness_generation(context) do
    case Lifecycle.current(context.isolation.port) do
      nil -> nil
      %{generation: generation} -> generation
    end
  end

  @doc "Whether the spawn finished its migration and its seed: the state the spawn returned with."
  def spawn_completion(context) do
    port = context.isolation.port

    %{
      migrated: Lifecycle.migrated?(port),
      seeded: Enum.map(context.sent_usernames, &{&1, Lifecycle.account?(port, &1)})
    }
  end

  @doc "Whether the first account the spawn listed logs in with the synthetic password."
  def login_seeded(context) do
    {:ok, %{accounts: [username | _rest]}} = context.spawn

    case Lifecycle.login(context.isolation.port, username, Fixtures.password()) do
      {:ok, _port} -> :ok
      :error -> :error
    end
  end

  def leftovers(context), do: Lifecycle.leftovers(context.isolation.port)

  def instance_directories(context), do: context.isolation.port.directories

  # PARTIAL. The model keeps no run base, so it cannot show the run root's files; it answers with the
  # instance's model files, which a drop clears. The integration adapter reads the run base on disk.
  def run_base_database_files(context), do: Lifecycle.database_files(context.isolation.port)

  @doc "The records and chat messages the current instance's database holds."
  def database_contents(context), do: Lifecycle.database_contents(context.isolation.port)

  # Seeding after a spawn, and the testing-control answers. The route's own renderer makes each refusal's
  # status and body, so the unit layer checks the answer a client would read.

  @seed_key "test-seed-once"
  @other_run_id "other-run-id"

  @doc "Given a seeded current instance: spawns one when none is current, then seeds it under the test key."
  def prepare_seeded(context) do
    context =
      if Lifecycle.current(context.isolation.port) do
        context
      else
        context |> choose_instance_id() |> spawn_instance(phase: :flat_primary)
      end

    seed_request(context, :new_key)
  end

  @doc "A scheduler task is running, so a spawn is refused while it runs."
  def hold_scheduler_task(context), do: put_isolation(context, :scheduler_busy, true)

  @doc """
  A seed request under the test key. `:new_key` and `:same_body` send the first seed, `:other_body` another
  seed, and `:not_current` the first seed to an instance that is not current. The answer is the status and
  the body the route gives: a seed that applies or is unchanged answers 200 with `applied`.
  """
  def seed_request(context, mode) do
    port = context.isolation.port

    target =
      if mode == :not_current,
        do: "not-current-instance",
        else: current_id(port) || "no-such-instance"

    seed =
      if mode == :other_body,
        do: Fixtures.accounts_seed(target, ["admin"]),
        else: Fixtures.accounts_seed(target, ["parent"])

    case Lifecycle.seed_current(port, target, @seed_key, seed) do
      {:ok, port, outcome} ->
        context
        |> put_port(port)
        |> put_answer(%{
          status: 200,
          body: %{"seedKey" => @seed_key, "applied" => outcome == :applied},
          sent: [@seed_key, target]
        })
        |> Map.put(:seed_usernames, Fixtures.seeded_usernames(seed))

      {:error, port, reason} ->
        context |> put_port(port) |> put_answer(refusal(reason, [@seed_key, target]))
    end
  end

  @doc """
  A spawn request. `:other_run` presents another run id, which is refused before anything else. `:plain`
  presents the run's own id: a running scheduler task refuses it `instance_busy`, a current instance
  `instance_active`, and otherwise the spawn runs.
  """
  def spawn_request(context, :other_run),
    do: put_answer(context, refusal(:run_mismatch, [@other_run_id]))

  def spawn_request(context, :plain) do
    cond do
      context.isolation[:scheduler_busy] ->
        put_answer(context, refusal(:instance_busy, []))

      Lifecycle.current(context.isolation.port) ->
        put_answer(context, refusal(:instance_active, []))

      true ->
        context
        |> choose_instance_id()
        |> spawn_instance(phase: :flat_primary)
        |> put_answer(%{status: 201, body: %{}, sent: []})
    end
  end

  @doc "Whether the first account of the last seed logs in with the synthetic password."
  def seed_account_login(context) do
    [username | _rest] = context.seed_usernames

    case Lifecycle.login(context.isolation.port, username, Fixtures.password()) do
      {:ok, _port} -> :ok
      :error -> :error
    end
  end

  @doc "How many accounts of the last seed the current instance holds."
  def seed_account_count(context),
    do: Enum.count(context.seed_usernames, &Lifecycle.account?(context.isolation.port, &1))

  defp current_id(port) do
    case Lifecycle.current(port) do
      nil -> nil
      %{instance_id: id} -> id
    end
  end

  defp refusal(reason, sent) do
    {status, body} = ErrorBody.render(reason)
    %{status: status, body: body, sent: sent}
  end

  defp put_answer(context, answer), do: Map.put(context, :isolation_answer, answer)

  defp seed_option(opts) do
    case Keyword.get(opts, :seed) do
      nil -> []
      seed -> [seed: seed]
    end
  end

  # A fresh instance id, seeded with one synthetic admin whose username carries that id's short form.
  defp spawn_with_admin(context) do
    context = choose_instance_id(context)
    seed = Fixtures.accounts_seed(context.isolation.instance_id, ["admin"])
    spawn_instance(context, seed: seed, usernames: Fixtures.seeded_usernames(seed))
  end

  defp port_after_drop({:ok, port}), do: port
  defp port_after_drop({:error, port, :not_current}), do: port

  defp drop_answer(port, id) do
    case Lifecycle.drop(port, id) do
      {:ok, dropped} -> %{port: dropped, status: 204}
      {:error, same, :not_current} -> %{port: same, status: {409, "not_current"}}
    end
  end

  # The guard's request: the peer, the headers, the run secret and the ownership of the runtime.
  defp guard_request(variant) do
    %{
      remote_ip: remote_ip(variant),
      headers: headers(variant),
      secret: Fixtures.secret(),
      runtime_owned?: true,
      instance_id: nil
    }
  end

  defp remote_ip(:non_loopback), do: @outside_peer
  defp remote_ip(_variant), do: @loopback

  defp headers(:no_header), do: [{"accept", "application/json"}]

  defp headers(:wrong_header),
    do: [{"accept", "application/json"}, {Secret.header(), Fixtures.wrong_secret()}]

  defp headers(:forwarded) do
    [
      {"accept", "application/json"},
      {Secret.header(), Fixtures.secret()},
      {"x-forwarded-for", Fixtures.forwarded_ip()}
    ]
  end

  defp headers(:non_loopback),
    do: [{"accept", "application/json"}, {Secret.header(), Fixtures.secret()}]

  # `Guard.admit/2` answers an admitted decision with the connection and a refusal by raising the
  # exception a missing route raises. The rescue at this call site turns that raise into the answer the
  # stock 404 gives, so the refusal is observed, not assumed.
  defp answer(decision) do
    Guard.admit(Plug.Test.conn(:post, @route_prefix <> "/instances"), decision)
    :admitted
  rescue
    error in Phoenix.Router.NoRouteError -> {:raised, error.__struct__}
  end

  defp put_port(context, port), do: put_isolation(context, :port, port)

  defp put_isolation(context, key, value) do
    %{context | isolation: Map.put(context.isolation, key, value)}
  end
end
