defmodule BnestApp.CodexChat.RepositoryImageTest do
  # ADR 002, Decision 2: the pure rules a repository image must meet before any file is read.
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.RepositoryImage

  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  describe "reference/1 accepts a repository-relative raster path" do
    test "accepts the four raster extensions in any letter case" do
      assert RepositoryImage.reference(@logo) == {:ok, @logo}
      assert RepositoryImage.reference("docs/photo.jpg") == {:ok, "docs/photo.jpg"}
      assert RepositoryImage.reference("docs/photo.jpeg") == {:ok, "docs/photo.jpeg"}
      assert RepositoryImage.reference("docs/anim.gif") == {:ok, "docs/anim.gif"}
      assert RepositoryImage.reference("docs/shot.webp") == {:ok, "docs/shot.webp"}
      assert RepositoryImage.reference("docs/SHOT.PNG") == {:ok, "docs/SHOT.PNG"}
    end

    test "drops one leading ./" do
      assert RepositoryImage.reference("./docs/shot.png") == {:ok, "docs/shot.png"}
    end
  end

  describe "reference/1 refuses a path that is not a repository image reference" do
    test "absolute paths, backslashes, NUL bytes and any scheme" do
      for path <- [
            "/etc/passwd.png",
            "\\etc\\passwd.png",
            "docs\\a.png",
            "docs/a\0.png",
            "C:/a.png"
          ] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end

    test "dot segments, empty segments and a trailing slash" do
      for path <- ["../a.png", "docs/../a.png", "docs/./a.png", "docs//a.png", "docs/a.png/", ""] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end

    test "dot-prefixed segments, which hide secrets such as .env and .git" do
      for path <- [".env/a.png", ".git/config.png", "docs/.hidden/a.png", "./.codex/a.png"] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end

    test "runtime-data, tool and build directories" do
      for path <- [
            "data/a.png",
            "node_modules/x/a.png",
            "local-tmp/a.png",
            "generated-reports/a.png",
            "worktrees/task/a.png",
            "_build/a.png",
            "deps/a.png",
            "test-results/a.png",
            "playwright-report/a.png",
            "blob-report/a.png"
          ] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end

    test "the same runtime-data, tool and build directories in any letter case" do
      # macOS and Windows treat `Data` and `data` as one folder, so the deny set compares without case.
      for path <- [
            "Data/prod/a.png",
            "DATA/prod/a.png",
            "Node_Modules/x/a.png",
            "WORKTREES/task/a.png",
            "Local-Tmp/a.png",
            "Generated-Reports/a.png",
            "_BUILD/a.png",
            "Test-Results/a.png",
            "Playwright-Report/a.png",
            "Blob-Report/a.png"
          ] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end

    test "a percent sign left after the one decoding, which means double encoding" do
      assert RepositoryImage.reference("docs/100%25.png") == :error
    end

    test "SVG and every other extension, and no extension at all" do
      for path <- ["docs/a.svg", "docs/a.bmp", "docs/a.pdf", "docs/a.png.txt", "docs/a"] do
        assert RepositoryImage.reference(path) == :error, "accepted #{inspect(path)}"
      end
    end
  end

  describe "signature/1 names the raster type of bytes that start with a raster signature" do
    test "PNG, JPEG, GIF and WebP" do
      assert RepositoryImage.signature(<<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 13>>) ==
               {:ok, "image/png"}

      assert RepositoryImage.signature(<<0xFF, 0xD8, 0xFF, 0xE0, 0, 16>>) == {:ok, "image/jpeg"}
      assert RepositoryImage.signature("GIF87a" <> <<1, 0>>) == {:ok, "image/gif"}
      assert RepositoryImage.signature("GIF89a" <> <<1, 0>>) == {:ok, "image/gif"}

      assert RepositoryImage.signature("RIFF" <> <<12, 0, 0, 0>> <> "WEBPVP8 ") ==
               {:ok, "image/webp"}
    end

    test "text, HTML, SVG, other RIFF containers and empty bytes are refused" do
      for bytes <- [
            "<html><script>alert(1)</script></html>",
            "<svg onload=\"alert(1)\"></svg>",
            "plain text",
            "RIFF" <> <<12, 0, 0, 0>> <> "WAVEfmt ",
            ""
          ] do
        assert RepositoryImage.signature(bytes) == :error, "accepted #{inspect(bytes)}"
      end
    end
  end

  test "max_bytes/0 is five mebibytes" do
    assert RepositoryImage.max_bytes() == 5 * 1024 * 1024
  end
end
