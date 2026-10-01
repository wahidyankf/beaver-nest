defmodule BnestApp.Storage.Ports.RecordKind do
  @moduledoc """
  A record kind that another context owns, such as the chat transcript or the Sifat Allah
  progress. Storage keeps the record envelope (owner, revision, timestamps) and asks the
  owning context, through this port, whether the payload is valid and how a browser source
  becomes one. Configuration registers the kinds, so Storage never depends on their owners.
  """

  @doc "The repository type atom, such as `:chat`."
  @callback kind() :: atom()

  @doc "The `recordType` string stored in every record of this kind."
  @callback record_type() :: String.t()

  @doc "The browser storage area and key whose payload imports into this kind."
  @callback source() :: {String.t(), String.t()}

  @doc "Whether the kind-owned fields of a record carrying this kind's envelope are valid."
  @callback valid?(record :: map()) :: boolean()

  @doc "The kind-owned record fields for a decoded browser payload."
  @callback normalize(source :: term()) :: {:ok, map()} | :error
end
