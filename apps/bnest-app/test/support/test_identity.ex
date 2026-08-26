defmodule BnestApp.TestIdentity do
  @moduledoc false

  alias BnestApp.TestRuntimeRoot

  @spec create!(TestRuntimeRoot.t(), String.t()) :: map()
  def create!(%{path: path, run_id: run_id}, suite) when is_binary(suite) do
    case TestRuntimeRoot.validate(path) do
      {:ok, %{path: ^path, run_id: ^run_id}} -> build_identity(path, run_id, suite)
      {:error, reason} -> raise ArgumentError, "identity requires a marked test root: #{reason}"
    end
  end

  defp build_identity(path, run_id, suite) do
    suite =
      suite
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 8)

    suffix =
      :crypto.hash(:sha256, run_id) |> Base.url_encode64(padding: false) |> String.slice(0, 10)

    %{
      username: "test-user-#{suite}-#{String.downcase(suffix)}",
      password: "Synthetic!#{suffix}Aa1",
      user_id: "user-test-#{String.downcase(suffix)}",
      runtime_root: path,
      account_index_root: Path.join(path, "system/usernames"),
      family_list_root: Path.join(path, "system/accounts")
    }
  end
end
