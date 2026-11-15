defmodule BnestApp.CodexChat.Ports.GeneratedImages do
  @moduledoc """
  Reads one Codex-generated image for the generated-image route.

  An implementation returns the bytes of a regular file at a `thread/file` reference below
  the Codex home's `generated_images` directory, at most `max_bytes` long. Every refusal is
  `{:error, :not_found}`: a missing file, a symbolic link below the root, a file over the
  limit, or a read error. The route answers all of them the same way, so the caller cannot
  tell them apart.
  """

  @callback read(path :: String.t(), max_bytes :: pos_integer()) ::
              {:ok, binary()} | {:error, :not_found}
end
