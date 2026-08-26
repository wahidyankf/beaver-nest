defmodule BnestAppWeb.ReleaseHeaders do
  @moduledoc false

  import Plug.Conn

  alias BnestApp.Deployment

  def init(options), do: options
  def call(conn, _options), do: put_resp_header(conn, "x-bnest-revision", Deployment.revision())
end
