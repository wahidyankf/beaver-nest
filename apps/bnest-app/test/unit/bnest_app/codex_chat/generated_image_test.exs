defmodule BnestApp.CodexChat.GeneratedImageTest do
  # ADR 007, Decision 2: the pure rules a generated image reference must meet before any file is read.
  use ExUnit.Case, async: true

  alias BnestApp.CodexChat.Domain.GeneratedImage

  @thread "01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071"
  @image_file "exec-2b5e6589-1111-2222-3333-444455556666.png"

  describe "reference/2 accepts a thread directory and a saved file name" do
    test "accepts the four raster extensions in any letter case" do
      assert GeneratedImage.reference(@thread, @image_file) == {:ok, "#{@thread}/#{@image_file}"}

      assert GeneratedImage.reference(@thread, "exec-abc123.jpg") ==
               {:ok, "#{@thread}/exec-abc123.jpg"}

      assert GeneratedImage.reference(@thread, "exec-abc123.jpeg") ==
               {:ok, "#{@thread}/exec-abc123.jpeg"}

      assert GeneratedImage.reference(@thread, "exec-abc123.gif") ==
               {:ok, "#{@thread}/exec-abc123.gif"}

      assert GeneratedImage.reference(@thread, "exec-abc123.webp") ==
               {:ok, "#{@thread}/exec-abc123.webp"}

      assert GeneratedImage.reference(@thread, "exec-ABC123.PNG") ==
               {:ok, "#{@thread}/exec-ABC123.PNG"}
    end
  end

  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A malformed or unknown generated image path is an empty not found response
  describe "reference/2 refuses anything outside the strict two-segment shape" do
    test "a thread that is empty, too long, or has no hyphen" do
      for thread <- ["", "nothyphen", String.duplicate("a", 65)] do
        assert GeneratedImage.reference(thread, @image_file) == :error,
               "accepted thread #{inspect(thread)}"
      end
    end

    test "a thread with a dot segment, a slash, a backslash, a colon or a percent sign" do
      for thread <- ["..", "a/b", "a\\b", "a:b", "a%2Fb", ".hidden"] do
        assert GeneratedImage.reference(thread, @image_file) == :error,
               "accepted thread #{inspect(thread)}"
      end
    end

    test "a file that does not start with exec-, has a bad character, or a wrong extension" do
      for file <- [
            "shot.png",
            "exec-abc.svg",
            "exec-abc.bmp",
            "exec-abc.png.txt",
            "exec-abc",
            "../exec-abc.png",
            "exec-ab/c.png",
            "exec-ab\\c.png",
            "exec-ab:c.png",
            "exec-ab%2E.png"
          ] do
        assert GeneratedImage.reference(@thread, file) == :error,
               "accepted file #{inspect(file)}"
      end
    end

    test "an empty thread or file" do
      assert GeneratedImage.reference("", @image_file) == :error
      assert GeneratedImage.reference(@thread, "") == :error
    end
  end

  test "max_bytes/0 shares the five-mebibyte image limit" do
    assert GeneratedImage.max_bytes() == 5 * 1024 * 1024
  end

  test "refuses names that are not text without reading anything" do
    assert GeneratedImage.reference(nil, @image_file) == :error
    assert GeneratedImage.reference(@thread, nil) == :error
    assert GeneratedImage.reference(nil, nil) == :error
  end
end
