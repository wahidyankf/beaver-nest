defmodule BnestApp.Identity.Authorization do
  @moduledoc false

  @owned_capabilities ~w(use_chat use_sifat_allah read_theme write_theme confirm_import view_import_status)a

  @spec allow?(map(), atom(), String.t() | nil) :: boolean()
  def allow?(%{"userId" => user_id, "roles" => roles}, capability, owner_id)
      when capability in @owned_capabilities do
    owner_id == user_id and valid_roles?(roles)
  end

  def allow?(_user, _capability, _owner_id), do: false

  defp valid_roles?(roles) when is_list(roles) and roles != [],
    do: Enum.all?(roles, &(&1 in ~w(children parents admin)))

  defp valid_roles?(_roles), do: false
end
