defmodule BnestApp.Storage.Adapters.LocalFlatSource do
  @moduledoc "The legacy flat-file tree on this host's file system."

  @behaviour BnestApp.Storage.Ports.FlatSource

  @impl true
  def list(flat_root) do
    flat_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, flat_root))
  end

  @impl true
  def read!(flat_root, relative_path), do: File.read!(Path.join(flat_root, relative_path))
end
