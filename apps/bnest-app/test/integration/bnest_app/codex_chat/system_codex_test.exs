defmodule BnestApp.CodexChat.Adapters.SystemCodexTest do
  # The host Codex lookup skips the SDK's bundled `node_modules` shim: each test builds its own
  # isolated PATH entries below one run root, removed after the test, and resolves over an
  # explicit PATH string, so no test mutates the process environment.
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Adapters.SystemCodex
  alias BnestApp.TestRuntimeRoot

  setup do
    runtime = TestRuntimeRoot.create!("system-codex")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)
    {:ok, root: runtime.path}
  end

  test "returns the first codex outside node_modules", %{root: root} do
    shim_dir = Path.join(root, "shim/node_modules/.bin")
    host_dir = Path.join(root, "host/bin")
    write_executable!(shim_dir)
    host_codex = write_executable!(host_dir)

    assert SystemCodex.resolve(Enum.join([shim_dir, host_dir], ":")) == host_codex
  end

  test "returns nil when only a node_modules shim exists", %{root: root} do
    shim_dir = Path.join(root, "only-shim/node_modules/.bin")
    write_executable!(shim_dir)

    assert SystemCodex.resolve(shim_dir) |> is_nil()
  end

  test "returns nil for an empty PATH" do
    assert SystemCodex.resolve("") |> is_nil()
  end

  test "a tilde entry does not qualify" do
    assert SystemCodex.resolve("~") |> is_nil()
    assert SystemCodex.resolve("~/bin") |> is_nil()
  end

  test "a symlink outside node_modules pointing into it does not qualify", %{root: root} do
    target_dir = Path.join(root, "linked-target/node_modules/.bin")
    write_executable!(target_dir)

    link_dir = Path.join(root, "plain-bin")
    File.mkdir_p!(link_dir)
    File.ln_s!(Path.join(target_dir, "codex"), Path.join(link_dir, "codex"))

    assert SystemCodex.resolve(link_dir) |> is_nil()
  end

  test "a non-executable codex does not qualify", %{root: root} do
    dir = Path.join(root, "not-executable")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "codex"), "#!/bin/sh\nexit 0\n")

    assert SystemCodex.resolve(dir) |> is_nil()
  end

  defp write_executable!(dir) do
    path = Path.join(dir, "codex")
    File.mkdir_p!(dir)
    File.write!(path, "#!/bin/sh\nexit 0\n")
    File.chmod!(path, 0o755)
    Path.expand(path)
  end
end
