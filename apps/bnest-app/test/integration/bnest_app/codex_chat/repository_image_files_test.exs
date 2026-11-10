defmodule BnestApp.CodexChat.Adapters.RepositoryImageFilesTest do
  # ADR 002, Decision 2 (rules 2 and 3): the file adapter over a synthetic repository. The repository and
  # every file the tests place beside it live in one isolated run root, removed after each test.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.RepositoryImageFiles
  alias BnestApp.CodexChat.Domain.RepositoryImage
  alias BnestApp.TestRuntimeRoot

  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"

  setup do
    runtime = TestRuntimeRoot.create!("codex-image-files")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    # The repository is `repo/` under the run root, so `../` reaches `outside.png`, a real file the
    # adapter must still refuse.
    repository = Path.join(runtime.path, "repo")
    File.mkdir_p!(repository)
    write!(runtime.path, "outside.png", @png)

    codex = Application.fetch_env!(:bnest_app, :codex)
    Application.put_env(:bnest_app, :codex, Keyword.put(codex, :working_directory, repository))
    on_exit(fn -> Application.put_env(:bnest_app, :codex, codex) end)

    {:ok, runtime: runtime.path, repository: repository}
  end

  describe "read/2 returns the bytes of a regular file below the working directory" do
    test "a file in a nested directory", %{repository: repository} do
      write!(repository, "docs/shots/a.png", @png)

      assert RepositoryImageFiles.read("docs/shots/a.png", RepositoryImage.max_bytes()) ==
               {:ok, @png}
    end

    test "a file at the top of the repository", %{repository: repository} do
      write!(repository, "a.png", @png)

      assert RepositoryImageFiles.read("a.png", RepositoryImage.max_bytes()) == {:ok, @png}
    end

    test "an empty regular file is read as empty bytes, which the signature check then refuses",
         %{repository: repository} do
      write!(repository, "empty.png", "")

      assert RepositoryImageFiles.read("empty.png", RepositoryImage.max_bytes()) == {:ok, ""}
    end

    test "a missing file is not found" do
      assert RepositoryImageFiles.read("docs/missing.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "reads the working directory from the configuration at each call", %{
      runtime: runtime,
      repository: repository
    } do
      write!(repository, "a.png", "first")
      other = Path.join(runtime, "other")
      write!(other, "a.png", "second")

      assert RepositoryImageFiles.read("a.png", 64) == {:ok, "first"}

      codex = Application.fetch_env!(:bnest_app, :codex)
      Application.put_env(:bnest_app, :codex, Keyword.put(codex, :working_directory, other))

      assert RepositoryImageFiles.read("a.png", 64) == {:ok, "second"}
    end

    test "a working directory reached through a symbolic link is trusted", %{
      runtime: runtime,
      repository: repository
    } do
      write!(repository, "a.png", @png)
      link = Path.join(runtime, "repo-link")
      File.ln_s!(repository, link)

      codex = Application.fetch_env!(:bnest_app, :codex)
      Application.put_env(:bnest_app, :codex, Keyword.put(codex, :working_directory, link))

      assert RepositoryImageFiles.read("a.png", RepositoryImage.max_bytes()) == {:ok, @png}
    end
  end

  describe "read/2 refuses every path that leaves or names something other than a file below the root" do
    test "traversal, absolute, empty, dot, backslash and NUL segments", %{repository: repository} do
      write!(repository, "docs/a.png", @png)

      for path <- [
            "../outside.png",
            "docs/../../outside.png",
            "docs/../docs/a.png",
            "/outside.png",
            "./docs/a.png",
            "docs//a.png",
            "docs/a.png/",
            "",
            "..",
            "docs\\..\\..\\outside.png",
            "docs/a\0.png"
          ] do
        assert RepositoryImageFiles.read(path, RepositoryImage.max_bytes()) ==
                 {:error, :not_found},
               "read #{inspect(path)}"
      end
    end

    test "a symbolic link to a file outside the repository", %{
      runtime: runtime,
      repository: repository
    } do
      File.mkdir_p!(Path.join(repository, "docs"))
      File.ln_s!(Path.join(runtime, "outside.png"), Path.join(repository, "docs/linked.png"))

      assert RepositoryImageFiles.read("docs/linked.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a symbolic link to a file inside the repository", %{repository: repository} do
      write!(repository, "docs/real.png", @png)
      File.ln_s!(Path.join(repository, "docs/real.png"), Path.join(repository, "docs/linked.png"))

      assert RepositoryImageFiles.read("docs/linked.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a symbolic link in a parent directory, even when the file it reaches is a real image",
         %{
           runtime: runtime,
           repository: repository
         } do
      write!(runtime, "elsewhere/a.png", @png)
      File.ln_s!(Path.join(runtime, "elsewhere"), Path.join(repository, "shots"))

      assert RepositoryImageFiles.read("shots/a.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a parent that is a regular file", %{repository: repository} do
      write!(repository, "docs/a.png", @png)

      assert RepositoryImageFiles.read("docs/a.png/b.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a directory whose name ends in .png", %{repository: repository} do
      File.mkdir_p!(Path.join(repository, "docs/dir.png"))

      assert RepositoryImageFiles.read("docs/dir.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end

    test "a named pipe is refused without being opened", %{repository: repository} do
      pipe = Path.join(repository, "pipe.png")
      assert {_output, 0} = System.cmd("mkfifo", [pipe])

      assert RepositoryImageFiles.read("pipe.png", RepositoryImage.max_bytes()) ==
               {:error, :not_found}
    end
  end

  describe "read/2 enforces the byte limit with a bounded read" do
    test "a file of exactly the limit is read, and one byte more is refused", %{
      repository: repository
    } do
      write!(repository, "exact.png", "0123456789abcdef")
      write!(repository, "over.png", "0123456789abcdef0")

      assert RepositoryImageFiles.read("exact.png", 16) == {:ok, "0123456789abcdef"}
      assert RepositoryImageFiles.read("over.png", 16) == {:error, :not_found}
    end

    test "a file over the repository image limit is refused, and one at the limit is read", %{
      repository: repository
    } do
      max = RepositoryImage.max_bytes()
      write!(repository, "at-limit.png", :binary.copy(<<0>>, max))
      write!(repository, "over-limit.png", :binary.copy(<<0>>, max + 1))

      assert {:ok, at_limit} = RepositoryImageFiles.read("at-limit.png", max)
      assert byte_size(at_limit) == max
      assert RepositoryImageFiles.read("over-limit.png", max) == {:error, :not_found}
    end
  end

  defp write!(root, relative, bytes) do
    full = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, bytes)
  end
end
