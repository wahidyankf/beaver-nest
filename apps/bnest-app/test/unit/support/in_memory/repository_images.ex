defmodule BnestApp.Test.InMemory.RepositoryImages do
  @moduledoc """
  A `BnestApp.CodexChat.Ports.RepositoryImages` double over a synthetic repository. It reads no
  file: the test puts each file, or a symbolic link, into an Agent it installs under its own
  supervisor.

  The double answers only what a file system would: a missing path and a symbolic link are
  `{:error, :not_found}`, and a link keeps its target, which must be a file of the repository. It
  does not enforce `max_bytes`, on purpose: the chat facade checks the size of every reply itself
  (ADR 002, Decision 2), and a test of the size limit must prove that check, not the double.

  The repository always holds the Beaver Nest logo as a synthetic PNG, so the unit layer can
  show that image the way the browser suite shows the real one.
  """

  @behaviour BnestApp.CodexChat.Ports.RepositoryImages

  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
  @synthetic_png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> "synthetic logo"

  @doc "Starts a fresh synthetic repository under the calling test's supervisor."
  def install do
    if GenServer.whereis(__MODULE__), do: ExUnit.Callbacks.stop_supervised!(__MODULE__)

    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> %{@logo => @synthetic_png} end, [name: __MODULE__]]}
    })

    :ok
  end

  @doc "Starts the synthetic repository unless this test already installed one."
  def ensure_installed do
    if GenServer.whereis(__MODULE__), do: :ok, else: install()
  end

  @doc "Puts `bytes` at the repository-relative `path`, replacing whatever was there."
  def put_file(path, bytes) when is_binary(path) and is_binary(bytes),
    do: Agent.update(__MODULE__, &Map.put(&1, path, bytes))

  @doc """
  Puts a symbolic link at `path` to `target`. The target must already be a file of the synthetic
  repository, so a read that followed the link would find real bytes. Every read of a link is
  refused.
  """
  def put_symlink(path, target) when is_binary(path) and is_binary(target) do
    files = Agent.get(__MODULE__, & &1)

    unless is_binary(Map.get(files, target)),
      do: raise("the link target #{inspect(target)} is not a file in the synthetic repository")

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
