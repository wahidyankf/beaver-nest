defmodule BnestAppWeb.PageController do
  use BnestAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
