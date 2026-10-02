defmodule BnestApp.Storage.Ports.FlatSource do
  @moduledoc """
  The legacy flat-file tree the one-time SQLite migration reads: every path under a root,
  and the bytes of one source.
  """

  @doc "Every path under `flat_root`, relative to it, in no particular order."
  @callback list(flat_root :: String.t()) :: [String.t()]

  @doc "The bytes of one source; raises when the source cannot be read."
  @callback read!(flat_root :: String.t(), relative_path :: String.t()) :: binary()
end
