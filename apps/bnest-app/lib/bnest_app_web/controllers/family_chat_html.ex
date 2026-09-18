defmodule BnestAppWeb.FamilyChatHTML do
  @moduledoc """
  This module contains pages rendered by FamilyChatController.

  See the `family_chat_html` directory for all templates available.
  """
  use BnestAppWeb, :html

  embed_templates "family_chat_html/*"
end
