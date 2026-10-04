defmodule BnestAppWeb.AdminScheduleSettingsLive do
  @moduledoc false

  use BnestAppWeb, :live_view

  alias BnestApp.Backup
  alias BnestApp.Backup.Domain.Reconciliation
  alias BnestApp.Operations
  alias BnestApp.Scheduler
  alias Phoenix.LiveView.AsyncResult

  @schedule_key "prod-sqlite-backup-daily"
  @backup_handler "prod_sqlite_backup"

  # How long the label waits for the check, in milliseconds. `assign_async/4` has no timeout of
  # its own, so the check enforces it; the application configuration lowers it for a test:
  # `config :bnest_app, BnestAppWeb.AdminScheduleSettingsLive, integrity_ceiling_ms: <ms>`.
  @default_integrity_ceiling_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Schedules & backups")
     |> assign(:error, nil)
     |> assign(:status_message, nil)
     |> refresh()
     |> start_integrity_check()}
  end

  @impl true
  def handle_event("save_schedule", %{"schedule" => params}, socket) do
    case Scheduler.update_daily(@schedule_key, params, DateTime.utc_now()) do
      {:ok, _schedule} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:status_message, "Daily schedule saved.")
         |> refresh()
         |> start_integrity_check()}

      {:error, reason} ->
        {:noreply, assign(socket, error: schedule_error(reason), status_message: nil)}
    end
  end

  def handle_event("save_backup", %{"backup" => %{"destination_directory" => directory}}, socket) do
    case Backup.save_destination(directory) do
      {:ok, location} ->
        {:ok, claim} =
          Scheduler.claim_setup(@schedule_key, location.destination_id, DateTime.utc_now())

        _task = Scheduler.run_now(claim)

        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:status_message, "Backup folder saved and its first verification was queued.")
         |> refresh()
         |> start_integrity_check()}

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

      <%!-- One stable container (not a live region): a message that appears or goes away must not
           shift the unkeyed siblings after it, or the patch recreates both forms and the focus
           on the control that was just used is lost. --%>
      <div id="settings-feedback">
        <p :if={@error} id="settings-error" role="alert" tabindex="-1" class="admin-settings-error">
          {@error}
        </p>
        <p :if={@status_message} aria-live="polite" class="admin-settings-status">
          {@status_message}
        </p>
      </div>

      <section class="schedule-group" aria-labelledby="family-schedules-title">
        <h2 id="family-schedules-title">Family schedules</h2>
        <p :if={@inventory.family == []}>No family schedules are configured.</p>
        <.schedule_row
          :for={schedule <- @inventory.family}
          schedule={schedule}
          integrity={integrity_outcome(@integrity)}
        />
      </section>

      <section class="schedule-group" aria-labelledby="admin-schedules-title">
        <h2 id="admin-schedules-title">Admin/system schedules</h2>
        <p :if={@inventory.admin_system == []}>No admin/system schedules are configured.</p>
        <.schedule_row
          :for={schedule <- @inventory.admin_system}
          schedule={schedule}
          integrity={integrity_outcome(@integrity)}
        />
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
    assigns =
      assigns
      |> assign(:settings_path, settings_path(assigns.schedule))
      |> assign(:integrity?, assigns.schedule.handler_key == @backup_handler)

    ~H"""
    <article
      class="schedule-row"
      data-schedule-key={@schedule.schedule_key}
      data-last-run-state={@schedule.last_run_state || "never"}
    >
      <h3>
        <a :if={@settings_path} href={@settings_path}>{schedule_label(@schedule)}</a>
        <span :if={!@settings_path}>{schedule_label(@schedule)}</span>
      </h3>
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
        <.integrity_item
          :if={@integrity?}
          term_id={"integrity-term-" <> @schedule.schedule_key}
          outcome={@integrity}
        />
      </dl>
    </article>
    """
  end

  # The integrity item of the backup row: its words are `Reconciliation.report/1`'s alone, so
  # the page can never disagree with the log, the telemetry and the Mix task. The description is
  # the one polite region; it holds no control and its attributes never change with the state, so
  # a result replaces the text in place and announces it without moving focus.
  attr :term_id, :string, required: true
  attr :outcome, :any, required: true

  defp integrity_item(assigns) do
    report = Reconciliation.report(assigns.outcome)

    assigns =
      assigns
      |> assign(:report, report)
      |> assign(:state, integrity_state(assigns.outcome, report))

    ~H"""
    <div class="integrity-label" data-integrity-state={@state}>
      <dt id={@term_id}>{@report.label}</dt>
      <dd class="integrity-label__result" aria-live="polite" aria-labelledby={@term_id}>
        <.integrity_marker state={@state} />
        <span class="integrity-label__summary">{@report.summary}</span>
        <ul :if={@report.problems != []} class="integrity-label__problems">
          <li :for={problem <- @report.problems}>{problem}</li>
        </ul>
      </dd>
    </div>
    """
  end

  # A shape per state beside the words, so no state rests on colour alone; decorative, because
  # the summary beside it says the same.
  attr :state, :atom, required: true

  defp integrity_marker(assigns) do
    ~H"""
    <svg
      class="integrity-label__marker"
      viewBox="0 0 20 20"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <.integrity_shape state={@state} />
    </svg>
    """
  end

  attr :state, :atom, required: true

  defp integrity_shape(%{state: :checking} = assigns) do
    ~H"""
    <circle cx="10" cy="10" r="9" stroke-dasharray="3 3" />
    <circle cx="5.5" cy="10" r="1.4" fill="currentColor" stroke="none" />
    <circle cx="10" cy="10" r="1.4" fill="currentColor" stroke="none" />
    <circle cx="14.5" cy="10" r="1.4" fill="currentColor" stroke="none" />
    """
  end

  defp integrity_shape(%{state: :all_present} = assigns) do
    ~H"""
    <circle cx="10" cy="10" r="9" />
    <path d="M5.5 10.5 L8.5 13.5 L14.5 6.5" />
    """
  end

  defp integrity_shape(%{state: :needs_attention} = assigns) do
    ~H"""
    <polygon points="10,2 19,18 1,18" />
    <path d="M10 8 L10 12.5" />
    <circle cx="10" cy="15.2" r="1.2" fill="currentColor" stroke="none" />
    """
  end

  defp integrity_shape(%{state: :could_not_check} = assigns) do
    ~H"""
    <rect x="1" y="1" width="18" height="18" rx="3" />
    <path d="M7 7 Q7 4 10 4 Q13.5 4 13.5 7.5 Q13.5 9.5 10 11 L10 12.5" stroke-width="1.8" />
    <circle cx="10" cy="15.5" r="1.1" fill="currentColor" stroke="none" />
    """
  end

  defp integrity_shape(%{state: :nothing_to_check} = assigns) do
    ~H"""
    <circle cx="10" cy="10" r="9" />
    <path d="M5.5 10 L14.5 10" />
    """
  end

  defp settings_path(schedule) do
    with {:ok, %{settings_key: settings_key}} when is_binary(settings_key) <-
           Scheduler.task_entry(schedule.handler_key),
         {:ok, %{path: path}} <- Operations.fetch_admin_panel(settings_key) do
      path
    else
      _no_typed_settings -> nil
    end
  end

  # The one place a check starts: the connected mount and each successful save call it. The
  # label returns to checking, and a check still in flight is cancelled first, so that only the
  # newest check can report (a result that arrives from a superseded one is dropped by its
  # reference). It runs off the render path and only on the connected mount: `assign_async/4`
  # runs nothing on the disconnected render, which shows the checking state and opens neither
  # the ledger nor the destination.
  defp start_integrity_check(socket) do
    ceiling_ms = integrity_ceiling_ms()

    socket
    |> cancel_integrity_check()
    |> assign_async(:integrity, fn -> {:ok, %{integrity: check_integrity(ceiling_ms)}} end,
      reset: true
    )
  end

  defp cancel_integrity_check(%{assigns: %{integrity: %AsyncResult{} = running}} = socket),
    do: cancel_async(socket, running)

  defp cancel_integrity_check(socket), do: socket

  defp integrity_ceiling_ms do
    :bnest_app
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:integrity_ceiling_ms, @default_integrity_ceiling_ms)
  end

  # The reconciliation runs in a task this function owns and monitors, so that the ceiling can
  # cancel it: a shutdown kills the process that is reading the destination, where giving up on
  # its answer alone would leave it reading. A check that is cancelled, exits or raises is the
  # outcome of a check that could not be made.
  defp check_integrity(ceiling_ms) do
    task = Task.async(&reconcile_outcome/0)

    case Task.yield(task, ceiling_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, outcome} -> outcome
      {:exit, _reason} -> {:error, :exited}
      nil -> {:error, :ceiling}
    end
  end

  # The destination is read, never prepared (`Backup.read_destination/0`), and a failure of any
  # kind is the outcome of a check that could not be made: its reason may name a path, so none
  # is kept.
  defp reconcile_outcome do
    with {:ok, location} <- Backup.read_destination() do
      Backup.reconcile(location.directory, Scheduler.verified_runs(@backup_handler))
    end
  rescue
    _error -> {:error, :raised}
  catch
    :exit, _reason -> {:error, :exited}
  end

  defp integrity_outcome(%AsyncResult{loading: loading}) when loading != nil, do: :checking
  defp integrity_outcome(%AsyncResult{ok?: true, result: outcome}), do: outcome
  defp integrity_outcome(%AsyncResult{}), do: {:error, :failed}

  # Which marker shows: read off the report, whose problems and exit status say what it found.
  defp integrity_state(:checking, _report), do: :checking
  defp integrity_state({:error, _reason}, _report), do: :could_not_check
  defp integrity_state({:ok, _results}, %{problems: [_ | _]}), do: :needs_attention
  defp integrity_state({:ok, _results}, %{exit_status: 0}), do: :all_present
  defp integrity_state({:ok, _results}, _report), do: :nothing_to_check

  defp refresh(socket) do
    inventory = Scheduler.admin_inventory()
    backup_schedule = Scheduler.get_schedule(@schedule_key)
    {:ok, backup_location} = Backup.destination()

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
        backup_directory: Backup.default_directory()
      )
  end

  defp schedule_label(%{handler_key: @backup_handler}), do: "Production database backup"
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
