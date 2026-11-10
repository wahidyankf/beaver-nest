defmodule BnestApp.CodexChat.Ports.RepositoryImages do
  @moduledoc """
  Reads one repository file for the Codex chat image route.

  An implementation returns the bytes of a regular file at a repository-relative path, at most
  `max_bytes` long. Every refusal is `{:error, :not_found}`: a missing file, a symbolic link below
  the repository root, a file over the limit, or a read error. The route answers all of them
  the same way, so the caller cannot tell them apart.
  """

  @callback read(path :: String.t(), max_bytes :: pos_integer()) ::
              {:ok, binary()} | {:error, :not_found}
end
