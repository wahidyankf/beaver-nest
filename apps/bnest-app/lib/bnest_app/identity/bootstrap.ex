defmodule BnestApp.Identity.Bootstrap do
  @moduledoc """
  The one-time creation of the first accounts. A pending journal is written before the
  accounts, and closed after them, so a crash in between is rolled back by `recover/1` on
  the next start. Once closed, setup never reopens.
  """

  alias BnestApp.Identity
  alias BnestApp.Identity.Domain.Credentials
  alias BnestApp.Identity.Domain.Session
  alias BnestApp.Identity.Ports.IdentityStore

  @roles ~w(children parents admin)

  @spec status(IdentityStore.handle()) :: :open | :closed | {:error, atom()}
  def status(store) do
    case IdentityStore.read_bootstrap(store) do
      {:ok, %{"state" => "closed"}} ->
        :closed

      {:ok, %{"state" => "pending"}} ->
        {:error, :recovery_required}

      {:error, :missing} ->
        if IdentityStore.empty?(store), do: :open, else: {:error, :conflict}

      {:error, _reason} ->
        {:error, :invalid_state}
    end
  end

  @spec recover(IdentityStore.handle()) :: :ok | {:error, atom()}
  def recover(store) do
    :global.trans({transaction_key(store), self()}, fn -> recover_locked(store) end)
  end

  @spec create(IdentityStore.handle(), [map()]) :: {:ok, [map()]} | {:error, atom()}
  def create(store, accounts) do
    :global.trans({transaction_key(store), self()}, fn -> create_locked(store, accounts) end)
  end

  defp create_locked(store, account_inputs) do
    with :open <- status(store),
         {:ok, prepared} <- prepare_accounts(account_inputs),
         true <- Enum.any?(prepared, &("admin" in &1.account["roles"])),
         :ok <- unique_usernames(prepared),
         {:ok, journal} <- pending_journal(prepared),
         {:ok, ^journal} <- IdentityStore.put_bootstrap(store, journal),
         :ok <- write_accounts(store, prepared),
         {:ok, _closed} <- close_journal(store, journal) do
      {:ok, Enum.map(prepared, &Session.public_account(&1.account))}
    else
      false -> {:error, :admin_required}
      {:error, reason} -> {:error, reason}
      :closed -> {:error, :closed}
    end
  end

  defp prepare_accounts(accounts) when is_list(accounts) and accounts != [] do
    accounts
    |> Enum.reduce_while({:ok, []}, fn input, {:ok, prepared} ->
      case prepare_account(input) do
        {:ok, account} -> {:cont, {:ok, [account | prepared]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp prepare_accounts(_accounts), do: {:error, :accounts_required}

  defp prepare_account(%{"username" => username, "password" => password, "roles" => roles}) do
    with {:ok, {display, normalized}} <- Credentials.normalize_username(username),
         :ok <- validate_roles(roles),
         :ok <- validate_password(password),
         {:ok, verifier} <- Identity.adapter(:credential_hasher).hash(password) do
      user_id = new_id("user")
      now = timestamp()

      account = %{
        "schemaVersion" => 1,
        "recordType" => "account",
        "userId" => user_id,
        "displayUsername" => display,
        "normalizedUsername" => normalized,
        "roles" => Enum.sort(roles),
        "passwordVerifier" => verifier,
        "createdAt" => now
      }

      index = %{
        "schemaVersion" => 1,
        "recordType" => "username-index",
        "normalizedUsername" => normalized,
        "userId" => user_id
      }

      {:ok, %{account: account, index: index}}
    end
  end

  defp prepare_account(_input), do: {:error, :invalid_account}

  defp validate_roles(roles) when is_list(roles) and roles != [] do
    if Enum.uniq(roles) == roles and Enum.all?(roles, &(&1 in @roles)),
      do: :ok,
      else: {:error, :invalid_roles}
  end

  defp validate_roles(_roles), do: {:error, :invalid_roles}

  defp validate_password(password) do
    if Credentials.valid_password?(password), do: :ok, else: {:error, :invalid_password}
  end

  defp unique_usernames(prepared) do
    usernames = Enum.map(prepared, & &1.account["normalizedUsername"])
    if Enum.uniq(usernames) == usernames, do: :ok, else: {:error, :duplicate_username}
  end

  defp pending_journal(prepared) do
    journal = %{
      "schemaVersion" => 1,
      "recordType" => "bootstrap",
      "state" => "pending",
      "attemptId" => new_id("bootstrap"),
      "startedAt" => timestamp(),
      "closedAt" => nil,
      "accounts" =>
        Enum.map(prepared, fn %{account: account, index: index} ->
          %{
            "userId" => account["userId"],
            "normalizedUsername" => account["normalizedUsername"],
            "accountSha256" => digest(account),
            "indexSha256" => digest(index)
          }
        end)
    }

    {:ok, journal}
  end

  defp write_accounts(store, prepared) do
    Enum.reduce_while(prepared, :ok, fn %{account: account, index: index}, :ok ->
      with {:ok, ^account} <- IdentityStore.put_account(store, account),
           {:ok, ^index} <- IdentityStore.put_username(store, index),
           :ok <- verify_pair(store, account, index) do
        {:cont, :ok}
      else
        _failure -> {:halt, {:error, :bootstrap_write_failed}}
      end
    end)
  end

  defp verify_pair(store, account, index) do
    with {:ok, ^account} <- IdentityStore.read_account(store, account["userId"]),
         {:ok, ^index} <- IdentityStore.read_username(store, index["normalizedUsername"]) do
      :ok
    else
      _failure -> {:error, :read_back_failed}
    end
  end

  defp close_journal(store, journal) do
    closed = %{journal | "state" => "closed", "closedAt" => timestamp()}
    IdentityStore.replace_bootstrap(store, closed)
  end

  defp recover_locked(store) do
    case IdentityStore.read_bootstrap(store) do
      {:ok, %{"state" => "pending"} = journal} -> rollback_pending(store, journal)
      {:ok, %{"state" => "closed"}} -> :ok
      {:error, :missing} -> :ok
      {:error, _reason} -> {:error, :invalid_state}
    end
  end

  defp rollback_pending(store, journal) do
    result =
      Enum.reduce_while(journal["accounts"], :ok, fn reference, :ok ->
        case rollback_pair(store, reference) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with :ok <- result, do: IdentityStore.remove_bootstrap(store, journal)
  end

  defp rollback_pair(store, reference) do
    with :ok <- remove_matching_account(store, reference),
         do: remove_matching_index(store, reference)
  end

  defp remove_matching_account(store, reference) do
    case IdentityStore.read_account(store, reference["userId"]) do
      {:ok, account} ->
        if digest(account) == reference["accountSha256"],
          do: IdentityStore.remove_account(store, account),
          else: {:error, :changed}

      {:error, :missing} ->
        :ok

      {:error, _reason} ->
        {:error, :invalid_state}
    end
  end

  defp remove_matching_index(store, reference) do
    case IdentityStore.read_username(store, reference["normalizedUsername"]) do
      {:ok, index} ->
        if digest(index) == reference["indexSha256"],
          do: IdentityStore.remove_username(store, index),
          else: {:error, :changed}

      {:error, :missing} ->
        :ok

      {:error, _reason} ->
        {:error, :invalid_state}
    end
  end

  defp digest(record),
    do: :crypto.hash(:sha256, Jason.encode!(record)) |> Base.encode16(case: :lower)

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp new_id(prefix) do
    suffix = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    "#{prefix}-#{suffix}"
  end

  # One cluster-wide lock per store, so two nodes cannot bootstrap the same records at once.
  defp transaction_key(store), do: {__MODULE__, IdentityStore.lock_key(store)}
end
