defmodule BnestAppWeb.TestingControl.Guard do
  @moduledoc """
  The guards every testing-control request passes before its route runs (ADR 001, section 2), in
  the order the record gives:

    1. (compile time) the routes exist only in the test build, see `BnestAppWeb.TestingRoutes`.
    2. the peer is loopback (`127.0.0.1` or `::1`) and the request carries no forwarding header, so
       a request that came through Caddy is refused.
    3. the test run owns the runtime: `:test_runtime_owned` is true and both run roots validate.
    4. the `x-bnest-testing` header holds the run secret, see `BnestAppWeb.TestingControl.Secret`.
    5. the `:id` in the path, when there is one, is 16 lowercase hex characters. Whether it is the
       current instance is the controller's answer (`not_current`), not a guard.

  Any refusal raises `Phoenix.Router.NoRouteError`, the error a missing route raises. The endpoint
  renders that error with the same `ErrorJSON` answer, and nothing else runs, so a refused request
  is answered exactly as a missing route is and changes nothing. The reason is never logged or
  rendered.

  The plug is the first plug of the `:testing_control` pipeline, before `accepts`, so a refused
  request never gets a 406 for its `Accept` header first.

  `decide/1` is pure. It takes the peer, the headers, the secret, the ownership of the runtime and
  the instance id, so the guard's rules can be tested without a connection.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @behaviour Plug

  alias BnestApp.TestRuntimeRoot
  alias BnestAppWeb.TestingControl.Secret

  @loopback [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]
  @forwarding_headers ~w(x-forwarded-for x-forwarded-host x-forwarded-proto forwarded x-real-ip)
  @instance_id_pattern ~r/\A[a-z0-9]{16}\z/

  @type request :: %{
          required(:remote_ip) => :inet.ip_address(),
          required(:headers) => [{String.t(), String.t()}],
          required(:secret) => String.t() | nil,
          required(:runtime_owned?) => boolean(),
          optional(:instance_id) => String.t() | nil
        }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    request = %{
      remote_ip: conn.remote_ip,
      headers: conn.req_headers,
      secret: System.get_env(Secret.env_name()),
      runtime_owned?: runtime_owned?(),
      instance_id: conn.path_params["id"]
    }

    admit(conn, decide(request))
  end

  @doc "Applies a decision to the connection: an admitted request goes on, a refusal raises."
  @spec admit(Plug.Conn.t(), :ok | {:error, atom()}) :: Plug.Conn.t()
  def admit(conn, :ok), do: conn

  def admit(conn, {:error, _reason}),
    do: raise(Phoenix.Router.NoRouteError, conn: conn, router: BnestAppWeb.Router)

  @doc "The guard decision for one request. Pure: nothing is read from the environment or disk."
  @spec decide(request()) ::
          :ok
          | {:error,
             :not_loopback
             | :forwarded
             | :runtime_not_owned
             | :bad_instance_id
             | :secret_unset
             | :secret_short
             | :header_missing
             | :header_repeated
             | :header_mismatch}
  def decide(%{remote_ip: ip, headers: headers} = request) do
    with :ok <- peer(ip, headers),
         :ok <- owned(request.runtime_owned?),
         :ok <- Secret.check(secret_values(headers), request.secret) do
      instance_id(Map.get(request, :instance_id))
    end
  end

  @doc """
  Whether the test run owns the runtime the application runs on: the flat and SQLite run roots
  validate with markers naming the same run. A missing run, a run whose markers do not validate and
  an application that is not a test run all answer false. Reads only the marker files.
  """
  @spec runtime_owned?() :: boolean()
  def runtime_owned? do
    owned_by?(
      Application.get_env(:bnest_app, :test_runtime_owned),
      Application.get_env(:bnest_app, :runtime_root),
      Application.get_env(:bnest_app, :test_sqlite_root)
    )
  end

  @doc """
  The ownership rule on the configuration values, so the rule can be tested without setting the
  application environment. Both roots must be paths, and both must validate with the same run id.
  """
  @spec owned_by?(term(), term(), term()) :: boolean()
  def owned_by?(true, flat, sqlite) when is_binary(flat) and is_binary(sqlite),
    do: same_run?(TestRuntimeRoot.validate(flat), TestRuntimeRoot.validate_sqlite(sqlite))

  def owned_by?(_flag, _flat, _sqlite), do: false

  @doc "Whether two root validations are both ok and name the same run."
  @spec same_run?(term(), term()) :: boolean()
  def same_run?({:ok, %{run_id: run_id}}, {:ok, %{run_id: run_id}}), do: true
  def same_run?(_flat, _sqlite), do: false

  # Loopback first, then the proxy headers: a forwarded request is refused even from loopback.
  defp peer(ip, headers) do
    cond do
      ip not in @loopback ->
        {:error, :not_loopback}

      Enum.any?(headers, fn {name, _value} -> name in @forwarding_headers end) ->
        {:error, :forwarded}

      true ->
        :ok
    end
  end

  defp owned(true), do: :ok
  defp owned(_runtime_not_owned), do: {:error, :runtime_not_owned}

  defp secret_values(headers) do
    for {name, value} <- headers, name == Secret.header(), do: value
  end

  defp instance_id(nil), do: :ok

  defp instance_id(id) when is_binary(id) do
    if Regex.match?(@instance_id_pattern, id), do: :ok, else: {:error, :bad_instance_id}
  end
end
