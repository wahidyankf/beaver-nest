defmodule BnestApp.Storage.ImportTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Domain.Manifest
  alias BnestApp.Storage.Import
  alias BnestApp.Storage.Ports.RecordBackend
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

  @owner "user-test-import"

  # Wraps the in-memory backend and fails the operations its store lists, so a test can
  # break exactly one step of an import.
  defmodule FlakyBackend do
    @behaviour BnestApp.Storage.Ports.RecordBackend

    alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend

    def start do
      {:ok, failing} = Agent.start_link(fn -> [] end)
      %{backend: __MODULE__, inner: InMemoryRecordBackend.start(), failing: failing}
    end

    def fail(store, operations), do: Agent.update(store.failing, fn _ -> operations end)

    @impl true
    def read(store, type, identity), do: call(store, :read, type, [store.inner, type, identity])

    @impl true
    def write(store, type, identity, revision, candidate),
      do: call(store, :write, type, [store.inner, type, identity, revision, candidate])

    @impl true
    def put_new(store, type, identity, candidate),
      do: call(store, :put_new, type, [store.inner, type, identity, candidate])

    @impl true
    def replace(store, type, identity, candidate),
      do: call(store, :replace, type, [store.inner, type, identity, candidate])

    @impl true
    def remove_exact(store, type, identity, expected),
      do: call(store, :remove_exact, type, [store.inner, type, identity, expected])

    defp call(store, operation, type, arguments) do
      if {operation, type} in Agent.get(store.failing, & &1),
        do: {:error, :io},
        else: apply(InMemoryRecordBackend, operation, arguments)
    end
  end

  test "accepts a theme once and reports a repeat as accepted" do
    store = InMemoryRecordBackend.start()

    assert {:ok, %{status: :accepted, record: %{"theme" => "dark"}}} =
             Import.browser(store, @owner, theme("dark"))

    assert {:ok, %{status: :accepted, record: nil}} = Import.browser(store, @owner, theme("dark"))
  end

  test "rejects a source outside the allow-list or over its limit" do
    store = InMemoryRecordBackend.start()

    assert {:error, :unsupported_source, %{"status" => "rejected"}} =
             Import.browser(store, @owner, %{theme("dark") | "storageKey" => "other"})

    assert {:error, :oversized, %{"failureCategory" => "oversized"}} =
             Import.browser(store, @owner, theme(String.duplicate("x", 17)))

    assert {:error, :oversized, %{"status" => "rejected"}} =
             Import.browser(store, @owner, theme(String.duplicate("x", 17)))

    assert Import.browser(store, @owner, %{theme("dark") | "payload" => nil}) ==
             {:error, :unsupported_source, nil}

    assert Import.browser(store, nil, theme("dark")) == {:error, :unsupported_source, nil}
  end

  test "rejects a malformed payload" do
    store = InMemoryRecordBackend.start()

    assert {:error, :malformed, %{"status" => "rejected"}} =
             Import.browser(store, @owner, theme("blue"))
  end

  test "keeps a newer record instead of importing over it" do
    store = InMemoryRecordBackend.start()
    {:ok, _newer} = RecordBackend.write(store, :theme, @owner, nil, %{"sourceImportId" => nil})

    assert {:error, :stale_revision, %{"status" => "retryable"}} =
             Import.browser(store, @owner, theme("dark"))
  end

  test "resumes an import whose manifest could not be closed" do
    store = FlakyBackend.start()
    FlakyBackend.fail(store, [{:replace, :manifest}])

    assert {:error, :read_back_failed, %{"status" => "pending"}} =
             Import.browser(store, @owner, theme("dark"))

    FlakyBackend.fail(store, [])

    assert {:ok, %{record: %{"revision" => 1, "theme" => "dark"}}} =
             Import.browser(store, @owner, theme("dark"))
  end

  test "reports a store that cannot be read or written" do
    store = FlakyBackend.start()

    FlakyBackend.fail(store, [{:put_new, :manifest}])
    assert Import.browser(store, @owner, theme("dark")) == {:error, :write_failed, nil}
    assert Import.absent_theme(store, @owner) == {:error, :write_failed}

    assert Import.browser(store, @owner, %{theme("dark") | "storageKey" => "other"}) ==
             {:error, :write_failed, nil}

    FlakyBackend.fail(store, [{:put_new, :browser_import}])

    assert {:error, :write_failed, %{"status" => "retryable"}} =
             Import.browser(store, @owner, theme("dark"))

    FlakyBackend.fail(store, [{:read, :manifest}])
    assert Import.browser(store, @owner, theme("dark")) == {:error, :invalid_state, nil}

    FlakyBackend.fail(store, [{:read, :theme}])

    assert {:error, :read_back_failed, %{"status" => "retryable"}} =
             Import.browser(store, @owner, theme("dark"))
  end

  test "reuses a preserved envelope only when its payload is unchanged" do
    store = FlakyBackend.start()
    {import_id, checksum} = Manifest.identity(@owner, "localStorage", "phx:theme", "dark")

    earlier = %{
      "importId" => import_id,
      "payload" => "dark",
      "integrity" => %{"sha256" => checksum, "capturedAt" => "2026-01-01T00:00:00Z"}
    }

    {:ok, _earlier} = RecordBackend.put_new(store, :browser_import, {@owner, import_id}, earlier)
    assert {:ok, _result} = Import.browser(store, @owner, theme("dark"))

    {other_id, _checksum} = Manifest.identity(@owner, "localStorage", "phx:theme", "light")
    altered = %{earlier | "payload" => "dark"} |> put_in(["integrity", "sha256"], checksum)

    {:ok, _altered} = RecordBackend.put_new(store, :browser_import, {@owner, other_id}, altered)

    assert {:error, :write_failed, %{"status" => "retryable"}} =
             Import.browser(store, @owner, theme("light"))

    FlakyBackend.fail(store, [{:read, :browser_import}])

    assert {:error, :write_failed, _manifest} = Import.browser(store, @owner, theme("light"))
  end

  test "records an owner without a theme preference once" do
    store = InMemoryRecordBackend.start()

    assert {:ok, %{import_id: import_id, record: nil}} = Import.absent_theme(store, @owner)
    assert {:ok, %{import_id: ^import_id}} = Import.absent_theme(store, @owner)
  end

  defp theme(payload),
    do: %{"storageArea" => "localStorage", "storageKey" => "phx:theme", "payload" => payload}
end
