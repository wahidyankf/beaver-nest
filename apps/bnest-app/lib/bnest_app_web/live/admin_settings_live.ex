defmodule BnestAppWeb.AdminSettingsLive do
  @moduledoc false

  use BnestAppWeb, :live_view

  alias BnestApp.AdminConfig.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin settings", panels: Registry.panels())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="admin-settings-shell" aria-labelledby="admin-settings-title">
      <nav aria-label="Breadcrumb"><a href="/">Admin home</a></nav>
      <p class="admin-settings-kicker">APPLICATION CONTROLS</p>
      <h1 id="admin-settings-title">Admin settings</h1>
      <p>Each area validates and saves only the fields owned by its domain.</p>

      <div class="admin-settings-grid" aria-label="Configuration areas">
        <a :for={panel <- @panels} href={panel.path} class="admin-settings-panel">
          <strong>{panel.label}</strong>
          <span>{panel.description}</span>
        </a>
      </div>
    </main>
    """
  end
end
