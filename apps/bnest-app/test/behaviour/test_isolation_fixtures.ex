defmodule BnestApp.Behaviour.TestIsolation.Fixtures do
  @moduledoc false

  # Synthetic values shared by the unit and integration adapters of `test_isolation.feature`. Every
  # account is `test-user-` prefixed and carries the instance short id; the secrets and passwords are
  # fixed test values that never leave the test run. Pure: nothing is read from the environment.

  use Boundary, top_level?: true, check: [in: false, out: false]

  @password "Synthetic!Pass1"
  @secret String.duplicate("ab", 32)
  @wrong_secret String.duplicate("cd", 32)
  @forwarded_ip "203.0.113.9"

  @kinds %{"admin" => ["admin", "parents"], "parent" => ["parents"]}

  @doc "A fresh random instance id, as a client chooses it: 16 lowercase hex characters."
  def new_instance_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  @doc "The first eight characters of an instance id: the short id its usernames carry."
  def short_id(instance_id), do: String.slice(instance_id, 0, 8)

  @doc "The synthetic password every seeded account uses."
  def password, do: @password

  @doc "The run secret the test server accepts: 32 bytes, hex encoded."
  def secret, do: @secret

  @doc "A secret that differs from the run secret, for the wrong-header refusal."
  def wrong_secret, do: @wrong_secret

  @doc "The client address a forwarded request claims, for the forwarded-header refusal."
  def forwarded_ip, do: @forwarded_ip

  @doc """
  A seed with one account per kind, named `test-user-<short id>-<kind>`. `"admin"` gets the admin and
  parents roles, `"parent"` the parents role.
  """
  def accounts_seed(instance_id, kinds) do
    short = short_id(instance_id)

    %{
      "accounts" =>
        Enum.map(kinds, fn kind ->
          %{
            "username" => "test-user-#{short}-#{kind}",
            "password" => @password,
            "roles" => Map.fetch!(@kinds, kind)
          }
        end)
    }
  end

  @doc "A seed with one admin account under the given username, which need not carry the short id."
  def named_admin_seed(username) do
    %{"accounts" => [%{"username" => username, "password" => @password, "roles" => ["admin"]}]}
  end

  @doc "The usernames a seed sends, in seed order."
  def seeded_usernames(seed), do: Enum.map(seed["accounts"], & &1["username"])
end
