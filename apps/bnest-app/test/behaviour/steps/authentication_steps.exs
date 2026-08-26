defmodule BnestApp.Behaviour.AuthenticationSteps do
  use ExBdd.StepDefinition

  import ExUnit.Assertions

  step "an approved user is logged in", context do
    context.behaviour_driver.establish_identity(context, :user)
  end

  step "an approved child is logged in", context do
    context.behaviour_driver.establish_identity(context, :child)
  end

  step("a visitor has no authenticated Bnest session", context,
    do: prepare(context, :unauthenticated)
  )

  step("the visitor opens the protected route {string}", %{args: [route]} = context,
    do: perform(context, :open_protected_route, [route])
  )

  step("Bnest redirects the visitor to login", context,
    do: outcome(context, :redirected_to_login)
  )

  step("Bnest does not read or write user data", context,
    do: outcome(context, :no_user_data_access)
  )

  step("Bnest has no bootstrap journal", context, do: prepare(context, :uninitialized))

  step("the maintainer submits all initial accounts including an administrator", context,
    do: perform(context, :bootstrap_accounts)
  )

  step("Bnest warns that later account management and password recovery are unavailable", context,
    do: outcome(context, :irreversible_warning)
  )

  step("Bnest creates the accounts exactly once", context,
    do: outcome(context, :accounts_created_once)
  )

  step("setup and public registration are unavailable afterward", context,
    do: outcome(context, :setup_closed)
  )

  step("Bnest accepts the passwords without a character-count rule", context,
    do: outcome(context, :passwords_without_length_rule)
  )

  step("Bnest rejects a password missing a letter, number, or punctuation mark", context,
    do: outcome(context, :password_requirements_enforced)
  )

  step("an approved user account exists", context, do: prepare(context, :approved_account))

  step("an approved user account exists with an Argon2id verifier", context,
    do: prepare(context, :approved_argon2_account)
  )

  step("the user logs in with valid credentials", context, do: perform(context, :login))

  step("the protected home page is available", context,
    do: outcome(context, :protected_home_available)
  )

  step("the user logs out from that browser", context,
    do: perform(context, :logout_current_browser)
  )

  step("that browser must log in again", context,
    do: outcome(context, :current_browser_logged_out)
  )

  step("no plaintext password is stored, logged, or rendered", context,
    do: outcome(context, :no_plaintext_password)
  )

  step("the user reloads and reopens Bnest in the same browser", context,
    do: perform(context, :reload_same_browser)
  )

  step("the same browser remains authenticated", context,
    do: outcome(context, :same_browser_authenticated)
  )

  step("one approved user is logged in on browser A and browser B", context,
    do: prepare(context, :two_browser_sessions)
  )

  step("the user logs out from browser A", context, do: perform(context, :logout_browser_a))

  step("browser A must log in again", context, do: outcome(context, :browser_a_logged_out))

  step("browser B remains authenticated", context, do: outcome(context, :browser_b_authenticated))

  step(
    "an approved user has the roles {string} and {string}",
    %{args: roles} = context,
    do: prepare(context, :multi_role_user, roles)
  )

  step("Bnest authorizes that user's own data operation", context,
    do: perform(context, :authorize_own_data)
  )

  step("the operation is allowed", context, do: outcome(context, :operation_allowed))

  step("an out-of-scope administration operation is denied", context,
    do: outcome(context, :administration_denied)
  )

  step("two approved users own separate Bnest data", context,
    do: prepare(context, :two_isolated_users)
  )

  step("the first user attempts the second user's data operation", context,
    do: perform(context, :cross_user_operation)
  )

  step("Bnest denies the operation before repository access", context,
    do: outcome(context, :denied_before_repository)
  )

  defp prepare(context, state, args \\ []),
    do: context.behaviour_driver.prepare_behaviour(context, state, args)

  defp perform(context, action, args \\ []),
    do: context.behaviour_driver.perform_behaviour(context, action, args)

  defp outcome(context, expected, args \\ []) do
    assert context.behaviour_driver.behaviour_outcome?(context, expected, args)
    context
  end
end
