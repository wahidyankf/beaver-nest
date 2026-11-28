defmodule BnestAppWeb.ImageSecurityHeadersTest do
  # Every image answer, served or refused, is private-cached and sandboxed,
  # and no request value comes back in a header.
  #
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A signed-in visitor can fetch a generated image
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Every image answer is private-cached and sandboxed
  use ExUnit.Case, async: false

  import Plug.Test

  alias BnestApp.Test.InMemory.GeneratedImages, as: InMemoryGeneratedImages
  alias BnestApp.Test.InMemory.RepositoryImages, as: InMemoryRepositoryImages
  alias BnestAppWeb.ChatImageController
  alias BnestAppWeb.GeneratedImageController

  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"
  @thread "abcdef12-3456"

  setup do
    :ok = InMemoryRepositoryImages.ensure_installed()
    :ok = InMemoryGeneratedImages.install()

    previous = Application.fetch_env!(:bnest_app, BnestApp.CodexChat)

    on_exit(fn -> Application.put_env(:bnest_app, BnestApp.CodexChat, previous) end)

    Application.put_env(
      :bnest_app,
      BnestApp.CodexChat,
      Keyword.put(previous, :generated_images, InMemoryGeneratedImages)
    )

    :ok
  end

  test "a served repository image is private-cached and sandboxed" do
    conn = show(ChatImageController, %{"path" => split(@logo)})

    assert conn.status == 200
    assert image_headers(conn)
    assert headerless(conn)
  end

  test "a refused repository image is an empty not found answer with the same headers" do
    conn = show(ChatImageController, %{"path" => ["docs", "missing-logo.png"]})

    assert conn.status == 404
    assert conn.resp_body == ""
    assert image_headers(conn)
  end

  test "a served generated image is private-cached and sandboxed" do
    InMemoryGeneratedImages.put_file(@thread <> "/exec-served.png", @png)

    conn = show(GeneratedImageController, %{"path" => [@thread, "exec-served.png"]})

    assert conn.status == 200
    assert image_headers(conn)
    assert headerless(conn)
  end

  test "an unknown generated image is an empty not found answer with the same headers" do
    conn = show(GeneratedImageController, %{"path" => [@thread, "exec-absent.png"]})

    assert conn.status == 404
    assert conn.resp_body == ""
    assert image_headers(conn)
  end

  defp show(controller, params) do
    conn(:get, "/")
    |> Plug.Conn.put_req_header("x-scenario-probe", "probe-value")
    |> controller.show(params)
  end

  defp split(path), do: String.split(path, "/")

  defp image_headers(conn) do
    Plug.Conn.get_resp_header(conn, "cache-control") == ["private, max-age=60"] and
      Plug.Conn.get_resp_header(conn, "content-security-policy") == [
        "default-src 'none'; sandbox"
      ]
  end

  defp headerless(conn) do
    values = Enum.map(conn.resp_headers, &elem(&1, 1))
    not Enum.any?(values, &String.contains?(&1, "probe-value"))
  end
end
