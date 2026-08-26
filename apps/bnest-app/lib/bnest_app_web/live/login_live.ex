defmodule BnestAppWeb.LoginLive do
  use BnestAppWeb, :live_view

  alias BnestApp.Identity
  alias BnestAppWeb.UserAuth

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    {setup_draft, setup_error} = setup_state(socket.assigns.flash)

    {:ok,
     socket
     |> assign(:return_to, UserAuth.safe_return_path(params["return_to"] || "/"))
     |> assign(:setup_draft, setup_draft)
     |> assign(:setup_error, setup_error)
     |> assign(:setup_status, Identity.setup_status())}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    return_to = UserAuth.safe_return_path(params["return_to"] || "/")

    if socket.assigns.return_to == return_to,
      do: {:noreply, socket},
      else: {:noreply, assign(socket, :return_to, return_to)}
  end

  @impl Phoenix.LiveView
  def render(%{live_action: :setup, setup_status: status} = assigns) when status != :open do
    ~H"""
    <main class="identity-shell">
      <section class="identity-card" aria-labelledby="setup-closed-title">
        <p class="identity-kicker">BEAVER NEST ACCOUNTS</p>
        <h1 id="setup-closed-title">Setup is permanently closed</h1>
        <p>
          Initial accounts already exist. Public registration and password recovery are unavailable.
        </p>
        <a class="identity-primary" href="/login">Go to login</a>
      </section>
    </main>
    """
  end

  def render(%{live_action: :setup} = assigns) do
    ~H"""
    <main class="identity-shell">
      <Layouts.flash_group flash={@flash} />
      <section class="identity-card identity-setup" aria-labelledby="setup-title">
        <p class="identity-kicker">ONE-TIME FAMILY SETUP</p>
        <h1 id="setup-title">Create the first family accounts</h1>
        <p class="identity-lede">
          Add every initial account now. After confirmation, account creation, role changes,
          password reset, and recovery are unavailable until a separate feature is built.
        </p>
        <p
          :if={@setup_error}
          id="setup-error"
          class="identity-warning"
          role="alert"
        >
          {@setup_error}
        </p>

        <form
          id="bootstrap-form"
          action="/setup"
          method="post"
          class="identity-form"
          aria-describedby={@setup_error && "setup-error"}
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <div id="account-cards" class="identity-account-grid" phx-update="ignore">
            <fieldset
              :for={{account, index} <- Enum.with_index(@setup_draft)}
              class="identity-account-card"
              data-account-card
            >
              <legend>
                {if index == 0, do: "Initial administrator", else: "Family member #{index + 1}"}
              </legend>
              <label for={"account-#{index}-username"}>Username</label>
              <input
                id={"account-#{index}-username"}
                name={"accounts[#{index}][username]"}
                value={account.username}
                required
                maxlength="32"
                autocomplete={if index == 0, do: "username", else: "off"}
              />
              <label for={"account-#{index}-password"}>Password</label>
              <input
                id={"account-#{index}-password"}
                name={"accounts[#{index}][password]"}
                type="password"
                required
                minlength="15"
                maxlength="128"
                autocomplete="new-password"
              />
              <label for={"account-#{index}-password-confirmation"}>Confirm password</label>
              <input
                id={"account-#{index}-password-confirmation"}
                name={"accounts[#{index}][password_confirmation]"}
                type="password"
                required
                minlength="15"
                maxlength="128"
                autocomplete="new-password"
              />
              <div class="identity-role-group" aria-labelledby={"account-#{index}-roles"}>
                <span id={"account-#{index}-roles"}>Roles</span>
                <label><input
                  type="checkbox"
                  name={"accounts[#{index}][roles][children]"}
                  value="true"
                  checked={"children" in account.roles}
                /> Children</label>
                <label><input
                  type="checkbox"
                  name={"accounts[#{index}][roles][parents]"}
                  value="true"
                  checked={"parents" in account.roles}
                /> Parents</label>
                <label><input
                  type="checkbox"
                  name={"accounts[#{index}][roles][admin]"}
                  value="true"
                  checked={"admin" in account.roles}
                /> Admin</label>
              </div>
              <button
                :if={index > 0}
                class="identity-secondary"
                type="button"
                data-remove-account
              >
                Remove this account
              </button>
            </fieldset>
          </div>

          <button class="identity-secondary" type="button" data-add-account>
            Add another initial account
          </button>
          <template id="account-card-template">
            <fieldset class="identity-account-card" data-account-card>
              <legend>Family member <span data-account-number></span></legend>
              <label for="account-__INDEX__-username">Username</label>
              <input
                id="account-__INDEX__-username"
                name="accounts[__INDEX__][username]"
                required
                maxlength="32"
                autocomplete="off"
              />
              <label for="account-__INDEX__-password">Password</label>
              <input
                id="account-__INDEX__-password"
                name="accounts[__INDEX__][password]"
                type="password"
                required
                minlength="15"
                maxlength="128"
                autocomplete="new-password"
              />
              <label for="account-__INDEX__-password-confirmation">Confirm password</label>
              <input
                id="account-__INDEX__-password-confirmation"
                name="accounts[__INDEX__][password_confirmation]"
                type="password"
                required
                minlength="15"
                maxlength="128"
                autocomplete="new-password"
              />
              <div class="identity-role-group" aria-labelledby="account-__INDEX__-roles">
                <span id="account-__INDEX__-roles">Roles</span>
                <label><input
                  type="checkbox"
                  name="accounts[__INDEX__][roles][children]"
                  value="true"
                /> Children</label>
                <label><input type="checkbox" name="accounts[__INDEX__][roles][parents]" value="true" />
                Parents</label>
                <label><input type="checkbox" name="accounts[__INDEX__][roles][admin]" value="true" />
                Admin</label>
              </div>
              <button class="identity-secondary" type="button" data-remove-account>
                Remove this account
              </button>
            </fieldset>
          </template>

          <p class="identity-warning" role="note">
            This is irreversible: losing a password makes that account unavailable. Passwords are hashed with Argon2id and are never shown in review.
          </p>
          <label class="identity-confirm">
            <input type="checkbox" name="confirm" value="closed" required />
            I understand setup closes permanently after this submission.
          </label>
          <button class="identity-primary" type="submit">Create accounts and close setup</button>
        </form>
      </section>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="identity-shell">
      <Layouts.flash_group flash={@flash} />
      <section class="identity-card identity-login" aria-labelledby="login-title">
        <a href="/" class="identity-brand" aria-label="Beaver Nest home">
          <img src="/images/beaver-nest-logo.png" alt="Beaver Nest logo" width="56" height="56" />
          <span>Beaver Nest</span>
        </a>
        <p class="identity-kicker">WELCOME BACK</p>
        <h1 id="login-title">Open your nest</h1>
        <p class="identity-lede">Use the username and password created during one-time setup.</p>
        <form id="login-form" action="/login" method="post" class="identity-form">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="return_to" value={@return_to} />
          <label for="login-username">Username</label>
          <input
            id="login-username"
            name="login[username]"
            required
            maxlength="32"
            autocomplete="username"
          />
          <label for="login-password">Password</label>
          <input
            id="login-password"
            name="login[password]"
            type="password"
            required
            maxlength="128"
            autocomplete="current-password"
          />
          <button class="identity-primary" type="submit">Log in</button>
        </form>
      </section>
    </main>
    """
  end

  defp setup_state(flash) do
    case Phoenix.Flash.get(flash, :setup_draft) do
      %{accounts: accounts, error: error} when is_list(accounts) and accounts != [] ->
        {accounts, error}

      _other ->
        {[%{username: "", roles: ["admin"]}], nil}
    end
  end
end
