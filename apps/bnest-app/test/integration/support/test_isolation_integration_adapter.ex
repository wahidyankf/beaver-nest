defmodule BnestApp.Behaviour.TestIsolation.IntegrationAdapter do
  @moduledoc """
  The integration layer's adapter for `test_isolation.feature` (ADR 001, sections 1 to 4). It runs the real
  switch (`BnestApp.TestInstance`), the real seed facades, the real storage pointer and SQLite repo, and the
  real endpoint through `BnestApp.Test.TestingControlWire`. "A test" acts in process (`TestInstance`); "a
  client" acts over the wire, as the TypeScript client does.

  Only the scenarios that the integration layer runs call these functions. The production-build scenario is
  `@integration-exempt`, so no function here exists for it, and an accidental call fails.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  import Phoenix.ConnTest

  alias BnestApp.Behaviour.TestIsolation.Fixtures
  alias BnestApp.Identity
  alias BnestApp.Identity.Ports.IdentityStore
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage
  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Test.MigrationFiles
  alias BnestApp.Test.ReleaseSchema
  alias BnestApp.Test.TestingControlWire, as: Wire
  alias BnestApp.TestInstance
  alias BnestApp.TestInstance.Paths
  alias BnestAppWeb.TestingControl.Secret

  @endpoint BnestAppWeb.Endpoint
  @outside_peer {203, 0, 113, 9}

  @doc """
  Installs the adapter for a scenario and the run secret the wire needs. The release hook drops whatever
  the scenario left current, so no instance outlives its scenario.
  """
  def prepare(context) do
    Wire.put_secret!()

    context
    |> Map.put(:isolation_adapter, __MODULE__)
    |> Map.put(:isolation, %{instance_id: nil, fail_after: nil})
  end

  @doc """
  Clears the wire state and the run secret. The current instance is dropped by the fresh-database hook in
  `test/behaviour/support/integration.exs`, which runs for every integration scenario.
  """
  def release(context) do
    Wire.cleanup!()
    context
  end

  @doc "The current instance's id and generation in this process, or nil."
  def current(_context) do
    case TestInstance.state() do
      nil -> nil
      instance -> %{instance_id: instance.instance_id, generation: instance.paths.generation}
    end
  end

  @doc "What `GET /state` reports as the current instance."
  def server_state(_context) do
    %{"instance" => instance} = Wire.json(Wire.send_request(:get, Wire.prefix() <> "/state"))

    case instance do
      nil ->
        nil

      %{"instanceId" => id, "generation" => generation} ->
        %{instance_id: id, generation: generation}
    end
  end

  def choose_instance_id(context),
    do: put_isolation(context, :instance_id, Fixtures.new_instance_id())

  def inject_failure(context, step), do: put_isolation(context, :fail_after, step)

  @doc """
  Spawns through `TestInstance.spawn!/2`. `opts`: `:phase`, `:seed` (a seed map), and `:usernames` (the
  usernames the seed sends). A refusal or failure is answered as data, with its step and, for a seed,
  the invalid field.
  """
  def spawn_instance(context, opts) do
    run = TestInstance.application_run!()

    spawn_opts =
      [
        instance_id: context.isolation.instance_id,
        label: "isolation",
        phase: Keyword.get(opts, :phase, :sqlite_primary),
        fail_after: context.isolation.fail_after
      ] ++ seed_option(opts)

    observed =
      try do
        {:ok, observe_spawn(TestInstance.spawn!(run, spawn_opts))}
      rescue
        error in TestInstance.Error -> {:error, refusal(error)}
      end

    context
    |> Map.put(:spawn, observed)
    |> Map.put(:sent_usernames, Keyword.get(opts, :usernames, []))
  end

  @doc "The previous test ends: its instance is dropped and the next test chooses its own id."
  def end_test(context) do
    case TestInstance.state() do
      nil -> :ok
      instance -> :ok = TestInstance.drop!(instance)
    end

    context
    |> Map.put(:previous_spawn, Map.get(context, :spawn))
    |> put_isolation(:instance_id, nil)
  end

  @doc "Deletes the current instance over the wire, then deletes it again. Answers the two statuses."
  def delete_current(context) do
    path = Wire.prefix() <> "/instances/" <> context.isolation.instance_id
    first = Wire.send_request(:delete, path)
    again = Wire.send_request(:delete, path)

    Map.put(context, :delete, %{first: first.status, again: {again.status, error_code(again)}})
  end

  @doc """
  A client's create request under one variant: `:no_header`, `:wrong_header`, `:forwarded` or
  `:non_loopback`. It is sent over the wire, and the same request to a missing route is recorded for
  comparison.
  """
  def create_request(context, variant) do
    run = TestInstance.application_run!()
    body = %{"runId" => run.run_id, "label" => "isolation"}
    opts = request_opts(variant)

    conn = Wire.send_request(:post, Wire.prefix() <> "/instances", body, opts)

    Map.put(context, :request, %{
      response: Wire.summary(conn),
      missing: Wire.missing_route(:post, body, opts),
      status: conn.status
    })
  end

  def setup_open?(_context), do: get(build_conn(), "/setup").status == 200

  def account_present?(_context, username) do
    store = Identity.adapter(:identity_store).new(Storage.active_store())
    match?({:ok, _record}, IdentityStore.read_username(store, username))
  end

  def readiness_generation(_context) do
    json_response(get(build_conn(), "/health/ready"), 200)["storageGeneration"]
  end

  @doc """
  The schema of the current instance, observed and then dropped, then the release database built and
  measured, so only one database is ever current. The comparison names both fingerprints and the migration
  files the versions must equal.
  """
  def compare_release_schema(context) do
    run = TestInstance.application_run!()
    instance = ReleaseSchema.observe()
    :ok = TestInstance.drop!(TestInstance.state())

    Map.put(context, :comparison, %{
      instance: instance,
      release: ReleaseSchema.with_release_build(run, &ReleaseSchema.observe/0),
      files: MigrationFiles.versions()
    })
  end

  @doc "The instance's schema fingerprint equals the release build's fingerprint."
  def schema_identical?(%{comparison: comparison}),
    do: comparison.instance.fingerprint == comparison.release.fingerprint

  @doc "Both databases hold exactly the committed migration files' versions, in order."
  def versions_exact?(%{comparison: comparison}) do
    comparison.instance.versions == comparison.files and
      comparison.release.versions == comparison.files
  end

  @doc "Whether the spawn finished its migrations and its seed: the state it returned with."
  def spawn_completion(context) do
    %{
      migrated: ReleaseSchema.applied_versions() == MigrationFiles.versions(),
      seeded: Enum.map(context.sent_usernames, &{&1, account_present?(context, &1)})
    }
  end

  @doc "Logs in as the first account the spawn listed, through the production login route."
  def login_seeded(context) do
    {:ok, %{accounts: [username | _rest]}} = context.spawn
    login(username, Fixtures.password())
  end

  @doc """
  The approved admin that `test_instances.feature` starts from: a fresh instance seeded with one admin, and
  that admin logged in through the production login route. A login the route refuses fails the Given.
  """
  def establish_admin(context) do
    context = spawn_with_admin(context)
    {:ok, %{accounts: [username]}} = context.spawn
    password = Fixtures.password()

    case login(username, password) do
      :ok ->
        Map.put(context, :previous_admin, %{username: username, password: password})

      :error ->
        raise "the approved admin cannot log in to its own instance"
    end
  end

  @doc """
  Replaces the current instance: the current one is dropped, then a fresh instance seeded with its own admin
  is spawned. The dropped spawn is kept as `previous_spawn`, and the previous admin's credentials stay in the
  context for the refusal check.
  """
  def replace_instance(context), do: context |> end_test() |> spawn_with_admin()

  @doc """
  Presents the previous admin's credentials to the production login route: `:ok` when it opens a session,
  `:error` when it refuses (a refusal redirects back to the login page with no identity cookie).
  """
  def login_as_previous_admin(context) do
    %{username: username, password: password} = context.previous_admin
    login(username, password)
  end

  @doc "The instance directories, the storage pointer and the backup configuration that still name the instance."
  def leftovers(context) do
    paths = instance_paths(context)

    [paths.sqlite_instance_root, paths.flat_instance_root, paths.backup_config_path]
    |> Enum.filter(&File.exists?/1)
    |> Kernel.++(pointer_leftovers(paths))
  end

  def instance_directories(context) do
    paths = instance_paths(context)

    [paths.sqlite_instance_root, paths.flat_instance_root]
    |> Enum.filter(&File.dir?/1)
  end

  @doc """
  The SQLite files this instance left behind: its database file and any `*.sqlite3*` under its SQLite root.
  The run root's shared base database (`bnest.sqlite3`) is not counted, because the existing scenarios still
  use it until the fresh-database migration (T9b). So this proves the instance's teardown, not an empty run root.
  """
  def instance_database_files(context) do
    paths = instance_paths(context)

    [paths.db_file | Path.wildcard(Path.join(paths.sqlite_instance_root, "**/*.sqlite3*"))]
    |> Enum.filter(&File.exists?/1)
    |> Enum.uniq()
  end

  @doc "The rows the current database holds in its record and Family Chat message tables."
  def database_contents(_context) do
    %{rows: [[records]]} = SqliteRepo.query!("SELECT count(*) FROM bnest_records")
    %{rows: [[messages]]} = SqliteRepo.query!("SELECT count(*) FROM family_chat_messages")
    %{records: records, chat_messages: messages}
  end

  # Helpers

  defp observe_spawn(instance) do
    {:ok, registry} = TestInstance.seed_registry(instance)

    accounts =
      registry
      |> Map.get(:keys, %{})
      |> Map.get("spawn", %{})
      |> Map.get(:accounts, [])

    %{
      instance_id: instance.instance_id,
      generation: instance.paths.generation,
      phase: instance.phase,
      accounts: Enum.map(accounts, & &1.username)
    }
  end

  defp refusal(%TestInstance.Error{reason: reason, step: step, detail: detail}) do
    %{reason: reason, step: step, invalid: invalid(detail)}
  end

  defp invalid(%{code: :seed_invalid, reason: reason, path: path}),
    do: %{reason: reason, path: path}

  defp invalid(_detail), do: nil

  defp seed_option(opts) do
    case Keyword.get(opts, :seed) do
      nil -> []
      seed -> [seed: {"spawn", seed}]
    end
  end

  # A fresh instance id, seeded with one synthetic admin whose username carries that id's short form.
  defp spawn_with_admin(context) do
    context = choose_instance_id(context)
    seed = Fixtures.accounts_seed(context.isolation.instance_id, ["admin"])
    spawn_instance(context, seed: seed, usernames: Fixtures.seeded_usernames(seed))
  end

  # The production route answers a valid login with a redirect to "/" and the identity cookie, and a
  # refused one with a redirect back to "/login" and no cookie.
  defp login(username, password) do
    conn =
      build_conn()
      |> post("/login", %{"login" => %{"username" => username, "password" => password}})

    if conn.status == 302 and Plug.Conn.get_resp_header(conn, "location") == ["/"] and
         Map.has_key?(conn.resp_cookies, "_bnest_identity"),
       do: :ok,
       else: :error
  end

  defp request_opts(:no_header), do: [headers: [{"accept", "application/json"}]]

  defp request_opts(:wrong_header) do
    [
      headers: [
        {"accept", "application/json"},
        {Secret.header(), Fixtures.wrong_secret()}
      ]
    ]
  end

  defp request_opts(:forwarded) do
    [headers: Wire.default_headers() ++ [{"x-forwarded-for", Fixtures.forwarded_ip()}]]
  end

  defp request_opts(:non_loopback),
    do: [headers: Wire.default_headers(), remote_ip: @outside_peer]

  defp error_code(conn) do
    case Jason.decode(conn.resp_body) do
      {:ok, %{"error" => %{"code" => code}}} -> code
      _other -> nil
    end
  end

  defp instance_paths(context) do
    run = TestInstance.application_run!()

    {:ok, paths} =
      Paths.derive(run.path, run.sqlite_path, run.run_id, context.isolation.instance_id)

    paths
  end

  # The storage pointer names an instance by its generation, so a pointer that still names this instance
  # is a leftover of it.
  defp pointer_leftovers(paths) do
    pointer = FileConfigStore.pointer_path()

    case File.read(pointer) do
      {:ok, bytes} -> if String.contains?(bytes, paths.generation), do: [pointer], else: []
      {:error, _reason} -> []
    end
  end

  defp put_isolation(context, key, value) do
    %{context | isolation: Map.put(context.isolation, key, value)}
  end
end
