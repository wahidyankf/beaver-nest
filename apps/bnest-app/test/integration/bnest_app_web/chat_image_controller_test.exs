defmodule BnestAppWeb.ChatImageControllerTest do
  # ADR 002, Decision 2: the image route, through the endpoint and the real file adapter. A test that
  # places files gets its own repository in an isolated run root; the signed-in logo test reads the
  # checkout, as production does.
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.CodexChat.Domain.RepositoryImage
  alias BnestApp.TestRuntimeRoot

  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"
  @checkout Path.expand("../../../../..", __DIR__)
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> "synthetic"
  @gif "GIF89a" <> "synthetic"
  @webp "RIFF" <> <<12, 0, 0, 0>> <> "WEBPVP8 "
  @not_a_raster "<html><script>alert(1)</script></html>"
  @svg ~S|<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>|

  # ADR 003, Decision 5: a Family Chat message may name a repository image, so every account that can read a
  # Family Chat message must load it. The route needs a signed-in session and no role or Family Chat flag, so one
  # synthetic member of each valid Family Chat role loads the logo. Characterization of the existing route: this
  # passes before and after the bodyHtml change, and it is the re-confirmation the decision relies on.
  describe "every Family Chat role" do
    for role <- ["children", "parents", "admin"] do
      test "a signed-in #{role} member loads the repository logo", %{conn: _conn} do
        {conn, _identity} =
          scenario_authenticated_conn(build_conn(), "chat-images-role-#{unquote(role)}", [
            unquote(role)
          ])

        conn = get(conn, route(@logo))

        assert conn.status == 200
        assert get_resp_header(conn, "content-type") == ["image/png"]
      end
    end
  end

  describe "a signed-in visitor" do
    test "fetches the repository logo as a PNG with the route's headers", %{conn: conn} do
      conn = get(conn, route(@logo))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert conn.resp_body == File.read!(Path.join(@checkout, @logo))
      assert_image_headers(conn)
    end

    test "the multi-segment URL and the single encoded-segment URL answer the same", %{conn: conn} do
      single = get(conn, route(@logo))
      multi = conn |> recycle() |> get("/chat/images/" <> @logo)

      assert multi.status == 200
      assert multi.resp_body == single.resp_body
      assert headers(multi) == headers(single)
    end

    test "the content type comes from the bytes, not from the file name", %{conn: conn} do
      root = use_repository()
      write!(root.repository, "jpeg-named.png", @jpeg)
      write!(root.repository, "png-named.jpg", @png)
      write!(root.repository, "anim.gif", @gif)
      write!(root.repository, "shot.webp", @webp)
      write!(root.repository, "upper.PNG", @png)

      for {path, type} <- [
            {"jpeg-named.png", "image/jpeg"},
            {"png-named.jpg", "image/png"},
            {"anim.gif", "image/gif"},
            {"shot.webp", "image/webp"},
            {"upper.PNG", "image/png"}
          ] do
        served = conn |> recycle() |> get(route(path))
        assert served.status == 200, "served #{path}"
        assert get_resp_header(served, "content-type") == [type], "type of #{path}"
      end
    end

    test "no request value comes back in a response header", %{conn: conn} do
      conn = conn |> put_req_header("x-probe", "probe-value-7f3a") |> get(route(@logo))

      assert conn.status == 200

      refute Enum.any?(conn.resp_headers, fn {_name, value} ->
               String.contains?(value, "probe-value-7f3a")
             end)
    end

    test "HEAD gets the same status and headers as GET, and no body", %{conn: conn} do
      get_conn = get(conn, route(@logo))
      head_conn = dispatch(conn |> recycle(), @endpoint, :head, route(@logo))

      assert head_conn.status == 200
      assert headers(head_conn) == headers(get_conn)
      assert head_conn.resp_body == ""
    end
  end

  describe "a signed-out visitor" do
    @tag :unauthenticated
    test "is redirected to login and gets no image bytes", %{conn: conn} do
      conn = get(conn, route(@logo))

      assert redirected_to(conn) =~ ~r{\A/login}
      refute String.starts_with?(conn.resp_body, <<0x89, "PNG">>)
    end
  end

  describe "every refusal is the same empty 404" do
    test "a missing file, and each traversal form of a path that leaves the repository", %{
      conn: conn
    } do
      root = use_repository()
      write!(root.runtime, "outside.png", @png)
      missing = get(conn, route("docs/missing.png"))

      assert_empty_not_found(missing, missing)

      for path <- [
            "../outside.png",
            "%2e%2e/outside.png",
            "%2e%2e%2Foutside.png",
            "docs%2F..%2F..%2Foutside.png",
            "docs/%2e%2e/%2e%2e/outside.png",
            "docs%5C..%5C..%5Coutside.png",
            "docs%00.png",
            "%252e%252e/outside.png",
            "%2Fetc%2Fhosts.png"
          ] do
        refused = conn |> recycle() |> get("/chat/images/" <> path)
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "a symbolic link to a file outside the repository, and one inside a linked directory",
         %{conn: conn} do
      root = use_repository()
      write!(root.runtime, "outside.png", @png)
      write!(root.runtime, "elsewhere/a.png", @png)
      File.mkdir_p!(Path.join(root.repository, "docs"))

      File.ln_s!(
        Path.join(root.runtime, "outside.png"),
        Path.join(root.repository, "docs/link.png")
      )

      File.ln_s!(Path.join(root.runtime, "elsewhere"), Path.join(root.repository, "shots"))
      missing = get(conn, route("docs/missing.png"))

      for path <- ["docs/link.png", "shots/a.png"] do
        refused = conn |> recycle() |> get(route(path))
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "an oversized file is refused, and a file of exactly the limit is served", %{conn: conn} do
      max = RepositoryImage.max_bytes()
      root = use_repository()
      write!(root.repository, "at-limit.png", @png <> :binary.copy(<<0>>, max - byte_size(@png)))

      write!(
        root.repository,
        "over-limit.png",
        @png <> :binary.copy(<<0>>, max - byte_size(@png) + 1)
      )

      missing = get(conn, route("docs/missing.png"))

      served = conn |> recycle() |> get(route("at-limit.png"))
      assert served.status == 200
      assert byte_size(served.resp_body) == max

      refused = conn |> recycle() |> get(route("over-limit.png"))
      assert_empty_not_found(refused, missing, "over-limit.png")
    end

    test "SVG, HTML and text are refused, whatever their name ends in", %{conn: conn} do
      root = use_repository()
      write!(root.repository, "named-png.png", @not_a_raster)
      write!(root.repository, "svg-named-png.png", @svg)
      write!(root.repository, "shot.svg", @png)
      write!(root.repository, "shot.PNG.txt", @png)
      missing = get(conn, route("docs/missing.png"))

      for path <- ["named-png.png", "svg-named-png.png", "shot.svg", "shot.PNG.txt"] do
        refused = conn |> recycle() |> get(route(path))
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "hidden and runtime-data locations are refused, in any letter case", %{conn: conn} do
      root = use_repository()

      for path <- [
            ".env/logo.png",
            ".git/config.png",
            "data/test-user-probe/logo.png",
            "Data/prod/logo.png",
            "Node_Modules/x/logo.png",
            "node_modules/x/logo.png",
            "local-tmp/logo.png",
            "_build/logo.png"
          ] do
        write!(root.repository, path, @png)
      end

      missing = get(conn, route("docs/missing.png"))

      for path <- [
            ".env/logo.png",
            ".git/config.png",
            "data/test-user-probe/logo.png",
            "Data/prod/logo.png",
            "Node_Modules/x/logo.png",
            "node_modules/x/logo.png",
            "local-tmp/logo.png",
            "_build/logo.png"
          ] do
        refused = conn |> recycle() |> get(route(path))
        assert_empty_not_found(refused, missing, path)
      end
    end
  end

  # One browser request for one repository path: the path's segments, each encoded on its own, so
  # the slashes arrive as %2F the way the drivers and the renderer send them.
  defp route(path), do: "/chat/images/" <> URI.encode(path, &URI.char_unreserved?/1)

  defp assert_image_headers(conn) do
    assert get_resp_header(conn, "cache-control") == ["private, max-age=60"]
    assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-disposition") == []
  end

  defp assert_empty_not_found(conn, reference, path \\ "missing") do
    assert conn.status == 404, "status for #{path}"
    assert conn.resp_body == "", "body for #{path}"
    assert headers(conn) == headers(reference), "headers for #{path}"
  end

  # Every header except the two the test server adds to each request.
  defp headers(conn) do
    Enum.reject(conn.resp_headers, fn {name, _value} -> name in ["date", "x-request-id"] end)
  end

  # A synthetic repository under its own run root, read by the route through the configured
  # working directory. The configuration is restored after the test.
  defp use_repository do
    runtime = TestRuntimeRoot.create!("chat-images")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    repository = Path.join(runtime.path, "repo")
    File.mkdir_p!(repository)

    codex = Application.fetch_env!(:bnest_app, :codex)
    Application.put_env(:bnest_app, :codex, Keyword.put(codex, :working_directory, repository))
    on_exit(fn -> Application.put_env(:bnest_app, :codex, codex) end)

    %{runtime: runtime.path, repository: repository}
  end

  defp write!(root, relative, bytes) do
    full = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, bytes)
  end
end
