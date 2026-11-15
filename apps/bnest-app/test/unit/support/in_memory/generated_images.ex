defmodule BnestApp.Test.InMemory.GeneratedImages do
  @moduledoc """
  A `BnestApp.CodexChat.Ports.GeneratedImages` double over a synthetic `generated_images`
  directory. It reads no file: the test puts each file, or a symbolic link, into an Agent it
  installs under its own supervisor.

  The double answers only what a file system would: a missing path and a symbolic link are
  `{:error, :not_found}`, and a link keeps its target, which must be a file of the synthetic
  directory. It does not enforce `max_bytes`, on purpose: the chat facade checks the size of
  every reply itself (ADR 007, Decision 2), and a test of the size limit must prove that
  check, not the double.
  """

  @behaviour BnestApp.CodexChat.Ports.GeneratedImages

  @thread "01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071"
  @synthetic_png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> "synthetic generated image"

  @doc "The thread of the seeded synthetic image."
  def thread, do: @thread

  @doc "Starts a fresh synthetic `generated_images` directory under the calling test's supervisor."
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start:
        {Agent, :start_link,
         [fn -> %{"#{@thread}/exec-seed.png" => @synthetic_png} end, [name: __MODULE__]]}
    })

    :ok
  end

  @doc "Puts `bytes` at the `thread/file` reference, replacing whatever was there."
  def put_file(path, bytes) when is_binary(path) and is_binary(bytes),
    do: Agent.update(__MODULE__, &Map.put(&1, path, bytes))

  @doc """
  Puts a symbolic link at `path` to `target`. The target must already be a file of the synthetic
  directory, so a read that followed the link would find real bytes. Every read of a link is
  refused.
  """
  def put_symlink(path, target) when is_binary(path) and is_binary(target) do
    files = Agent.get(__MODULE__, & &1)

    unless is_binary(Map.get(files, target)),
      do: raise("the link target #{inspect(target)} is not a file in the synthetic directory")

    Agent.update(__MODULE__, &Map.put(&1, path, {:symlink, target}))
  end

  @impl true
  def read(path, _max_bytes) do
    case Agent.get(__MODULE__, &Map.fetch(&1, path)) do
      {:ok, bytes} when is_binary(bytes) -> {:ok, bytes}
      _symlink_or_missing -> {:error, :not_found}
    end
  end
end
