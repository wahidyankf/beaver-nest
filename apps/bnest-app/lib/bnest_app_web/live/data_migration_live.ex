defmodule BnestAppWeb.DataMigrationLive do
  use BnestAppWeb, :live_view

  alias BnestApp.DataRepository
  alias BnestApp.DataRepository.Import

  @source_labels %{
    "bnest.chat.v1" => "Chat conversation",
    "bnest.sifat-allah.v1" => "Sifat Allah progress",
    "phx:theme" => "Theme preference"
  }

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if socket.assigns.current_user["migrationMode"] do
      {:ok,
       socket |> put_flash(:error, "Log in before importing browser data.") |> redirect(to: "/")}
    else
      {:ok, assign(socket, sources: [], outcomes: [], ready?: false)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("browser-sources", %{"sources" => sources}, socket) when is_list(sources) do
    {:noreply, assign(socket, sources: sanitize_sources(sources), ready?: true)}
  end

  def handle_event("confirm-imports", _params, socket) do
    owner_id = socket.assigns.current_user["userId"]
    store = DataRepository.store()
    outcomes = Enum.map(socket.assigns.sources, &import_source(store, owner_id, &1))

    cleanup =
      outcomes
      |> Enum.filter(&(&1.status == :accepted and is_binary(&1.cleanup_key)))
      |> Enum.map(& &1.cleanup_key)

    {:noreply,
     socket
     |> assign(:outcomes, outcomes)
     |> push_event("imports-accepted", %{"storageKeys" => cleanup})}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <main class="identity-shell">
      <section
        id="browser-import"
        class="identity-card identity-setup"
        aria-labelledby="import-title"
        phx-hook="BrowserImport"
      >
        <p class="identity-kicker">MOVE DATA SAFELY</p>
        <h1 id="import-title">Save this browser's Bnest data</h1>
        <p class="identity-lede">
          Review the recognized items below. Bnest copies and verifies each item before removing its old browser copy.
        </p>

        <p :if={!@ready?} role="status">Checking this browser…</p>
        <div :if={@ready?} class="identity-account-grid" aria-label="Recognized browser data">
          <article :for={source <- @sources} class="identity-account-card">
            <h2>{source_label(source["storageKey"])}</h2>
            <p>{if source["present"], do: "Ready to preserve", else: "Uses system default"}</p>
          </article>
        </div>

        <div :if={@outcomes != []} aria-live="polite" class="identity-account-grid">
          <p :for={outcome <- @outcomes} class="identity-warning">
            {outcome.label}: {outcome_text(outcome.status)}
          </p>
        </div>

        <button
          :if={@ready?}
          type="button"
          class="identity-primary"
          phx-click="confirm-imports"
        >
          Preserve and verify recognized data
        </button>
        <a href="/" class="identity-secondary">Back to Beaver Nest</a>
      </section>
    </main>
    """
  end

  defp sanitize_sources(sources) do
    allowed = [
      {"sessionStorage", "bnest.chat.v1"},
      {"localStorage", "bnest.sifat-allah.v1"},
      {"localStorage", "phx:theme"}
    ]

    sources
    |> Enum.flat_map(fn source ->
      area = source["storageArea"]
      key = source["storageKey"]
      present = source["present"] == true

      if {area, key} in allowed and (not present or is_binary(source["payload"])) do
        [
          %{
            "storageArea" => area,
            "storageKey" => key,
            "present" => present,
            "payload" => source["payload"]
          }
        ]
      else
        []
      end
    end)
    |> Enum.uniq_by(&{&1["storageArea"], &1["storageKey"]})
  end

  defp import_source(store, owner_id, %{"storageKey" => "phx:theme", "present" => false}) do
    case Import.absent_theme(store, owner_id) do
      {:ok, _result} -> outcome("phx:theme", :accepted, nil)
      {:error, _reason} -> outcome("phx:theme", :retryable, nil)
    end
  end

  defp import_source(_store, _owner_id, %{
         "storageKey" => key,
         "present" => false
       })
       when key in ["bnest.chat.v1", "bnest.sifat-allah.v1"],
       do: outcome(key, :accepted, nil)

  defp import_source(store, owner_id, source) do
    key = source["storageKey"]

    case Import.browser(store, owner_id, source) do
      {:ok, _result} ->
        outcome(key, :accepted, key)

      {:error, :stale_revision, _manifest} ->
        outcome(key, :refresh_required, nil)

      {:error, reason, _manifest} when reason in [:malformed, :oversized, :unsupported_source] ->
        outcome(key, :rejected, nil)

      {:error, _reason, _manifest} ->
        outcome(key, :retryable, nil)
    end
  end

  defp outcome(key, status, cleanup_key),
    do: %{label: source_label(key), status: status, cleanup_key: cleanup_key}

  defp source_label(key), do: Map.get(@source_labels, key, "Browser data")

  defp outcome_text(:accepted), do: "accepted and verified"
  defp outcome_text(:rejected), do: "rejected safely; browser source retained"
  defp outcome_text(:retryable), do: "not completed; retry without re-entering data"
  defp outcome_text(:refresh_required), do: "newer server data exists; refresh before retrying"
end
