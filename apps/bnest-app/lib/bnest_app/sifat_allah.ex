defmodule BnestApp.SifatAllah do
  @moduledoc """
  The Sifat Allah bounded context: each learner's saved learning progress.

  This module is the context's application-service facade. Its adapter comes from
  application configuration under `config :bnest_app, BnestApp.SifatAllah`, one per port in
  `BnestApp.SifatAllah.Ports`, so a test can supply an in-memory double. Each function takes
  an optional `store:` handle; without one it works on the configured store's `new/0`
  handle. The curriculum and quiz rules are the exported, pure
  `BnestApp.SifatAllah.Domain.Quiz`, which callers use to render and answer.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [],
    exports: [{Domain, []}, {Ports, []}]

  alias BnestApp.SifatAllah.Domain.ProgressRecord
  alias BnestApp.SifatAllah.Ports.ProgressStore

  @type option :: {:store, ProgressStore.handle()} | {:now, DateTime.t()}

  @doc "The configured adapter for a Sifat Allah port: `:progress_store`."
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc """
  The `sifat-allah-progress` record `owner_id` saved last, or the store's error:
  `{:error, :missing}` when they saved none.
  """
  @spec load_progress(String.t(), [option()]) :: {:ok, map()} | {:error, atom()}
  def load_progress(owner_id, options \\ []),
    do: ProgressStore.read(store(options), owner_id)

  @doc """
  Saves the learning `snapshot` (the progress with the learner's session under `"session"`)
  of `owner_id` over `previous`, the record it last loaded or saved (`nil` for none), and
  returns the stored record.

  The write expects the revision of `previous`, so progress that changed in between is kept
  and the store's error (`{:error, :stale}`) returned. The record is stamped with the `now:`
  option, the current time by default, truncated to the second.
  """
  @spec save_progress(String.t(), map(), map() | nil, [option()]) ::
          {:ok, map()} | {:error, atom()}
  def save_progress(owner_id, snapshot, previous, options \\ []) do
    now = Keyword.get_lazy(options, :now, &DateTime.utc_now/0)

    ProgressStore.write(
      store(options),
      owner_id,
      ProgressRecord.expected_revision(previous),
      ProgressRecord.record(owner_id, snapshot, previous, now)
    )
  end

  defp store(options),
    do: Keyword.get_lazy(options, :store, fn -> adapter(:progress_store).new() end)
end
