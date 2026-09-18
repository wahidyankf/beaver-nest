defmodule BnestAppWeb.Router do
  use BnestAppWeb, :router
  import BnestAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BnestAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :authenticated_browser do
    plug :require_authenticated_user
  end

  pipeline :open_setup do
    plug :require_open_setup
  end

  pipeline :admin_only do
    plug :require_admin_role
  end

  pipeline :family_chat_enabled do
    plug :require_family_chat_enabled
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The real `/api/graphql` surface: strict method/content-type/size/CSRF
  # checks (tech-doc 008) before Absinthe ever executes a document.
  pipeline :graphql do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_user
    plug BnestAppWeb.Plugs.GraphQLPipeline
    plug :put_absinthe_context
  end

  # GraphiQL is a browser-loaded debugging page (GET renders the UI, its own
  # fetch calls POST back to the same forward) — never the API surface real
  # clients use, so it does not carry the strict `:graphql` pipeline's
  # method/CSRF checks. It only ever exists in dev/test builds (see the
  # `dev_routes` compile-time gate below), never in production.
  pipeline :graphiql do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_current_user
    plug :put_absinthe_context
  end

  defp put_absinthe_context(conn, _options) do
    Absinthe.Plug.put_options(conn,
      context: %{
        current_user: conn.assigns[:current_user],
        session_digest: conn.assigns[:session_digest]
      }
    )
  end

  scope "/api" do
    pipe_through :graphql

    forward "/graphql", Absinthe.Plug, schema: BnestAppWeb.Schema, json_codec: Jason
  end

  scope "/health", BnestAppWeb do
    pipe_through :api

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/", BnestAppWeb do
    pipe_through :browser

    live "/login", LoginLive, :login
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", BnestAppWeb do
    pipe_through [:browser, :open_setup]

    live "/setup", LoginLive, :setup
    post "/setup", BootstrapController, :create
  end

  scope "/", BnestAppWeb do
    pipe_through [:browser, :authenticated_browser]

    get "/", PageController, :home
    put "/preferences/theme", ThemeController, :update

    live_session :authenticated,
      on_mount: [{BnestAppWeb.UserAuth, :require_authenticated_user}] do
      live "/chat", ChatLive
      live "/apps/sifat-allah", SifatAllahLive
      live "/data-migration", DataMigrationLive
    end
  end

  scope "/", BnestAppWeb do
    pipe_through [:browser, :authenticated_browser, :family_chat_enabled]

    get "/family-chat", FamilyChatController, :redirect_to_canonical
    get "/family-chat/:slug", FamilyChatController, :room
  end

  scope "/", BnestAppWeb do
    pipe_through [:browser, :admin_only, :authenticated_browser]

    live_session :storage_admin,
      on_mount: [{BnestAppWeb.UserAuth, :require_admin_user}] do
      live "/storage", StorageLive
      live "/admin/settings", AdminSettingsLive
      live "/admin/settings/schedules", AdminScheduleSettingsLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", BnestAppWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bnest_app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BnestAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Dev/test-only interactive GraphQL explorer. Compiled out entirely in
    # production builds by the `dev_routes` gate above — matching how
    # LiveDashboard is scoped — so no production route or production
    # compile-time enablement ever exists (tech-doc 008).
    scope "/api" do
      pipe_through :graphiql

      forward "/graphiql", Absinthe.Plug.GraphiQL,
        schema: BnestAppWeb.Schema,
        json_codec: Jason,
        socket: BnestAppWeb.UserSocket,
        interface: :playground
    end
  end
end
