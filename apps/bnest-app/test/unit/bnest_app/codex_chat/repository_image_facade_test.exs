defmodule BnestApp.CodexChat.RepositoryImageFacadeTest do
  # Not async: the in-memory repository is a named Agent for this test alone.
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat
  alias BnestApp.CodexChat.Domain.RepositoryImage
  alias BnestApp.Test.InMemory.RepositoryImages, as: InMemoryRepositoryImages

  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic image"

  defmodule RaisingRepositoryImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.RepositoryImages

    @impl true
    def read(path, _max_bytes), do: raise("the port was asked to read #{path}")
  end

  defmodule RecordingRepositoryImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.RepositoryImages

    @impl true
    def read(path, max_bytes) do
      send(self(), {:port_read, path, max_bytes})
      {:error, :not_found}
    end
  end

  defmodule OversizedRepositoryImages do
    @moduledoc false
    @behaviour BnestApp.CodexChat.Ports.RepositoryImages

    # A port that ignores the limit and returns one byte more than it.
    @impl true
    def read(_path, max_bytes),
      do: {:ok, <<0x89, "PNG\r\n", 0x1A, "\n">> <> :binary.copy(<<0>>, max_bytes)}
  end

  setup do
    InMemoryRepositoryImages.install()
    :ok
  end

  test "returns the media type and the bytes of a repository image" do
    InMemoryRepositoryImages.put_file("docs/shot.png", @png)

    assert CodexChat.repository_image("docs/shot.png",
             repository_images: InMemoryRepositoryImages
           ) ==
             {:ok, "image/png", @png}
  end

  test "answers :error, not a reason, for a missing file" do
    assert CodexChat.repository_image("docs/missing.png",
             repository_images: InMemoryRepositoryImages
           ) == :error
  end

  test "answers :error for a symbolic link, even one that points at a real image" do
    InMemoryRepositoryImages.put_symlink("docs/linked.png", @logo)

    assert CodexChat.repository_image("docs/linked.png",
             repository_images: InMemoryRepositoryImages
           ) ==
             :error
  end

  test "answers :error for a file that is not a raster image, whatever its name" do
    InMemoryRepositoryImages.put_file("docs/not-an-image.png", "<html>not an image</html>")

    assert CodexChat.repository_image("docs/not-an-image.png",
             repository_images: InMemoryRepositoryImages
           ) == :error
  end

  test "answers :error for a file over the size limit" do
    too_large = @png <> :binary.copy(<<0>>, RepositoryImage.max_bytes())
    InMemoryRepositoryImages.put_file("docs/too-large.png", too_large)

    assert CodexChat.repository_image("docs/too-large.png",
             repository_images: InMemoryRepositoryImages
           ) == :error
  end

  test "reads through the configured adapter when no repository_images option is given" do
    InMemoryRepositoryImages.put_file("docs/configured.png", @png)

    assert CodexChat.repository_image("docs/configured.png") == {:ok, "image/png", @png}
  end

  test "refuses a path outside the repository before the port reads anything" do
    assert CodexChat.repository_image("../../config/secret.png",
             repository_images: RaisingRepositoryImages
           ) == :error

    assert CodexChat.repository_image("data/prod/a.png",
             repository_images: RaisingRepositoryImages
           ) ==
             :error
  end

  test "asks the port for at most the size limit, and maps every port refusal to :error" do
    assert CodexChat.repository_image(@logo, repository_images: RecordingRepositoryImages) ==
             :error

    max_bytes = RepositoryImage.max_bytes()
    assert_received {:port_read, @logo, ^max_bytes}
  end

  test "refuses bytes over the limit even when the port returns them" do
    assert CodexChat.repository_image("docs/shot.png",
             repository_images: OversizedRepositoryImages
           ) ==
             :error
  end
end
