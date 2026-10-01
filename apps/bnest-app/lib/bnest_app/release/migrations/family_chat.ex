defmodule BnestApp.Release.Migrations.FamilyChat do
  @moduledoc """
  Release-time migration/verification for Family Chat, mirroring
  `BnestApp.Release.Migrations.PersistentSchedules`'s standalone-callable
  shape (usable both from a running application and from a bare `mix eval`/
  release console before the application supervises anything).

  The name is frozen: `tools/deployment.mjs` evaluates it. The migration and the
  convergence themselves are the `BnestApp.FamilyChat` facade's; this module owns only the
  release-time repository, the exclusive storage lock and the handler check around them.
  """

  alias BnestApp.FamilyChat
  alias BnestApp.Scheduler.Registry
  alias BnestApp.Storage

  @spec apply_and_verify!() :: :ok
  def apply_and_verify! do
    with_repository(fn ->
      Storage.with_exclusive_lock(&migrate_and_verify!/0)
    end)
  end

  # Tech-doc 009 ("Backup Schedule Migration"): "After the compatibility
  # revision is routed and every runnable slot supports the new Backup
  # service, managed release calls a public Scheduler operation that
  # force-converges this key once"; and "Push retention remains a separate
  # fixed disabled seed at 00:15 WIB and becomes enabled only after old-slot
  # drain." Unlike `activate_when_compatible!/0` below (a `boot`-time
  # self-heal gated on `family_chat_enabled`, i.e. tech-doc 007's experience
  # flag), release tooling calls this directly, once, right after the prior
  # slot's drain -- independent of that flag, matching the Gherkin "Rule:
  # One-time backup schedule convergence" scenario's own driver, which calls
  # `Scheduler.converge_backup_time!/2` the same way.
  @spec converge_after_drain!() :: :ok
  def converge_after_drain! do
    with_repository(fn ->
      Storage.with_exclusive_lock(&do_converge_after_drain!/0)
    end)
  end

  # Split out from `apply_and_verify!/0` so the `case` below sits at one
  # nesting level of its own, rather than a third level inside that
  # function's two wrapping closures (`with_repository`'s and
  # `Storage.with_exclusive_lock`'s) -- keeps the migration/verification logic at
  # credo's max nesting depth instead of merely satisfying it by relocation.
  defp migrate_and_verify! do
    {:ok, room} = FamilyChat.migrate!()

    case room do
      %{id: 1, slug: "ruang-keluarga", name: "Ruang Keluarga", room_kind: "conversation"} ->
        :ok

      other ->
        raise "family chat migration verification failed: #{inspect(other)}"
    end

    activate_when_compatible!()
    verify_registered_handler!()
  end

  # Tech-doc 002: the retention seed ships `enabled = 0` "during mixed-
  # version overlap"; once compatible code is active (`family_chat_enabled`
  # -- tech-doc 007's compatibility/experience release flag), a compatible
  # slot both enables the retention schedule and converges the pre-existing
  # backup schedule to 18:00 UTC. Both go through the same CAS-on-`revision
  # = 1` seam as `Scheduler.converge_backup_time!/2` (see its moduledoc), so
  # calling this on every boot -- rather than requiring a precise "slot
  # fully drained" signal this module has no way to observe -- is safe: it
  # takes effect at most once, ever, and never overrides a later operator
  # edit to either schedule.
  defp activate_when_compatible! do
    if Application.get_env(:bnest_app, :family_chat_enabled, false) do
      do_converge_after_drain!()
    end

    :ok
  end

  defp do_converge_after_drain!, do: FamilyChat.converge_after_drain!()

  defp verify_registered_handler! do
    case Registry.fetch("family_chat_push_retention") do
      {:ok, %{handler: BnestApp.PushNotifications.RetentionJob}} ->
        :ok

      _missing_or_wrong ->
        raise "family chat push retention handler is not registered"
    end
  end

  defp with_repository(operation) do
    ensure_database_apps_started!()
    standalone? = not application_started?(:bnest_app)
    started_here? = is_nil(Process.whereis(BnestApp.SqliteRepo))
    if started_here?, do: Storage.ensure_started!()

    try do
      operation.()
    after
      if standalone? and started_here?, do: Storage.stop()
    end
  end

  defp application_started?(application) do
    Enum.any?(Application.started_applications(), fn {started, _description, _version} ->
      started == application
    end)
  end

  defp ensure_database_apps_started! do
    Enum.each([:ecto_sql, :exqlite], fn application ->
      case Application.ensure_all_started(application) do
        {:ok, _started} ->
          :ok

        {:error, {_failed_application, reason}} ->
          raise "could not start #{application} for family chat migration: #{inspect(reason)}"
      end
    end)
  end
end
