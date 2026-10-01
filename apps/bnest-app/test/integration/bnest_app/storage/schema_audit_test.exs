defmodule BnestApp.SchemaAuditTest do
  use ExUnit.Case, async: false

  alias BnestApp.Storage.Adapters.FileRecordBackend
  alias BnestApp.Storage.Adapters.SchemaAudit
  alias BnestApp.TestRuntimeRoot

  test "reports only public record type and version categories without changing bytes" do
    runtime = TestRuntimeRoot.create!("schema-audit")

    on_exit(fn ->
      if File.exists?(runtime.path), do: TestRuntimeRoot.cleanup!(runtime)
    end)

    chat = %{
      "schemaVersion" => 1,
      "recordType" => "chat",
      "ownerId" => "user-test-audit",
      "sourceImportId" => nil,
      "revision" => 0,
      "state" => %{
        "version" => 2,
        "thread_id" => nil,
        "model" => "fixture-model",
        "reasoning_effort" => "medium",
        "messages" => []
      },
      "updatedAt" => "2030-01-01T00:00:00Z"
    }

    store = FileRecordBackend.new!(runtime.path)
    assert {:ok, ^chat} = FileRecordBackend.write(store, :chat, chat["ownerId"], nil, chat)
    before = tree_digest(runtime.path)

    assert {:ok, [%{"recordType" => "chat", "schemaVersion" => 1, "result" => "pass"}]} =
             SchemaAudit.audit_root(runtime.path)

    assert tree_digest(runtime.path) == before
    refute inspect(SchemaAudit.audit_root(runtime.path)) =~ "user-test-audit"
    refute inspect(SchemaAudit.audit_root(runtime.path)) =~ runtime.path
  end

  test "rejects a path outside approved production or marked test roots" do
    assert {:error, :unsupported_root} = SchemaAudit.audit_root(System.tmp_dir!())
  end

  defp tree_digest(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(fn path -> :crypto.hash(:sha256, File.read!(path)) end)
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end
end
