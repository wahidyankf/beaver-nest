defmodule BnestApp.Backup.Adapters.FileConfigStore do
  @moduledoc """
  `BnestApp.Backup.Ports.ConfigStore` over one private JSON file.

  The file is `BNEST_BACKUP_CONFIG`, else the `:backup_config_path` application setting
  (which `config/test.exs` points at each test run's own path), else the operator's real
  `~/.config/bnest/backup.json`, in that order. A test therefore never reads or writes the
  real file, whose destination is the production backup directory. The default repository
  is the `:backup_repository_root` application setting, which only `config/test.exs` sets,
  else `BNEST_REPOSITORY_ROOT`, else the checkout this module was compiled in.
  """

  @behaviour BnestApp.Backup.Ports.ConfigStore

  @compiled_repository_root Path.expand("../../../../../..", __DIR__)

  @impl true
  def new, do: %{adapter: __MODULE__}

  @impl true
  def read(_store) do
    case File.read(config_path()) do
      {:ok, bytes} ->
        case Jason.decode(bytes) do
          {:ok, document} -> {:ok, document}
          {:error, _invalid_json} -> {:error, :invalid_config}
        end

      {:error, :enoent} ->
        {:error, :absent}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  # The parent directory is made private only when it is the operator's own (no
  # `BNEST_BACKUP_CONFIG`); an explicitly named file's directory is left as its owner set it.
  @impl true
  def write(_store, document) do
    path = config_path()
    parent = Path.dirname(path)
    File.mkdir_p!(parent)

    if is_nil(System.get_env("BNEST_BACKUP_CONFIG")) do
      File.chmod!(parent, 0o700)
    end

    temporary = path <> ".partial-" <> random_id()
    File.write!(temporary, Jason.encode!(document))
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, path)
    :ok
  rescue
    File.Error -> {:error, :config_write_failed}
  end

  @impl true
  def config_path(_store), do: config_path()

  @impl true
  def repository_root(_store), do: repository_root()

  @doc "The repository whose ignored `data/backup` is the default destination."
  @spec repository_root() :: String.t()
  def repository_root do
    # The test-only setting wins over the variable: the deployment exports
    # `BNEST_REPOSITORY_ROOT` naming the permanent checkout, whose `data/backup` is the
    # production backup directory, so a test inheriting it must still resolve its own run's
    # root. Production configuration never sets `:backup_repository_root`.
    Application.get_env(:bnest_app, :backup_repository_root) ||
      System.get_env("BNEST_REPOSITORY_ROOT") || @compiled_repository_root
  end

  @doc "The configuration file, resolved in the order the module documentation gives."
  @spec config_path() :: String.t()
  def config_path do
    System.get_env("BNEST_BACKUP_CONFIG") ||
      Application.get_env(:bnest_app, :backup_config_path) ||
      Path.expand("~/.config/bnest/backup.json")
  end

  defp random_id, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
