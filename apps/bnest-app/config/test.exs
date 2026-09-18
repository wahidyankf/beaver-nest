import Config

config :bnest_app, :identity_cutover_enabled, true
config :bnest_app, :scheduler_automatic?, false
# On by default in test so unit/integration drivers can exercise the room
# route/navigation without per-test overrides; the specific "flag genuinely
# off" checkpoint scenario overrides this locally via
# `Application.put_env/3` + `on_exit/1` (the same pattern used for other
# per-test config overrides in this suite, e.g.
# `test/integration/bnest_app_web/authentication_test.exs`).
config :bnest_app, :family_chat_enabled, true

# Fixed synthetic VAPID keypair (never a real deployment secret -- generated
# once via `WebPush.Vapid.generate_keypair/0` and hardcoded here so test
# runs are deterministic/reproducible). `push_notifications_test_provider?`
# additionally allowlists the synthetic `push.allowed.example.com` provider
# host so subscription-validation tests can use an https/allowlisted-shaped
# endpoint without ever dialing a real Apple/Mozilla/Chromium provider.
config :web_push, :vapid,
  public_key:
    "BPGxd0fDWxgSZ-Xx3woJ2NshVgXsIIZp3Y1kPEcR8tM3_MBfPIJRJmH8unEa3SWfcgTIdhWOT95xw6poaIffyuI",
  private_key: "172QFip6G1cnH9jJ4ZCrCGNq33f6UFgjIe2MWzvsUlU",
  subject: "mailto:test@example.com"

config :bnest_app, :push_notifications_test_provider?, true

config :bnest_app, :storage_profile, {:test, System.get_env("BNEST_TEST_RUN_ID")}

if System.get_env("BNEST_TEST_LAYER") == "integration" do
  run_id =
    System.get_env("BNEST_TEST_RUN_ID") ||
      "mix-" <>
        (:crypto.strong_rand_bytes(8)
         |> Base.url_encode64(padding: false)
         |> String.downcase())

  runtime_root =
    System.get_env("BNEST_RUNTIME_ROOT") ||
      Path.expand("../../../data/test/runs/#{run_id}", __DIR__)

  sqlite_root = Path.expand("~/bnest/data/test/runs/#{run_id}")
  flat_runs_root = Path.expand("../../../data/test/runs", __DIR__)
  sqlite_runs_root = Path.expand("~/bnest/data/test/runs")

  # Test config runs before application modules are available. Enforce the same
  # exact-child invariant here before creating or writing either runtime root.
  Enum.each(
    [{runtime_root, flat_runs_root}, {sqlite_root, sqlite_runs_root}],
    fn {candidate, parent} ->
      candidate = Path.expand(candidate)

      if Path.dirname(candidate) != parent or Path.basename(candidate) != run_id or
           candidate == parent do
        raise "test runtime must be one run-id child of its dedicated test root"
      end

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :symlink}} ->
          raise "test runtime cannot be a symlink"

        {:ok, %File.Stat{type: :directory}} ->
          marker_path = Path.join(candidate, ".bnest-test-run.json")

          marker =
            case File.read(marker_path) do
              {:ok, bytes} -> JSON.decode!(bytes)
              {:error, _reason} -> raise "existing test runtime has no readable marker"
            end

          if marker["schemaVersion"] != 1 or marker["recordType"] != "bnest-test-run" or
               marker["runId"] != run_id or marker["owner"] != "bnest-test-harness" do
            raise "existing test runtime marker is invalid"
          end

        {:ok, _not_directory} ->
          raise "test runtime must be a directory"

        _not_symlink ->
          :ok
      end
    end
  )

  marker = %{
    "schemaVersion" => 1,
    "recordType" => "bnest-test-run",
    "runId" => Path.basename(runtime_root),
    "createdAt" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
    "owner" => "bnest-test-harness"
  }

  Enum.each(~w(general apps/beaver-nest system users), fn relative ->
    File.mkdir_p!(Path.join(runtime_root, relative))
  end)

  File.mkdir_p!(sqlite_root)

  marker =
    marker
    |> Map.put("pid", System.pid())
    |> Map.put(
      "hostname",
      case :inet.gethostname() do
        {:ok, hostname} -> List.to_string(hostname)
        {:error, _reason} -> "local"
      end
    )

  encoded_marker = JSON.encode!(marker)
  File.write!(Path.join(runtime_root, ".bnest-test-run.json"), encoded_marker)
  File.write!(Path.join(sqlite_root, ".bnest-test-run.json"), encoded_marker)

  config :bnest_app,
    runtime_root: runtime_root,
    test_sqlite_root: sqlite_root,
    storage_config_path: Path.join(runtime_root, "storage-config/storage.json"),
    test_runtime_owned: true

  config :bnest_app, storage_profile: {:test, run_id}
else
  config :bnest_app,
    runtime_root: nil,
    test_sqlite_root: nil,
    storage_config_path: nil,
    test_runtime_owned: false
end

# Family Chat's SQLite tables are additive to the shared database but must never
# resolve through the real `~/.config/bnest/storage.json` pointer during tests (that
# file is shared/production-adjacent). Every test run (unit or integration) gets its
# own isolated SQLite path here; `BnestApp.FamilyChat.Store` self-heals the connection
# onto this path before each operation, independent of the legacy flat/sqlite phase.
family_chat_run_id =
  System.get_env("BNEST_TEST_RUN_ID") ||
    "unit-" <>
      (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false) |> String.downcase())

config :bnest_app,
  family_chat_sqlite_path:
    Path.expand("~/bnest/data/test/family-chat/#{family_chat_run_id}/bnest.sqlite3")

codex_session =
  if System.get_env("BNEST_CODEX_RUNNER"),
    do: BnestApp.Codex.PortSession,
    else: BnestApp.Codex.FixtureSession

config :bnest_app, :codex_session, codex_session
config :bnest_app, :codex_models, BnestApp.Codex.FixtureModels

config :argon2_elixir,
  argon2_type: 2,
  m_cost: 8,
  t_cost: 1,
  parallelism: 1

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bnest_app, BnestAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "T0v3TGsG47MqIa6FIYGgWKEDFQxeD58eLszvlCUH8KFhGJXBH6hQLPe7dYY7nKju",
  server: false

# In test we don't send emails
config :bnest_app, BnestApp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
