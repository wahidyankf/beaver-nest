defmodule BnestApp.CodexChat.GeneratedImageFacadeTest do
  # ADR 007, Decision 2: the generated-image route's facade, mirroring the repository-image one.
  # Not async: the in-memory generated images are a named Agent for this test alone.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.GeneratedImage
  alias BnestApp.Test.InMemory.GeneratedImages, as: InMemoryGeneratedImages

  @thread "01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071"
  @image_file "exec-2b5e6589-1111-2222-3333-444455556666.png"
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic image"

  defmodule RaisingGeneratedImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.GeneratedImages

    @impl true
    def read(path, _max_bytes), do: raise("the port was asked to read #{path}")
  end

  defmodule RecordingGeneratedImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.GeneratedImages

    @impl true
    def read(path, max_bytes) do
      send(self(), {:port_read, path, max_bytes})
      {:error, :not_found}
    end
  end

  defmodule OversizedGeneratedImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.GeneratedImages

    # A port that ignores the limit and returns one byte more than it.
    @impl true
    def read(_path, max_bytes),
      do: {:ok, <<0x89, "PNG\r\n", 0x1A, "\n">> <> :binary.copy(<<0>>, max_bytes)}
  end

  setup do
    InMemoryGeneratedImages.install()
    :ok
  end

  test "returns the media type and the bytes of a generated image" do
    InMemoryGeneratedImages.put_file("#{@thread}/#{@image_file}", @png)

    assert CodexChat.generated_image(@thread, @image_file,
             generated_images: InMemoryGeneratedImages
           ) ==
             {:ok, "image/png", @png}
  end

  test "answers :error, not a reason, for a missing file" do
    assert CodexChat.generated_image(@thread, "exec-missing.png",
             generated_images: InMemoryGeneratedImages
           ) == :error
  end

  test "answers :error for a symbolic link, even one that points at a real image" do
    InMemoryGeneratedImages.put_symlink(
      "#{@thread}/exec-linked.png",
      "#{InMemoryGeneratedImages.thread()}/exec-seed.png"
    )

    assert CodexChat.generated_image(@thread, "exec-linked.png",
             generated_images: InMemoryGeneratedImages
           ) ==
             :error
  end

  test "answers :error for a file that is not a raster image, whatever its name" do
    InMemoryGeneratedImages.put_file(
      "#{@thread}/exec-not-an-image.png",
      "<html>not an image</html>"
    )

    assert CodexChat.generated_image(@thread, "exec-not-an-image.png",
             generated_images: InMemoryGeneratedImages
           ) == :error
  end

  test "answers :error for a file over the size limit" do
    too_large = @png <> :binary.copy(<<0>>, GeneratedImage.max_bytes())
    InMemoryGeneratedImages.put_file("#{@thread}/exec-too-large.png", too_large)

    assert CodexChat.generated_image(@thread, "exec-too-large.png",
             generated_images: InMemoryGeneratedImages
           ) == :error
  end

  test "refuses a bad name before the port reads anything" do
    assert CodexChat.generated_image("../outside", @image_file,
             generated_images: RaisingGeneratedImages
           ) ==
             :error

    assert CodexChat.generated_image(@thread, "shot.svg",
             generated_images: RaisingGeneratedImages
           ) ==
             :error
  end

  test "asks the port for at most the size limit, and maps every port refusal to :error" do
    assert CodexChat.generated_image(@thread, "exec-missing.png",
             generated_images: RecordingGeneratedImages
           ) ==
             :error

    max_bytes = GeneratedImage.max_bytes()
    assert_received {:port_read, "#{@thread}/exec-missing.png", ^max_bytes}
  end

  test "refuses bytes over the limit even when the port returns them" do
    assert CodexChat.generated_image(@thread, @image_file,
             generated_images: OversizedGeneratedImages
           ) ==
             :error
  end

  test "looks up the configured adapter when no option replaces it" do
    assert CodexChat.generated_image("../outside", @image_file) == :error
  end
end
