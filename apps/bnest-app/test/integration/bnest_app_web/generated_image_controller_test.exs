defmodule BnestAppWeb.GeneratedImageControllerTest do
  # ADR 007, Decision 2: the generated-image route, through the endpoint and the real file adapter.
  # Every test reads a synthetic Codex home in an isolated run root, never the real `~/.codex`.
  use BnestAppWeb.ConnCase, async: false

  alias BnestApp.CodexChat.Domain.GeneratedImage
  alias BnestApp.TestRuntimeRoot

  @thread "01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071"
  @png <<0x89, "PNG\r\n", 0x1A, "\n">> <> "synthetic"
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> "synthetic"
  @not_a_raster "<html><script>alert(1)</script></html>"
  @svg ~S|<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>|

  describe "a signed-in visitor" do
    test "fetches a generated image with the route's headers", %{conn: conn} do
      %{generated: generated} = use_codex_home()
      write!(generated, "#{@thread}/exec-abc.png", @png)

      conn = get(conn, route("#{@thread}/exec-abc.png"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert conn.resp_body == @png
      assert_image_headers(conn)
    end

    test "the multi-segment URL and the single encoded-segment URL answer the same", %{
      conn: conn
    } do
      %{generated: generated} = use_codex_home()
      write!(generated, "#{@thread}/exec-abc.png", @png)

      single = get(conn, route("#{@thread}/exec-abc.png"))
      multi = conn |> recycle() |> get("/chat/generated-images/#{@thread}/exec-abc.png")

      assert multi.status == 200
      assert multi.resp_body == single.resp_body
      assert headers(multi) == headers(single)
    end

    test "the content type comes from the bytes, not from the file name", %{conn: conn} do
      %{generated: generated} = use_codex_home()
      write!(generated, "#{@thread}/exec-jpeg-named.png", @jpeg)

      served = get(conn, route("#{@thread}/exec-jpeg-named.png"))

      assert served.status == 200
      assert get_resp_header(served, "content-type") == ["image/jpeg"]
    end

    test "no request value comes back in a response header", %{conn: conn} do
      %{generated: generated} = use_codex_home()
      write!(generated, "#{@thread}/exec-abc.png", @png)

      conn =
        conn
        |> put_req_header("x-probe", "probe-value-7f3a")
        |> get(route("#{@thread}/exec-abc.png"))

      assert conn.status == 200

      refute Enum.any?(conn.resp_headers, fn {_name, value} ->
               String.contains?(value, "probe-value-7f3a")
             end)
    end
  end

  describe "a signed-out visitor" do
    @tag :unauthenticated
    test "is redirected to login and gets no image bytes", %{conn: conn} do
      conn = get(conn, route("#{@thread}/exec-abc.png"))

      assert redirected_to(conn) =~ ~r{\A/login}
      refute String.starts_with?(conn.resp_body, <<0x89, "PNG">>)
    end
  end

  describe "every refusal is the same empty 404" do
    test "a missing file, and each traversal form of a path that leaves the directory", %{
      conn: conn
    } do
      root = use_codex_home()
      write!(root.runtime, "outside.png", @png)
      missing = get(conn, route("#{@thread}/exec-missing.png"))

      assert_empty_not_found(missing, missing)

      for path <- [
            "../outside.png",
            "#{@thread}/../../outside.png",
            "%2e%2e/outside.png",
            "#{@thread}%2F..%2F..%2Foutside.png",
            "%252e%252e/outside.png",
            "%2Fetc%2Fhosts.png"
          ] do
        refused = conn |> recycle() |> get("/chat/generated-images/" <> path)
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "a path that is not two segments", %{conn: conn} do
      root = use_codex_home()
      write!(root.generated, "#{@thread}/exec-abc.png", @png)
      missing = get(conn, route("#{@thread}/exec-missing.png"))

      for path <- [
            "/chat/generated-images/exec-abc.png",
            "/chat/generated-images/#{@thread}/exec-abc.png/extra"
          ] do
        refused = conn |> recycle() |> get(path)
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "a symbolic link to a file outside the generated directory, and one inside a linked thread",
         %{conn: conn} do
      root = use_codex_home()
      write!(root.runtime, "outside.png", @png)
      write!(root.runtime, "elsewhere/exec-a.png", @png)
      File.mkdir_p!(Path.join(root.generated, @thread))

      File.ln_s!(
        Path.join(root.runtime, "outside.png"),
        Path.join(root.generated, "#{@thread}/exec-linked.png")
      )

      File.ln_s!(Path.join(root.runtime, "elsewhere"), Path.join(root.generated, "linked-thread"))
      missing = get(conn, route("#{@thread}/exec-missing.png"))

      for path <- ["#{@thread}/exec-linked.png", "linked-thread/exec-a.png"] do
        refused = conn |> recycle() |> get(route(path))
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "an oversized file is refused, and a file of exactly the limit is served", %{conn: conn} do
      max = GeneratedImage.max_bytes()
      root = use_codex_home()

      write!(
        root.generated,
        "#{@thread}/exec-at-limit.png",
        @png <> :binary.copy(<<0>>, max - byte_size(@png))
      )

      write!(
        root.generated,
        "#{@thread}/exec-over-limit.png",
        @png <> :binary.copy(<<0>>, max - byte_size(@png) + 1)
      )

      missing = get(conn, route("#{@thread}/exec-missing.png"))

      served = conn |> recycle() |> get(route("#{@thread}/exec-at-limit.png"))
      assert served.status == 200
      assert byte_size(served.resp_body) == max

      refused = conn |> recycle() |> get(route("#{@thread}/exec-over-limit.png"))
      assert_empty_not_found(refused, missing, "exec-over-limit.png")
    end

    test "SVG, HTML and text are refused, whatever the name ends in", %{conn: conn} do
      root = use_codex_home()
      write!(root.generated, "#{@thread}/exec-named-png.png", @not_a_raster)
      write!(root.generated, "#{@thread}/exec-svg-named-png.png", @svg)
      write!(root.generated, "#{@thread}/exec-shot.svg", @png)
      missing = get(conn, route("#{@thread}/exec-missing.png"))

      for path <- [
            "#{@thread}/exec-named-png.png",
            "#{@thread}/exec-svg-named-png.png",
            "#{@thread}/exec-shot.svg"
          ] do
        refused = conn |> recycle() |> get(route(path))
        assert_empty_not_found(refused, missing, path)
      end
    end

    test "hidden thread directories are refused", %{conn: conn} do
      root = use_codex_home()
      write!(root.generated, ".hidden/exec-abc.png", @png)
      missing = get(conn, route("#{@thread}/exec-missing.png"))

      refused = conn |> recycle() |> get(route(".hidden/exec-abc.png"))
      assert_empty_not_found(refused, missing, ".hidden/exec-abc.png")
    end
  end

  # One browser request for one thread/file reference: each segment encoded on its own, so the
  # slash arrives as %2F the way the renderer sends it.
  defp route(path), do: "/chat/generated-images/" <> URI.encode(path, &URI.char_unreserved?/1)

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

  # A synthetic Codex home under its own run root, read by the route through the configured
  # codex home. The configuration is restored after the test.
  defp use_codex_home do
    runtime = TestRuntimeRoot.create!("chat-generated-images")
    on_exit(fn -> TestRuntimeRoot.cleanup!(runtime) end)

    generated = Path.join([runtime.path, "home", "generated_images"])
    File.mkdir_p!(generated)

    codex = Application.fetch_env!(:bnest_app, :codex)

    Application.put_env(
      :bnest_app,
      :codex,
      Keyword.put(codex, :codex_home, Path.join(runtime.path, "home"))
    )

    on_exit(fn -> Application.put_env(:bnest_app, :codex, codex) end)

    %{runtime: runtime.path, generated: generated}
  end

  defp write!(root, relative, bytes) do
    full = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, bytes)
  end
end
