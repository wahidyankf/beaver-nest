defmodule BnestApp.Preferences do
  @moduledoc """
  The Preferences bounded context: each signed-in user's explicit theme choice.

  This module is the context's application-service facade. Its adapter comes from
  application configuration under `config :bnest_app, BnestApp.Preferences`, one per port
  in `BnestApp.Preferences.Ports`, so a test can supply an in-memory double. Each function
  takes an optional `store:` handle; without one it works on the configured store's
  `new/0` handle.
  """

  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [],
    exports: [{Ports, []}]

  alias BnestApp.Preferences.Domain.Theme
  alias BnestApp.Preferences.Ports.PreferenceStore

  @type option :: {:store, PreferenceStore.handle()}

  @doc "The configured adapter for a Preferences port: `:preference_store`."
  @spec adapter(atom()) :: module()
  def adapter(port), do: :bnest_app |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(port)

  @doc "Every theme a user may choose."
  @spec themes() :: [Theme.t()]
  def themes, do: Theme.values()

  @doc """
  The theme `owner_id` chose, or `"system"` when they stored none or their preference
  cannot be read.
  """
  @spec theme(String.t(), [option()]) :: Theme.t()
  def theme(owner_id, options \\ []) do
    case PreferenceStore.read(store(options), owner_id) do
      {:ok, %{"theme" => theme}} -> theme
      {:error, _missing_or_invalid} -> Theme.default()
    end
  end

  @doc """
  Stores `theme` as the choice of `owner_id`, stamped with `now`. The caller supplies the
  time, so the stored `updatedAt` is the request's time truncated to the second.

  The write expects the revision of the preference it read, so a preference that changed
  in between is kept and its store's error (`{:error, :stale}`) returned. Choosing
  `"system"` clears the preference instead, as `clear_theme/2` does. An unknown theme is
  `{:error, :invalid_theme}`.
  """
  @spec put_theme(String.t(), term(), DateTime.t(), [option()]) :: :ok | {:error, atom()}
  def put_theme(owner_id, theme, now, options \\ []) do
    cond do
      not Theme.valid?(theme) -> {:error, :invalid_theme}
      theme == Theme.default() -> clear_theme(owner_id, options)
      true -> write_theme(store(options), owner_id, theme, now)
    end
  end

  @doc """
  Removes the preference of `owner_id`, so the system theme applies. It removes exactly
  the record it read, so one changed in between is kept (`{:error, :changed}`); with no
  preference stored it is `:ok`.
  """
  @spec clear_theme(String.t(), [option()]) :: :ok | {:error, atom()}
  def clear_theme(owner_id, options \\ []) do
    store = store(options)

    case PreferenceStore.read(store, owner_id) do
      {:ok, record} -> PreferenceStore.remove_exact(store, owner_id, record)
      {:error, :missing} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_theme(store, owner_id, theme, now) do
    with {:ok, previous} <- current(store, owner_id),
         {:ok, _record} <-
           PreferenceStore.write(
             store,
             owner_id,
             Theme.expected_revision(previous),
             Theme.record(owner_id, theme, previous, now)
           ) do
      :ok
    end
  end

  defp current(store, owner_id) do
    case PreferenceStore.read(store, owner_id) do
      {:ok, record} -> {:ok, record}
      {:error, :missing} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store(options),
    do: Keyword.get_lazy(options, :store, fn -> adapter(:preference_store).new() end)
end
