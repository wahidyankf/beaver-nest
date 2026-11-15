defmodule BnestApp.CodexChat.Adapters.GeneratedImageFilesTest do
  # ADR 007, Decision 2 (rules 2 and 3): the file adapter over a synthetic Codex home. The home and
  # every file the tests place beside it live in one isolated run root, removed after each test.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.GeneratedImageFiles
  alias BnestApp.CodexChat.Domain.GeneratedImage
  alias BnestApp.TestRuntimeRoot

  @thread "01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071"
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"

  setup do
    runtime = TestRuntimeRoot.create!("codex-generated-image-files")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    # The Codex home is `home/` under the run root, so `../` reaches `outside/`, real files the
    # adapter must still refuse.
    home = Path.join(runtime.path, "home")
    File.mkdir_p!(generated_dir(home))
    write!(runtime.path, "outside.png", @png)

    codex = Application.fetch_env!(:bnest_app, :codex)
    Application.put_env(:bnest_app, :codex, Keyword.put(codex, :codex_home, home))
    on_exit(fn -> Application.put_env(:bnest_app, :codex, codex) end)

    {:ok, runtime: runtime.path, home: home}
  end

  describe "read/2 returns the bytes of a regular file below generated_images" do
    test "a file in a thread directory", %{home: home} do
      write!(generated_dir(home), "#{@thread}/exec-abc.png", @png)

      assert GeneratedImageFiles.read("#{@thread}/exec-abc.png", GeneratedImage.max_bytes()) ==
               {:ok, @png}
    end

    test "an empty regular file is read as empty bytes, which the signature check then refuses",
         %{home: home} do
      write!(generated_dir(home), "#{@thread}/exec-empty.png", "")

      assert GeneratedImageFiles.read("#{@thread}/exec-empty.png", GeneratedImage.max_bytes()) ==
               {:ok, ""}
    end

    test "a missing file is not found" do
      assert GeneratedImageFiles.read("#{@thread}/exec-missing.png", GeneratedImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "reads the Codex home from the configuration at each call", %{
      runtime: runtime,
      home: home
    } do
      write!(generated_dir(home), "#{@thread}/exec-a.png", "first")
      other = Path.join(runtime, "other-home")
      File.mkdir_p!(generated_dir(other))
      write!(generated_dir(other), "#{@thread}/exec-a.png", "second")

      assert GeneratedImageFiles.read("#{@thread}/exec-a.png", 64) == {:ok, "first"}

      codex = Application.fetch_env!(:bnest_app, :codex)
      Application.put_env(:bnest_app, :codex, Keyword.put(codex, :codex_home, other))

      assert GeneratedImageFiles.read("#{@thread}/exec-a.png", 64) == {:ok, "second"}
    end

    test "a Codex home reached through a symbolic link is trusted", %{
      runtime: runtime,
      home: home
    } do
      write!(generated_dir(home), "#{@thread}/exec-a.png", @png)
      link = Path.join(runtime, "home-link")
      File.ln_s!(home, link)

      codex = Application.fetch_env!(:bnest_app, :codex)
      Application.put_env(:bnest_app, :codex, Keyword.put(codex, :codex_home, link))

      assert GeneratedImageFiles.read("#{@thread}/exec-a.png", GeneratedImage.max_bytes()) ==
               {:ok, @png}
    end
  end

  describe "read/2 refuses every path that is not one generated file below the root" do
    test "a wrong segment count, traversal, absolute, dot, backslash and NUL segments", %{
      home: home
    } do
      write!(generated_dir(home), "#{@thread}/exec-a.png", @png)

      for path <- [
            "exec-a.png",
            "#{@thread}/exec-a.png/extra",
            "../outside.png",
            "#{@thread}/../../outside.png",
            "#{@thread}/../#{@thread}/exec-a.png",
            "/outside.png",
            "#{@thread}//exec-a.png",
            "",
            "..",
            "#{@thread}/exec-a\0.png"
          ] do
        assert GeneratedImageFiles.read(path, GeneratedImage.max_bytes()) ==
                 {:error, :not_found},
               "read #{inspect(path)}"
      end
    end

    test "a symbolic link to a file outside the generated directory", %{
      runtime: runtime,
      home: home
    } do
      File.mkdir_p!(Path.join(generated_dir(home), @thread))

      File.ln_s!(
        Path.join(runtime, "outside.png"),
        Path.join(generated_dir(home), "#{@thread}/exec-linked.png")
      )

      assert GeneratedImageFiles.read("#{@thread}/exec-linked.png", GeneratedImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a symbolic link to a file inside the generated directory", %{home: home} do
      write!(generated_dir(home), "#{@thread}/exec-real.png", @png)

      File.ln_s!(
        Path.join(generated_dir(home), "#{@thread}/exec-real.png"),
        Path.join(generated_dir(home), "#{@thread}/exec-linked.png")
      )

      assert GeneratedImageFiles.read("#{@thread}/exec-linked.png", GeneratedImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a symbolic link in the thread position, even when the file it reaches is a real image",
         %{runtime: runtime, home: home} do
      write!(runtime, "elsewhere/exec-a.png", @png)
      File.ln_s!(Path.join(runtime, "elsewhere"), Path.join(generated_dir(home), "linked-thread"))

      assert GeneratedImageFiles.read("linked-thread/exec-a.png", GeneratedImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a thread position that is a regular file", %{home: home} do
      write!(generated_dir(home), "not-a-dir", @png)

      assert GeneratedImageFiles.read("not-a-dir/exec-a.png", GeneratedImage.max_bytes()) ==
               {:error, :not_found}
    end
  end

  describe "read/2 enforces the byte limit with a bounded read" do
    test "a file of exactly the limit is read, and one byte more is refused", %{home: home} do
      write!(generated_dir(home), "#{@thread}/exec-exact.png", "0123456789abcdef")
      write!(generated_dir(home), "#{@thread}/exec-over.png", "0123456789abcdef0")

      assert GeneratedImageFiles.read("#{@thread}/exec-exact.png", 16) ==
               {:ok, "0123456789abcdef"}

      assert GeneratedImageFiles.read("#{@thread}/exec-over.png", 16) == {:error, :not_found}
    end

    test "a file over the generated image limit is refused, and one at the limit is read",
         %{home: home} do
      max = GeneratedImage.max_bytes()
      write!(generated_dir(home), "#{@thread}/exec-at-limit.png", :binary.copy(<<0>>, max))
      write!(generated_dir(home), "#{@thread}/exec-over-limit.png", :binary.copy(<<0>>, max + 1))

      assert {:ok, at_limit} =
               GeneratedImageFiles.read("#{@thread}/exec-at-limit.png", max)

      assert byte_size(at_limit) == max

      assert GeneratedImageFiles.read("#{@thread}/exec-over-limit.png", max) ==
               {:error, :not_found}
    end
  end

  defp generated_dir(home), do: Path.join(home, "generated_images")

  defp write!(root, relative, bytes) do
    full = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, bytes)
  end
end
