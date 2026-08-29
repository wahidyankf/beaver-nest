defmodule BnestAppWeb.StorageLive do
  @moduledoc false

  use BnestAppWeb, :live_view

  alias BnestApp.DataRepository.StorageCoordinator
  alias BnestApp.SqliteRepo
  alias BnestApp.Storage.Config
  alias BnestApp.Storage.Location
  alias BnestApp.Storage.Migration
  alias Ecto.Adapters.SQL, as: EctoSQL

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Storage")
     |> assign(:directory_input, "")
     |> assign(:error, nil)
     |> assign(:status_message, nil)
     |> refresh_state()}
  end

  @impl true
  def handle_event("check_folder", %{"directory" => directory}, socket) do
    case Location.validate(directory) do
      {:ok, validated} ->
        {:noreply,
         socket
         |> assign(:directory_input, validated)
         |> assign(:error, nil)
         |> assign(:status_message, "Folder looks safe to use.")}

      {:error, reason} ->
        {:noreply, assign(socket, error: safe_error(reason), status_message: nil)}
    end
  end

  def handle_event("create_database", %{"directory" => directory}, socket) do
    case Config.persist_directory(directory) do
      {:ok, _config} ->
        {:noreply, socket |> assign(:error, nil) |> refresh_state()}

      {:error, reason} ->
        {:noreply, assign(socket, error: safe_error(reason))}
    end
  end

  def handle_event("move_data", _params, socket) do
    Config.ensure_default!()
    directory = Config.resolved_database_path() |> Path.dirname()
    :ok = StorageCoordinator.ensure_started!(Config.resolved_database_path())
    Ecto.Migrator.run(SqliteRepo, migrations_path(), :up, all: true)

    flat_root = Application.get_env(:bnest_app, :runtime_root)
    result = Migration.run(flat_root, SqliteRepo)

    if result.blocked == 0 do
      _ = File.mkdir_p!(directory)
      verified? = Migration.integrity_ok?() and Migration.parity_ok?(flat_root)
      if verified?, do: Migration.activate!()
    end

    {:noreply, refresh_state(socket)}
  end

  def handle_event("retry_migration", _params, socket) do
    handle_event("move_data", %{}, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl p-6" aria-labelledby="storage-heading">
      <h1 id="storage-heading" class="text-2xl font-semibold">Storage setup</h1>

      <p
        :if={@error}
        role="alert"
        class="mt-4 rounded border border-red-400 bg-red-50 p-3 text-red-800"
      >
        {@error}
      </p>

      <p :if={@status_message} aria-live="polite" class="mt-4 text-sm text-gray-700">
        {@status_message}
      </p>

      <section class="mt-6" aria-label="Database folder">
        <form phx-submit="check_folder">
          <label for="directory" class="block text-sm font-medium">Database folder</label>
          <input
            type="text"
            id="directory"
            name="directory"
            value={@directory_input}
            disabled={@locked?}
            placeholder={Location.default_directory()}
            class="mt-1 w-full rounded border p-2"
          />
          <button
            type="submit"
            disabled={@locked?}
            class="mt-2 rounded bg-slate-700 px-3 py-1 text-white"
          >
            Check folder
          </button>
        </form>

        <form :if={not @locked?} phx-submit="create_database" class="mt-2">
          <input type="hidden" name="directory" value={@directory_input} />
          <button type="submit" class="rounded bg-indigo-700 px-3 py-1 text-white">
            Create database
          </button>
        </form>
      </section>

      <section class="mt-6" aria-live="polite" aria-label="Migration status">
        <p>Status: <strong>{@phase_label}</strong></p>

        <form :if={@phase == :flat_primary} phx-submit="move_data">
          <button type="submit" class="mt-2 rounded bg-emerald-700 px-3 py-1 text-white">
            {if @retryable?, do: "Retry migration", else: "Move data"}
          </button>
        </form>
      </section>
    </div>
    """
  end

  # Reads only: rendering /storage (mount, or any event's post-refresh) must
  # never itself persist a default location, or an admin's first visit would
  # silently lock in the default before they ever get to choose a custom
  # folder. Config.phase/0 and Config.resolved_database_path/0 both fall back
  # to the same default without writing; only an explicit action (headless
  # `move_data`, or the CLI migration task) is allowed to call
  # Config.ensure_default!/0.
  defp refresh_state(socket) do
    phase = Config.phase()
    retryable? = phase == :flat_primary and migration_started?()

    socket
    |> assign(:phase, phase)
    |> assign(:phase_label, phase_label(phase, retryable?))
    |> assign(:locked?, migration_started?())
    |> assign(:retryable?, retryable?)
    |> assign(:directory_input, Config.resolved_database_path() |> Path.dirname())
  end

  defp migration_started? do
    StorageCoordinator.ensure_started!()

    EctoSQL.query(
      SqliteRepo,
      "SELECT 1 FROM sqlite_master WHERE name = 'bnest_migration_runs'",
      []
    )
    |> case do
      {:ok, %{rows: [[1]]}} ->
        case SqliteRepo.query("SELECT 1 FROM bnest_migration_runs LIMIT 1") do
          {:ok, %{rows: [_row]}} -> true
          _absent -> false
        end

      _missing_table ->
        false
    end
  rescue
    _error -> false
  end

  defp phase_label(:sqlite_primary, _retryable?), do: "SQLite active"
  defp phase_label(:flat_primary, true), do: "Blocked — retry available"
  defp phase_label(:flat_primary, false), do: "Not started"

  defp safe_error(:not_absolute), do: "Enter an absolute server-local folder."
  defp safe_error(:symlink), do: "That folder contains a symlink; choose a direct path."

  defp safe_error(:world_writable),
    do: "That folder's parent is world-writable; choose a private location."

  defp safe_error(:unsafe_location),
    do: "That folder overlaps the application or a migration source."

  defp safe_error(:immutable),
    do: "The database location is set and cannot change after creation."

  defp safe_error(_reason),
    do: "That folder can't be used; choose another private server-local path."

  defp migrations_path, do: Application.app_dir(:bnest_app, "priv/sqlite_repo/migrations")
end
