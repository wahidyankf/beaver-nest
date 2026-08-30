defmodule BnestAppWeb.AdminScheduleSettingsLive do
  @moduledoc false

  use BnestAppWeb, :live_view

  alias BnestApp.Backup.Config, as: BackupConfig
  alias BnestApp.Scheduler.Run
  alias BnestApp.Scheduler.Store

  @schedule_key "prod-sqlite-backup-daily"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Schedules & backups")
     |> assign(:error, nil)
     |> assign(:status_message, nil)
     |> refresh()}
  end

  @impl true
  def handle_event("save_schedule", %{"schedule" => params}, socket) do
    case Store.update_daily(@schedule_key, params, DateTime.utc_now()) do
      {:ok, _schedule} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:status_message, "Daily schedule saved.")
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, error: schedule_error(reason), status_message: nil)}
    end
  end

  def handle_event("save_backup", %{"backup" => %{"destination_directory" => directory}}, socket) do
    case BackupConfig.save(directory) do
      {:ok, location} ->
        {:ok, claim} =
          Store.claim_setup(@schedule_key, location.destination_id, DateTime.utc_now())

        dispatch(claim)

        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:status_message, "Backup folder saved and its first verification was queued.")
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, error: backup_error(reason), status_message: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="admin-settings-shell" aria-labelledby="schedules-title">
      <nav aria-label="Breadcrumb">
        <a href="/">Admin home</a> <span aria-hidden="true">/</span>
        <a href="/admin/settings">Admin settings</a>
      </nav>
      <p class="admin-settings-kicker">DAILY OPERATIONS</p>
      <h1 id="schedules-title">Schedules &amp; backups</h1>

      <p :if={@error} id="settings-error" role="alert" tabindex="-1" class="admin-settings-error">
        {@error}
      </p>
      <p :if={@status_message} aria-live="polite" class="admin-settings-status">
        {@status_message}
      </p>

      <section class="schedule-group" aria-labelledby="family-schedules-title">
        <h2 id="family-schedules-title">Family schedules</h2>
        <p :if={@inventory.family == []}>No family schedules are configured.</p>
        <.schedule_row :for={schedule <- @inventory.family} schedule={schedule} />
      </section>

      <section class="schedule-group" aria-labelledby="admin-schedules-title">
        <h2 id="admin-schedules-title">Admin/system schedules</h2>
        <p :if={@inventory.admin_system == []}>No admin/system schedules are configured.</p>
        <.schedule_row :for={schedule <- @inventory.admin_system} schedule={schedule} />
      </section>

      <section class="settings-form-card" aria-labelledby="schedule-form-title">
        <h2 id="schedule-form-title">Production database backup</h2>
        <p>Expiration: <strong>Never</strong></p>
        <form phx-submit="save_schedule">
          <input type="hidden" name="schedule[revision]" value={@backup_schedule.revision} />
          <label class="settings-check">
            <input
              type="checkbox"
              name="schedule[enabled]"
              value="true"
              checked={@backup_schedule.enabled}
            /> Enabled
          </label>
          <label for="daily-time-wib">Daily time (WIB)</label>
          <input
            id="daily-time-wib"
            type="time"
            name="schedule[daily_time_wib]"
            value={utc_to_wib(@backup_schedule.daily_at_utc)}
            required
          />
          <button type="submit">Save schedule</button>
        </form>
      </section>

      <section class="settings-form-card" aria-labelledby="backup-folder-title">
        <h2 id="backup-folder-title">Backup folder</h2>
        <p>Default: <code>@data/backup/</code></p>
        <p>Keep one per day for 7 days.</p>
        <form phx-submit="save_backup">
          <label for="backup-directory">Private destination override</label>
          <input
            id="backup-directory"
            type="text"
            name="backup[destination_directory]"
            value={@backup_directory}
            aria-describedby="backup-folder-help"
          />
          <p id="backup-folder-help">
            Leave the current resolved folder unchanged or enter a safe absolute override.
          </p>
          <button type="submit">Save and create first backup</button>
        </form>
      </section>
    </main>
    """
  end

  defp schedule_row(assigns) do
    ~H"""
    <article class="schedule-row" data-schedule-key={@schedule.schedule_key}>
      <h3>{schedule_label(@schedule)}</h3>
      <dl>
        <div>
          <dt>Cadence</dt><dd>Daily at {utc_to_wib(@schedule.daily_at_utc)} WIB</dd>
        </div>
        <div>
          <dt>Next run</dt><dd>{@schedule.next_run_at}</dd>
        </div>
        <div>
          <dt>State</dt><dd>{schedule_state(@schedule)}</dd>
        </div>
        <div>
          <dt>Expiration</dt><dd>{expiration(@schedule)}</dd>
        </div>
        <div>
          <dt>Last result</dt><dd>{last_result(@schedule)}</dd>
        </div>
      </dl>
    </article>
    """
  end

  defp refresh(socket) do
    inventory = Store.admin_inventory()
    backup_schedule = Store.get_schedule(@schedule_key)
    {:ok, backup_location} = BackupConfig.resolve()

    assign(socket,
      inventory: inventory,
      backup_schedule: backup_schedule,
      backup_directory: backup_location.directory
    )
  rescue
    _not_ready ->
      assign(socket,
        inventory: %{family: [], admin_system: []},
        backup_schedule: fallback_schedule(),
        backup_directory: BackupConfig.default_directory()
      )
  end

  defp dispatch(claim) do
    case Process.whereis(BnestApp.Scheduler.Tasks) do
      nil ->
        Task.start(fn -> Run.execute(claim, DateTime.utc_now()) end)

      _pid ->
        Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
          Run.execute(claim, DateTime.utc_now())
        end)
    end
  end

  defp schedule_label(%{handler_key: "prod_sqlite_backup"}), do: "Production database backup"
  defp schedule_label(schedule), do: schedule.schedule_key
  defp schedule_state(%{expired_at: expired_at}) when not is_nil(expired_at), do: "Expired"
  defp schedule_state(%{enabled: true}), do: "Enabled"
  defp schedule_state(_schedule), do: "Disabled"
  defp last_result(%{last_run_state: nil}), do: "Never run"
  defp last_result(%{last_run_state: "verified"}), do: "Verified"
  defp last_result(%{last_run_state: "retryable"}), do: "Retry scheduled"
  defp last_result(%{last_run_state: "running"}), do: "Running"
  defp last_result(%{last_run_state: "failed"}), do: "Failed; review configuration"
  defp last_result(%{last_run_state: "skipped"}), do: "Skipped; review configuration"
  defp expiration(%{expiration_kind: "never"}), do: "Never expires"
  defp expiration(%{expiration_kind: "at", expires_at: instant}), do: "Expires at #{instant}"

  defp expiration(%{expiration_kind: "after_occurrences"} = schedule),
    do: "#{schedule.claimed_occurrences} of #{schedule.max_occurrences} occurrences"

  defp utc_to_wib(utc) do
    {:ok, parsed} = Time.from_iso8601(utc <> ":00")
    {seconds, _microseconds} = Time.to_seconds_after_midnight(parsed)

    seconds
    |> Kernel.+(7 * 60 * 60)
    |> Integer.mod(86_400)
    |> Time.from_seconds_after_midnight()
    |> Calendar.strftime("%H:%M")
  end

  defp schedule_error(:invalid_time), do: "Enter a valid WIB time."
  defp schedule_error(:conflict), do: "The schedule changed. Reload and try again."
  defp schedule_error(_reason), do: "The schedule could not be saved."

  defp backup_error(:source_overlap), do: "Choose a folder outside the live database location."
  defp backup_error(:symlink), do: "Choose a folder that is not a symbolic link."
  defp backup_error(_reason), do: "The backup folder could not be saved safely."

  defp fallback_schedule do
    %{
      schedule_key: @schedule_key,
      handler_key: "prod_sqlite_backup",
      daily_at_utc: "19:00",
      enabled: true,
      expiration_kind: "never",
      expires_at: nil,
      max_occurrences: nil,
      claimed_occurrences: 0,
      expired_at: nil,
      next_run_at: "Unavailable",
      revision: 1
    }
  end
end
