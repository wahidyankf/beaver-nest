defmodule BnestApp.Codex.RepositoryAccess do
  @moduledoc false

  @roles ~w(children parents admin)

  @type mode :: :read_only | :workspace_write

  @spec can_enable_write?(map()) :: boolean()
  def can_enable_write?(%{"roles" => roles}) when is_list(roles) do
    valid_roles?(roles) and "admin" in roles and "children" not in roles
  end

  def can_enable_write?(_user), do: false

  @spec mode(map(), boolean()) :: mode()
  def mode(user, true) do
    if can_enable_write?(user), do: :workspace_write, else: :read_only
  end

  def mode(_user, _requested), do: :read_only

  defp valid_roles?(roles) do
    roles != [] and Enum.uniq(roles) == roles and Enum.all?(roles, &(&1 in @roles))
  end
end
