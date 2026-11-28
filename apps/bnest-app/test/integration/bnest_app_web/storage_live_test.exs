defmodule BnestAppWeb.StorageLiveTest do
  @moduledoc """
  Integration tests for the `sqlite_storage.feature` storage page. The bound
  scenarios read the production `/storage` page through LiveViewTest: on a
  flat-primary instance, after a blocked run, and on a SQLite-primary
  instance.
  """

  use BnestAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BnestApp.Storage
  alias BnestApp.TestInstance

  @moduletag phase: :flat_primary

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The storage status reads Not started, Blocked, or SQLite active
  test "the storage status reads Not started before any migration", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/storage")

    assert status_of(html) == "Not started"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The storage status reads Not started, Blocked, or SQLite active
  test "the storage status reads Blocked after a blocked run", %{conn: conn} do
    root = instance_flat_root!()
    broken = Path.join(root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken))
    File.write!(broken, "{malformed")

    assert {:error, :blocked, _report} = Storage.migrate(root, false)

    {:ok, _view, html} = live(conn, "/storage")

    assert status_of(html) == "Blocked — retry available"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The storage status reads Not started, Blocked, or SQLite active
  test "the storage status reads SQLite active once SQLite is authoritative", %{conn: conn} do
    root = instance_flat_root!()

    assert {:ok, :activated, _report} = Storage.migrate(root, true)

    {:ok, _view, html} = live(conn, "/storage")

    assert status_of(html) == "SQLite active"
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: Move data and Retry migration start or retry the migration
  test "Move data and Retry migration start or retry the migration", %{conn: conn} do
    root = instance_flat_root!()
    broken = Path.join(root, "system/manifests/broken-manifest.json")
    File.mkdir_p!(Path.dirname(broken))
    File.write!(broken, "{malformed")

    {:ok, view, _html} = live(conn, "/storage")
    assert control_of(render(view)) == "Move data"

    html = render_submit(view, :move_data, %{})
    assert status_of(html) == "Blocked — retry available"
    assert control_of(html) == "Retry migration"

    File.rm!(broken)
    html = render_submit(view, :retry_migration, %{})
    assert status_of(html) == "SQLite active"
  end

  # @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: The folder is locked once migration has started
  test "the folder is locked once migration has started", %{conn: conn} do
    root = instance_flat_root!()

    assert {:ok, _outcome, _report} = Storage.migrate(root, false)
    assert Storage.migration_started?()

    {:ok, view, _html} = live(conn, "/storage")
    assert has_element?(view, ~s(input#directory[disabled]))

    assert has_element?(
             view,
             "section[aria-label='Database folder'] button[disabled]",
             "Check folder"
           )

    refute render(view) =~ "Create database"
  end

  defp instance_flat_root! do
    case TestInstance.state() do
      %{paths: %{flat_instance_root: root}} -> root
      _other -> raise "no flat-primary test instance is current"
    end
  end

  defp status_of(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("section[aria-label='Migration status'] strong")
    |> LazyHTML.text()
  end

  defp control_of(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("section[aria-label='Migration status'] button")
    |> LazyHTML.text()
    |> String.trim()
  end
end
