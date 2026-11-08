defmodule BnestApp.Test.TestingControlWire do
  @moduledoc """
  Drives the testing-control routes through the real endpoint, the way the TypeScript client does:
  the secret in `x-bnest-testing`, a JSON body, the peer on loopback. Every value is synthetic.

  Headers are appended, never replaced, so a test can send the same header twice. A request built
  here is comparable with a missing route built the same way (`missing_route/3`), which is how the
  guard tests show that a refusal is the stock not-found response.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  import ExUnit.Assertions
  import Phoenix.ConnTest

  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Storage.Records
  alias BnestApp.TestInstance

  @endpoint BnestAppWeb.Endpoint
  @prefix "/__bnest_testing/v1"
  @secret_env "BNEST_TEST_CONTROL_SECRET"
  @secrets_key :testing_control_secrets
  @password "Synthetic!Pass1"

  @doc "The route prefix every testing-control request starts with."
  def prefix, do: @prefix

  @doc "The synthetic password every seeded account uses."
  def password, do: @password

  @doc """
  Sets a fresh random secret in the environment, as the runner does, and returns it. Every secret the run
  generates is kept in the application environment, so the end-of-run check can look for each of them on disk.
  """
  def put_secret! do
    secret = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    System.put_env(@secret_env, secret)
    Application.put_env(:bnest_app, @secrets_key, [secret | secrets()])
    secret
  end

  @doc "Every run secret this run has generated, for the end-of-run check that no file holds one."
  def secrets, do: Application.get_env(:bnest_app, @secrets_key, [])

  @doc "Unsets the secret, so the control is closed."
  def clear_secret!, do: System.delete_env(@secret_env)

  @doc """
  The headers a well-formed client sends: `accept`, and the secret header when the environment
  holds a secret. A test that needs a different header list builds its own.
  """
  def default_headers do
    case System.get_env(@secret_env) do
      nil -> [{"accept", "application/json"}]
      secret -> [{"accept", "application/json"}, {"x-bnest-testing", secret}]
    end
  end

  @doc """
  Sends one request through the endpoint.

  A map `body` is sent as JSON with `content-type: application/json` unless a content type is
  already among the headers. A binary `body` is sent raw and needs its own content-type header.
  Options:

    * `:headers` (default: `default_headers/0`)
    * `:remote_ip` (default: the test adapter's loopback peer)
  """
  def send_request(method, path, body \\ nil, opts \\ []) do
    headers = Keyword.get_lazy(opts, :headers, &default_headers/0)

    conn =
      headers
      |> Enum.reduce(build_conn(), &append_header/2)
      |> put_peer(Keyword.get(opts, :remote_ip))

    case body do
      nil ->
        dispatch_answered(conn, method, path, nil)

      raw when is_binary(raw) ->
        dispatch_answered(conn, method, path, raw)

      map when is_map(map) ->
        dispatch_answered(with_json_type(conn), method, path, Jason.encode!(map))
    end
  end

  # An error the endpoint renders (a refused guard, a malformed body) is re-raised by ConnTest after
  # its response is sent to this process. The response is taken from the mailbox, so the caller sees
  # the same conn an answered request gives. Earlier answers are drained first, so only this
  # request's response can be taken.
  defp dispatch_answered(conn, method, path, body) do
    discard_sent()

    try do
      dispatch(conn, @endpoint, method, path, body)
    rescue
      error ->
        case take_sent() do
          {status, headers, resp_body} ->
            %Plug.Conn{status: status, resp_headers: headers, resp_body: resp_body}

          nil ->
            reraise error, __STACKTRACE__
        end
    end
  end

  defp discard_sent do
    receive do
      {ref, _answer} when is_reference(ref) -> discard_sent()
    after
      0 -> :ok
    end
  end

  defp take_sent do
    receive do
      {ref, {status, headers, body}} when is_reference(ref) -> {status, headers, body}
    after
      0 -> nil
    end
  end

  @doc "Sends the same request to a route that does not exist, with the same headers and body."
  def missing_route(method, body \\ nil, opts \\ []) do
    method |> send_request(@prefix <> "/no-such-route", body, opts) |> summary()
  end

  @doc "The status, content type and body of a response: the parts a missing route also has."
  def summary(conn), do: {conn.status, response_header(conn, "content-type"), conn.resp_body}

  @doc "The response body, decoded."
  def json(conn), do: Jason.decode!(conn.resp_body)

  @doc "The first value of a response header, or nil."
  def response_header(conn, name) do
    case Plug.Conn.get_resp_header(conn, name) do
      [value | _rest] -> value
      [] -> nil
    end
  end

  @doc """
  Everything a refused request must leave alone: the current instance, its directories, the
  storage pointer, the settings a switch changes, the backup configuration and the Records store.
  """
  def snapshot do
    run = TestInstance.application_run!()

    %{
      instance: TestInstance.info(),
      audit: TestInstance.audit(),
      base_audit: TestInstance.base_audit(),
      pointer: pointer_bytes(),
      runtime_root: Application.fetch_env(:bnest_app, :runtime_root),
      backup_repository_root: Application.fetch_env(:bnest_app, :backup_repository_root),
      backup_config_present:
        File.exists?(Path.join([run.sqlite_path, "storage-config", "backup.json"])),
      records_store: :sys.get_state(Records).store
    }
  end

  @doc "Drops the current instance, if any, and clears the wire state a test may have changed."
  def cleanup! do
    run = TestInstance.application_run!()

    case TestInstance.state() do
      nil -> :ok
      instance -> :ok = TestInstance.drop!(instance)
    end

    File.rm(Path.join([run.sqlite_path, "storage-config", "backup.json"]))
    clear_secret!()
    Application.delete_env(:bnest_app, :testing_control_fail_after)
    :ok
  end

  @doc "The synthetic account usernames of an instance, which carry its short id."
  def usernames(instance_id) do
    short = String.slice(instance_id, 0, 8)
    {"test-user-#{short}-admin", "test-user-#{short}-parent"}
  end

  @doc "The account seed an instance's admin and parent need, with synthetic passwords."
  def account_seed(instance_id) do
    {admin, parent} = usernames(instance_id)

    %{
      "accounts" => [
        %{"username" => admin, "password" => @password, "roles" => ["admin", "parents"]},
        %{"username" => parent, "password" => @password, "roles" => ["parents"]}
      ]
    }
  end

  @doc "Asserts a response is the stock not-found response, the same one a missing route gets."
  def assert_not_found(conn, missing) do
    assert summary(conn) == missing
    assert conn.status == 404
  end

  @doc "Asserts the stock JSON not-found body, for a request that asks for JSON."
  def assert_json_not_found(conn) do
    assert conn.status == 404
    assert json(conn) == %{"errors" => %{"detail" => "Not Found"}}
  end

  defp append_header({name, value}, conn),
    do: %{conn | req_headers: conn.req_headers ++ [{name, value}]}

  defp put_peer(conn, nil), do: conn
  defp put_peer(conn, ip), do: %{conn | remote_ip: ip}

  defp with_json_type(conn) do
    if Enum.any?(conn.req_headers, &match?({"content-type", _value}, &1)),
      do: conn,
      else: append_header({"content-type", "application/json"}, conn)
  end

  defp pointer_bytes do
    case File.read(FileConfigStore.pointer_path()) do
      {:ok, bytes} -> bytes
      {:error, :enoent} -> nil
    end
  end
end
