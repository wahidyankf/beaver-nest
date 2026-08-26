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

  pipeline :api do
    plug :accepts, ["json"]
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
  end
end
