defmodule BnestApp.Behaviour.HttpEndpoints.IntegrationAdapter do
  @moduledoc """
  The integration layer's adapter for `http_endpoints.feature`. Where the
  review binds a scenario at integration, it drives the real endpoint over
  the scenario's fresh test instance: liveness through `GET /health/live`
  with the deployment variables set or cleared, theme writes through `PUT
  /preferences/theme` with the scenario session, public files through plain
  `GET`s with no session, and unknown paths with each `accept` header. The
  refused-write scenario swaps in a rejecting preference store through the
  application environment.
  """

  import ExUnit.Assertions
  import Phoenix.ConnTest, only: [build_conn: 0, recycle: 1]

  alias BnestApp.Preferences
  alias BnestAppWeb.Endpoint

  defmodule RejectingStore do
    @moduledoc false

    @behaviour BnestApp.Preferences.Ports.PreferenceStore

    @impl true
    def new, do: %{adapter: __MODULE__}

    @impl true
    def read(_store, _owner_id), do: {:error, :missing}

    @impl true
    def write(_store, _owner_id, _expected_revision, _record), do: {:error, :boom}

    @impl true
    def remove_exact(_store, _owner_id, _expected), do: :ok
  end

  defmodule InvalidRolesStore do
    @moduledoc false

    # Reads every account through the real identity store, but carries the
    # row's roles instead of the stored ones, so the session user the
    # endpoint observes has no usable role while the session itself stays
    # real. The row's roles come from this module's application environment,
    # which the adapter sets beside the adapter swap and restores after.

    @behaviour BnestApp.Identity.Ports.IdentityStore

    alias BnestApp.Identity.Ports.IdentityStore

    @impl true
    def new(records) do
      %{adapter: __MODULE__, real: real_adapter().new(records), roles: roles()}
    end

    @impl true
    def read_account(%{real: real, roles: roles}, user_id) do
      with {:ok, account} <- IdentityStore.read_account(real, user_id),
           do: {:ok, Map.put(account, "roles", roles)}
    end

    @impl true
    def read_username(%{real: real}, username), do: IdentityStore.read_username(real, username)

    @impl true
    def read_session(%{real: real}, digest), do: IdentityStore.read_session(real, digest)

    @impl true
    def read_bootstrap(%{real: real}), do: IdentityStore.read_bootstrap(real)

    @impl true
    def put_account(%{real: real}, account), do: IdentityStore.put_account(real, account)

    @impl true
    def put_username(%{real: real}, index), do: IdentityStore.put_username(real, index)

    @impl true
    def put_session(%{real: real}, session), do: IdentityStore.put_session(real, session)

    @impl true
    def put_bootstrap(%{real: real}, journal), do: IdentityStore.put_bootstrap(real, journal)

    @impl true
    def replace_account(%{real: real}, account), do: IdentityStore.replace_account(real, account)

    @impl true
    def replace_session(%{real: real}, session), do: IdentityStore.replace_session(real, session)

    @impl true
    def replace_bootstrap(%{real: real}, journal),
      do: IdentityStore.replace_bootstrap(real, journal)

    @impl true
    def remove_account(%{real: real}, account), do: IdentityStore.remove_account(real, account)

    @impl true
    def remove_username(%{real: real}, index), do: IdentityStore.remove_username(real, index)

    @impl true
    def remove_bootstrap(%{real: real}, journal),
      do: IdentityStore.remove_bootstrap(real, journal)

    @impl true
    def empty?(%{real: real}), do: IdentityStore.empty?(real)

    @impl true
    def lock_key(%{real: real}), do: IdentityStore.lock_key(real)

    defp real_adapter, do: Application.get_env(:bnest_app, __MODULE__)[:real]
    defp roles, do: Application.get_env(:bnest_app, __MODULE__)[:roles]
  end

  @doc "Installs the HTTP scenario state in the scenario context."
  def install(context) do
    Map.put(context, :http, %{
      conn: context[:conn] || build_conn(),
      owner: owner_from(context),
      liveness: nil,
      revision_header: nil,
      answer: nil,
      statics: %{},
      prefs: Application.fetch_env!(:bnest_app, BnestApp.Preferences)
    })
  end

  @doc "Nothing to release: the scenario context is discarded with the test."
  def release(context), do: context

  # Liveness reports its status, revision, and slot (BN-HTTP-01).

  def set_release(context, "(unset)", "(unset)") do
    delete_environment("BNEST_RELEASE_REVISION")
    delete_environment("BNEST_DEPLOY_SLOT")
    context
  end

  def set_release(context, revision, slot) do
    put_environment("BNEST_RELEASE_REVISION", revision)
    put_environment("BNEST_DEPLOY_SLOT", slot)
    context
  end

  def fetch_liveness(context) do
    {context, answer} = request(context, :get, "/health/live")

    put_http(context, %{
      liveness: Jason.decode!(answer.resp_body),
      revision_header: List.first(Plug.Conn.get_resp_header(answer, "x-bnest-revision"))
    })
  end

  def assert_liveness(context, revision, slot) do
    assert context.http.liveness == %{"status" => "live", "revision" => revision, "slot" => slot}
    context
  end

  def assert_liveness_header(context, reported) do
    assert context.http.revision_header == reported
    context
  end

  # A theme change is saved or refused as invalid (BN-HTTP-10), and refused
  # for a user without write rights or when the store rejects it.

  def sign_in_owner(context), do: context

  def sign_in_roles(context, roles_string) do
    roles = parse_roles(roles_string)
    {previous_identity, real_store} = identity_before_roles_swap()

    Application.put_env(
      :bnest_app,
      BnestApp.Identity,
      Keyword.put(previous_identity, :identity_store, InvalidRolesStore)
    )

    Application.put_env(:bnest_app, InvalidRolesStore, real: real_store, roles: roles)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, BnestApp.Identity, previous_identity)
      Application.delete_env(:bnest_app, InvalidRolesStore)
    end)

    context
  end

  def seed_theme(context, "(none)") do
    assert Preferences.clear_theme(context.http.owner) == :ok
    context
  end

  def seed_theme(context, saved) do
    assert Preferences.put_theme(context.http.owner, saved, DateTime.utc_now()) == :ok
    context
  end

  def set_store(context, "accepts writes") do
    Application.put_env(:bnest_app, BnestApp.Preferences, context.http.prefs)
    context
  end

  def set_store(context, "rejects writes") do
    prefs = Keyword.put(context.http.prefs, :preference_store, RejectingStore)
    Application.put_env(:bnest_app, BnestApp.Preferences, prefs)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bnest_app, BnestApp.Preferences, context.http.prefs)
    end)

    context
  end

  def save_theme(context, "(empty)"), do: save_theme(context, "")

  def save_theme(context, theme) do
    {context, answer} = request(context, :put, "/preferences/theme", %{"theme" => theme})
    put_http(context, %{answer: answer})
  end

  def assert_theme_answer(context, status, "(empty)"),
    do: assert_theme_answer(context, status, "")

  def assert_theme_answer(context, status, body) do
    assert context.http.answer.status == status
    assert context.http.answer.resp_body == body
    context
  end

  def assert_stored_theme(context, expected) do
    assert Preferences.theme(context.http.owner) == expected
    context
  end

  # A public static file is served without signing in (BN-HTTP-23).

  def sign_out(context) do
    put_http(context, %{conn: build_conn()})
  end

  def fetch_static(context, path) do
    answer = build_conn() |> Phoenix.ConnTest.dispatch(Endpoint, :get, path)
    put_http(context, %{answer: answer})
  end

  def assert_static(context, media) do
    answer = context.http.answer
    assert answer.status == 200
    assert answer.resp_body != ""

    assert List.first(Plug.Conn.get_resp_header(answer, "content-type"))
           |> String.starts_with?(media)

    statics = Map.put(context.http.statics, media, answer.resp_body)

    if map_size(statics) == 2 do
      [first, second] = Map.values(statics)
      assert first != second
    end

    put_http(context, %{statics: statics})
  end

  # An unknown path gets the stock not found page, as HTML or JSON (BN-HTTP-24).

  def ask_for(context, media), do: put_http(context, %{media: media})

  def open_unknown_path(context) do
    answer =
      build_conn()
      |> Plug.Conn.put_req_header("accept", context.http.media)
      |> Phoenix.ConnTest.dispatch(Endpoint, :get, "/no/such/page")

    put_http(context, %{answer: answer})
  end

  def assert_unknown_path(context, "HTML") do
    assert context.http.answer.status == 404

    assert List.first(Plug.Conn.get_resp_header(context.http.answer, "content-type"))
           |> String.starts_with?("text/html")

    context
  end

  def assert_unknown_path(context, "JSON") do
    assert context.http.answer.status == 404
    assert %{"errors" => %{"detail" => _detail}} = Jason.decode!(context.http.answer.resp_body)
    context
  end

  def assert_unknown_detail(context, detail) do
    case context.http.media do
      "text/html" ->
        assert context.http.answer.resp_body == detail

      "application/json" ->
        assert Jason.decode!(context.http.answer.resp_body) == %{
                 "errors" => %{"detail" => detail}
               }
    end

    context
  end

  defp request(context, method, path, params \\ nil) do
    answer =
      context.http.conn
      |> recycle()
      |> Phoenix.ConnTest.dispatch(Endpoint, method, path, params)

    {put_http(context, %{conn: answer}), answer}
  end

  defp owner_from(context) do
    (context[:test_identity] && context[:test_identity].user_id) || context[:user_id]
  end

  # A scenario may sign in more than once, so the identity config may already
  # name InvalidRolesStore. Reading it as the real store would make the
  # store wrap itself, so recover the config from before the first swap.
  defp identity_before_roles_swap do
    identity = Application.fetch_env!(:bnest_app, BnestApp.Identity)

    case Keyword.fetch!(identity, :identity_store) do
      InvalidRolesStore ->
        real_store = Application.fetch_env!(:bnest_app, InvalidRolesStore)[:real]
        {Keyword.put(identity, :identity_store, real_store), real_store}

      real_store ->
        {identity, real_store}
    end
  end

  defp parse_roles("(empty)"), do: []
  defp parse_roles("unknown"), do: ["unknown"]
  defp parse_roles("admin"), do: ["admin"]

  defp put_environment(name, value) do
    previous = System.get_env(name)
    System.put_env(name, value)

    ExUnit.Callbacks.on_exit(fn ->
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end)
  end

  defp delete_environment(name) do
    previous = System.get_env(name)
    System.delete_env(name)

    ExUnit.Callbacks.on_exit(fn ->
      if previous, do: System.put_env(name, previous)
    end)
  end

  defp put_http(context, patch), do: %{context | http: Map.merge(context.http, patch)}
end
