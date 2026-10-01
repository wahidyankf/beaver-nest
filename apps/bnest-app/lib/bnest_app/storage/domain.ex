defmodule BnestApp.Storage.Domain do
  @moduledoc """
  The Storage domain: record schemas, browser-source normalization, import manifests, the
  flat-file migration assessment, and storage locations. Pure: no file, process, clock, or
  database access. `Jason` is allowed because canonical JSON is a domain value.
  """

  use Boundary, type: :strict, deps: [Jason], exports: :all
end
