defmodule BnestApp.TestInstance.Error do
  @moduledoc false

  # Raised by the test-instance switch. `reason` is the refusal or failure kind the endpoints map
  # to a status code: `:instance_active`, `:instance_busy`, `:run_mismatch`, `:pointer_mismatch`,
  # `:not_current`, `:refused` (a directory check failed), `:spawn_failed` (with the failed `step`)
  # or `:cleanup_failed` (with the retained `path`). `detail` carries the underlying reason.

  use Boundary, top_level?: true, check: [in: false, out: false]

  defexception [:reason, :step, :path, :detail]

  @type t :: %__MODULE__{
          reason: atom(),
          step: atom() | nil,
          path: String.t() | nil,
          detail: term()
        }

  @impl true
  def message(%{reason: :spawn_failed, step: step, detail: detail}),
    do: "test instance spawn failed at #{step}: #{inspect(detail)}"

  def message(%{reason: :cleanup_failed, path: path, detail: detail}),
    do: "test instance cleanup failed at #{path}: #{inspect(detail)}"

  def message(%{reason: reason, detail: detail}) when not is_nil(detail),
    do: "test instance refused: #{reason} (#{inspect(detail)})"

  def message(%{reason: reason}), do: "test instance refused: #{reason}"
end
