defmodule BnestApp.Behaviour.HttpEndpoints.UnitAdapter do
  @moduledoc """
  The unit layer's adapter for `http_endpoints.feature`. It drives the
  production facades and controllers over the in-memory doubles: liveness
  over the in-memory release environment, theme writes through
  `ThemeController` over the record repository started on an in-memory
  backend, static files through `Plug.Static` over `Plug.Test`, and the
  stock error pages through their render functions. Only the integration
  adapter reaches the endpoint.
  """

  import ExUnit.Assertions
  import Plug.Conn
  import Plug.Test

  alias BnestApp.Operations
  alias BnestApp.Preferences
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.ReleaseEnvironment
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestAppWeb.ErrorHTML
  alias BnestAppWeb.ErrorJSON
  alias BnestAppWeb.ReleaseHeaders
  alias BnestAppWeb.ThemeController

  @owner "test-user-http-endpoints-owner"

  # The unit layer's fixed clock: seeded theme stamps never read the system
  # clock, matching the `@behaviour_now` seam the sibling unit drivers use.
  @behaviour_now ~U[2026-09-04 12:00:00Z]

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

  @doc "Installs the HTTP scenario state in the scenario context."
  def install(context) do
    ReleaseEnvironment.install()
    install_storage_once()

    Map.put(context, :http, %{
      owner: @owner,
      user: nil,
      liveness: nil,
      revision_header: nil,
      answer: nil,
      statics: %{},
      error: nil,
      prefs: Application.fetch_env!(:bnest_app, BnestApp.Preferences)
    })
  end

  @doc "Nothing to release: the scenario context is discarded with the test."
  def release(context), do: context

  # Liveness reports its status, revision, and slot (BN-HTTP-01).

  def set_release(context, revision, slot) do
    if revision != "(unset)", do: ReleaseEnvironment.put_revision(release(), revision)
    if slot != "(unset)", do: ReleaseEnvironment.put_slot(release(), slot)
    context
  end

  def fetch_liveness(context) do
    {:ok, liveness} = Operations.liveness()

    header =
      conn(:get, "/health/live")
      |> ReleaseHeaders.call(ReleaseHeaders.init([]))
      |> get_resp_header("x-bnest-revision")
      |> List.first()

    put_http(context, %{liveness: liveness, revision_header: header})
  end

  def assert_liveness(context, revision, slot) do
    assert context.http.liveness == %{status: "live", revision: revision, slot: slot}
    context
  end

  def assert_liveness_header(context, reported) do
    assert context.http.revision_header == reported
    context
  end

  # A theme change is saved or refused as invalid (BN-HTTP-10), and refused
  # for a user without write rights or when the store rejects it.

  def sign_in_owner(context) do
    put_http(context, %{user: %{"userId" => @owner, "roles" => ["admin"]}})
  end

  def sign_in_roles(context, roles) do
    put_http(context, %{user: %{"userId" => @owner, "roles" => parse_roles(roles)}})
  end

  def seed_theme(context, "(none)") do
    assert Preferences.clear_theme(context.http.owner) == :ok
    context
  end

  def seed_theme(context, saved) do
    assert Preferences.put_theme(context.http.owner, saved, @behaviour_now) == :ok
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
    answer =
      conn(:put, "/preferences/theme", %{"theme" => theme})
      |> assign(:current_user, context.http.user)
      |> ThemeController.update(%{"theme" => theme})

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
    put_http(context, %{user: nil, answer: nil})
  end

  def fetch_static(context, path) do
    answer = conn(:get, path) |> Plug.Static.call(static_options())
    put_http(context, %{answer: answer})
  end

  def assert_static(context, media) do
    answer = context.http.answer
    assert answer.status == 200
    assert answer.resp_body != ""
    assert List.first(get_resp_header(answer, "content-type")) |> String.starts_with?(media)

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
    case context.http.media do
      "text/html" -> put_http(context, %{error: ErrorHTML.render("404.html", %{})})
      "application/json" -> put_http(context, %{error: ErrorJSON.render("404.json", %{})})
    end
  end

  def assert_unknown_path(context, "HTML") do
    assert is_binary(context.http.error)
    context
  end

  def assert_unknown_path(context, "JSON") do
    assert %{errors: %{detail: _detail}} = context.http.error
    context
  end

  def assert_unknown_detail(context, detail) do
    case context.http.media do
      "text/html" -> assert context.http.error == detail
      "application/json" -> assert context.http.error == %{errors: %{detail: detail}}
    end

    context
  end

  defp install_storage_once do
    if is_nil(GenServer.whereis(Records)) do
      previous = StoragePorts.install()
      ExUnit.Callbacks.on_exit(fn -> StoragePorts.restore(previous) end)
      records = InMemoryRecordBackend.start()
      ExUnit.Callbacks.start_supervised!({Records, store: records})
    end

    :ok
  end

  defp release, do: ReleaseEnvironment.new()

  defp parse_roles("(empty)"), do: []
  defp parse_roles("unknown"), do: ["unknown"]
  defp parse_roles("admin"), do: ["admin"]

  defp static_options do
    Plug.Static.init(at: "/", from: :bnest_app, gzip: false, only: BnestAppWeb.static_paths())
  end

  defp put_http(context, patch), do: %{context | http: Map.merge(context.http, patch)}
end
