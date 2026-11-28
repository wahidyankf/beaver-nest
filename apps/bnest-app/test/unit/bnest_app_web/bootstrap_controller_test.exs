defmodule BnestAppWeb.BootstrapControllerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias BnestApp.Identity
  alias BnestApp.Storage.Records
  alias BnestApp.Test.InMemory.RecordBackend, as: InMemoryRecordBackend
  alias BnestApp.Test.InMemory.StoragePorts
  alias BnestAppWeb.BootstrapController
  alias BnestAppWeb.LoginLive
  alias Phoenix.HTML.Safe

  @password "Setup password 1!"

  # The record-backed request path, empty so bootstrap is open: the shared
  # setup for the controller-level bootstrap proofs below.
  setup do
    {:ok, _apps} = Application.ensure_all_started(:plug)
    previous = StoragePorts.install()
    on_exit(fn -> StoragePorts.restore(previous) end)
    store = InMemoryRecordBackend.start()
    start_supervised!({Records, store: store})
    start_supervised!(Identity)
    :ok
  end

  defp setup_conn(params) do
    conn(:post, "/setup", params) |> init_test_session(%{}) |> Phoenix.Controller.fetch_flash([])
  end

  defp account(username, password, confirmation, roles) do
    %{
      "username" => username,
      "password" => password,
      "password_confirmation" => confirmation,
      "roles" => Map.new(roles, &{&1, "true"})
    }
  end

  defp submit(params) do
    params |> setup_conn() |> BootstrapController.create(params)
  end

  # The setup form posts its account cards as `accounts[<index>][...]`, which Plug decodes
  # into a map keyed by the index text. Setup and its error draft must keep the cards in
  # the order the form showed them, so the keys order by their numeric index, not as text
  # ("10" would otherwise come before "2").
  test "account cards keep the form's order past nine cards" do
    params = Map.new(0..11, &{Integer.to_string(&1), %{"username" => "test-user-#{&1}"}})

    assert params |> BootstrapController.ordered_account_params() |> Enum.map(&elem(&1, 0)) ==
             Enum.map(0..11, &Integer.to_string/1)
  end

  test "keys that are not form indexes order after every indexed card" do
    params = %{"1" => %{}, "x" => %{}, "0" => %{}}

    assert params |> BootstrapController.ordered_account_params() |> Enum.map(&elem(&1, 0)) ==
             ["0", "1", "x"]
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A setup submission that breaks a rule is refused and creates no account
  test "a setup submission that breaks a rule is refused and creates no account" do
    for {setup_case, params, message} <- [
          {"no admin",
           %{
             "confirm" => "closed",
             "accounts" => %{
               "0" => account("test-user-setup-one", @password, @password, ["children"]),
               "1" => account("test-user-setup-two", @password, @password, ["parents"])
             }
           }, "At least one initial account must have the admin role."},
          {"duplicate username",
           %{
             "confirm" => "closed",
             "accounts" => %{
               "0" => account("Test-User-Setup", @password, @password, ["admin"]),
               "1" => account("test-user-setup", @password, @password, ["admin"])
             }
           }, "Each username must be unique regardless of letter case."},
          {"empty username",
           %{
             "confirm" => "closed",
             "accounts" => %{
               "0" => account("", @password, @password, ["admin"])
             }
           }, "Use 1–32 letters, numbers, dots, dashes, or underscores."},
          {"long username",
           %{
             "confirm" => "closed",
             "accounts" => %{
               "0" => account(String.duplicate("a", 33), @password, @password, ["admin"])
             }
           }, "Use 1–32 letters, numbers, dots, dashes, or underscores."},
          {"password mismatch",
           %{
             "confirm" => "closed",
             "accounts" => %{
               "0" =>
                 account("test-user-setup-one", @password, "A different password 0!", ["admin"])
             }
           }, "Each password and confirmation must match."},
          {"unchecked box",
           %{
             "accounts" => %{
               "0" => account("test-user-setup-one", @password, @password, ["admin"])
             }
           }, "Confirm that setup closes permanently before continuing."}
        ] do
      response = submit(params)

      assert response.status == 302, setup_case
      assert get_resp_header(response, "location") == ["/setup"], setup_case

      assert Phoenix.Flash.get(response.assigns.flash, :error) == message, setup_case
      assert Identity.setup_status() == :open, setup_case
    end
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: First-time setup warns that accounts cannot be managed or recovered later, then closes
  test "first-time setup warns that accounts cannot be managed or recovered later, then closes" do
    html =
      %{
        live_action: :setup,
        setup_status: :open,
        setup_draft: [%{username: "", roles: ["admin"]}],
        setup_error: nil,
        flash: %{}
      }
      |> LoginLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "irreversible"
    assert html =~ "account creation, role changes"
    assert html =~ "password reset, and recovery are unavailable"
    assert html =~ "closes permanently"

    response =
      submit(%{
        "confirm" => "closed",
        "accounts" => %{
          "0" => account("test-user-setup-warn", @password, @password, ["admin"])
        }
      })

    assert response.status == 302
    assert get_resp_header(response, "location") == ["/login"]

    assert Phoenix.Flash.get(response.assigns.flash, :info) ==
             "Initial accounts created. Setup is now permanently closed."

    assert Identity.setup_status() != :open
  end

  # credo:disable-for-next-line Credo.Check.Readability.MaxLineLength
  # @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: A failed setup keeps the names and roles and clears every password
  test "a failed setup keeps the names and roles and clears every password" do
    params = %{
      "confirm" => "closed",
      "accounts" => %{
        "0" =>
          account("test-user-setup-one", "Setup password 1!", "Setup mismatch 9!", ["children"]),
        "1" => account("test-user-setup-two", "Setup password 2!", "Setup mismatch 8!", ["admin"])
      }
    }

    response = submit(params)

    assert response.status == 302
    assert get_resp_header(response, "location") == ["/setup"]

    message = "Each password and confirmation must match."
    assert Phoenix.Flash.get(response.assigns.flash, :error) == message
    assert Identity.setup_status() == :open

    draft = Phoenix.Flash.get(response.assigns.flash, :setup_draft)

    assert %{
             accounts: [
               %{username: "test-user-setup-one", roles: ["children"]},
               %{username: "test-user-setup-two", roles: ["admin"]}
             ],
             error: ^message
           } = draft

    refute inspect(draft) =~ "Setup password"
    refute inspect(draft) =~ "Setup mismatch"

    html =
      %{
        live_action: :setup,
        setup_status: :open,
        setup_draft: draft.accounts,
        setup_error: draft.error,
        flash: %{}
      }
      |> LoginLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "test-user-setup-one"
    assert html =~ "test-user-setup-two"
    assert html =~ message
    assert html =~ "setup-error"
    refute html =~ "Setup password 1!"
    refute html =~ "Setup password 2!"
    refute html =~ "Setup mismatch 9!"
    refute html =~ "Setup mismatch 8!"
  end
end
