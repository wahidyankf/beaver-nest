defmodule BnestApp.Test.BehaviourEvidence do
  @moduledoc """
  Evidence both behaviour drivers gather the same way: the initial-account submissions, the
  log captured around a request, a cross-user operation attempted through the guard a
  request handler applies, and the storage UI visits counted from router and LiveView
  telemetry. Each driver supplies its own stores and request path.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  require Logger

  alias BnestApp.Identity
  alias BnestApp.Identity.{Bootstrap, Login}
  alias BnestApp.Preferences

  @missing_requirement_passwords ["password_", "password1", "123_"]

  @doc """
  Submits each password missing a letter, number or punctuation mark as its own initial
  administrator first, keeping the result and the bootstrap status after it; then submits
  the real accounts twice, with a three-character and a 131-character password, and logs
  each one in. Returns `{rejections, first_result, second_result, logins}`.
  """
  def submit_initial_accounts(store) do
    rejections =
      Enum.map(@missing_requirement_passwords, fn password ->
        result =
          Bootstrap.create(store, [
            %{
              "username" => "test-user-family-admin",
              "password" => password,
              "roles" => ["admin"]
            }
          ])

        {password, result, Bootstrap.status(store)}
      end)

    accounts = [
      %{"username" => "test-user-family-admin", "password" => "a_1", "roles" => ["admin"]},
      %{
        "username" => "test-user-family-child",
        "password" => String.duplicate("é", 129) <> "_1",
        "roles" => ["children"]
      }
    ]

    first_result = Bootstrap.create(store, accounts)
    second_result = Bootstrap.create(store, accounts)
    logins = Enum.map(accounts, &Login.authenticate(store, &1["username"], &1["password"]))
    {rejections, first_result, second_result, logins}
  end

  @doc "Both real accounts were created and each logs in with its short or long password."
  def accepted_any_length?(context) do
    match?({:ok, [_admin, _child]}, context.bootstrap_first_result) and
      length(context.bootstrap_logins) == 2 and
      Enum.all?(context.bootstrap_logins, &match?({:ok, _token}, &1))
  end

  @doc "Every incomplete password was refused as invalid and left setup open."
  def rejected_each_missing_requirement?(rejections) do
    Enum.map(rejections, &elem(&1, 0)) == @missing_requirement_passwords and
      Enum.all?(rejections, fn {_password, result, status} ->
        result == {:error, :invalid_password} and status == :open
      end)
  end

  @doc """
  Runs `fun` with the logger at debug level and every log line captured, then restores the
  level. A process level cannot be more verbose than the configured one, so the level is
  global while `fun` runs. Returns `{result, log}`.
  """
  def with_debug_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :debug)

    try do
      ExUnit.CaptureLog.with_log([level: :debug], fun)
    after
      Logger.configure(level: previous)
    end
  end

  @doc """
  The first user's theme read and write aimed at `owner_id`, each run only when the guard a
  request handler applies allows it. Returns `[read_theme: outcome, write_theme: outcome]`.
  """
  def cross_user_theme_attempts(user, owner_id) do
    [
      read_theme: guarded(user, :read_theme, owner_id, fn -> Preferences.theme(owner_id) end),
      write_theme:
        guarded(user, :write_theme, owner_id, fn ->
          Preferences.put_theme(owner_id, "light", DateTime.utc_now())
        end)
    ]
  end

  @doc """
  Counts every request routed to the storage UI and every mount of its LiveView from now
  until the test ends, so an action's effect on the count is observed rather than assumed.
  Returns the counter.
  """
  def watch_storage_ui_visits do
    # `mix test --no-start` leaves the handler table unstarted on the unit layer.
    {:ok, _apps} = Application.ensure_all_started(:telemetry)
    visits = :counters.new(1, [])

    handler =
      "bnest-behaviour-storage-ui-" <> Integer.to_string(System.unique_integer([:positive]))

    :ok =
      :telemetry.attach_many(
        handler,
        [[:phoenix, :router_dispatch, :start], [:phoenix, :live_view, :mount, :start]],
        &__MODULE__.count_storage_ui_visit/4,
        visits
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler) end)
    visits
  end

  @doc false
  def count_storage_ui_visit(_event, _measurements, metadata, visits) do
    if storage_ui_visit?(metadata), do: :counters.add(visits, 1, 1)
    :ok
  end

  defp storage_ui_visit?(%{conn: %Plug.Conn{request_path: "/storage" <> _rest}}), do: true
  defp storage_ui_visit?(%{socket: %{view: BnestAppWeb.StorageLive}}), do: true
  defp storage_ui_visit?(_metadata), do: false

  defp guarded(user, capability, owner_id, operation) do
    if Identity.authorize(user, capability, owner_id) do
      operation.()
      :performed
    else
      :denied
    end
  end
end
