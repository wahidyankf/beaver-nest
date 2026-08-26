defmodule BnestAppWeb.BootstrapController do
  use BnestAppWeb, :controller

  alias BnestApp.Identity

  def create(conn, %{"confirm" => "closed", "accounts" => account_params}) do
    with :open <- Identity.setup_status(),
         {:ok, accounts} <- decode_accounts(account_params),
         {:ok, _created} <- Identity.bootstrap(accounts) do
      conn
      |> put_flash(:info, "Initial accounts created. Setup is now permanently closed.")
      |> redirect(to: "/login")
    else
      :closed -> not_found(conn)
      {:error, :closed} -> not_found(conn)
      {:error, reason} -> setup_error(conn, reason, account_params)
      _invalid -> setup_error(conn, :invalid_account, account_params)
    end
  end

  def create(conn, params) do
    case Identity.setup_status() do
      :closed -> not_found(conn)
      _other -> setup_error(conn, :confirmation_required, params["accounts"])
    end
  end

  defp decode_accounts(params) when is_map(params) do
    accounts =
      params
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {_key, account} ->
        %{
          "username" => account["username"],
          "password" => account["password"],
          "passwordConfirmation" => account["password_confirmation"],
          "roles" => selected_roles(account["roles"] || %{})
        }
      end)

    if Enum.all?(accounts, &passwords_match?/1) do
      {:ok, Enum.map(accounts, &Map.delete(&1, "passwordConfirmation"))}
    else
      {:error, :password_mismatch}
    end
  end

  defp decode_accounts(_params), do: {:error, :invalid_account}

  defp passwords_match?(account),
    do: account["password"] == account["passwordConfirmation"]

  defp selected_roles(roles) when is_map(roles) do
    roles
    |> Enum.filter(fn {_role, selected} -> selected in ["true", "on"] end)
    |> Enum.map(fn {role, _selected} -> role end)
  end

  defp selected_roles(_roles), do: []

  defp setup_error(conn, reason, account_params) do
    message =
      case reason do
        :admin_required -> "At least one initial account must have the admin role."
        :duplicate_username -> "Each username must be unique regardless of letter case."
        :invalid_username -> "Use 1–32 letters, numbers, dots, dashes, or underscores."
        :invalid_password -> "Passwords must contain 15–128 characters."
        :password_mismatch -> "Each password and confirmation must match."
        :confirmation_required -> "Confirm that setup closes permanently before continuing."
        _other -> "Check every account and try setup again. Password fields were cleared."
      end

    conn
    |> put_flash(:setup_draft, %{accounts: safe_setup_draft(account_params), error: message})
    |> put_flash(:error, message)
    |> redirect(to: "/setup")
  end

  defp safe_setup_draft(params) when is_map(params) do
    params
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.flat_map(fn
      {_key, account} when is_map(account) ->
        [
          %{
            username: account["username"] || "",
            roles: selected_roles(account["roles"] || %{})
          }
        ]

      _invalid ->
        []
    end)
  end

  defp safe_setup_draft(_params), do: []

  defp not_found(conn), do: send_resp(conn, :not_found, "Not found")
end
