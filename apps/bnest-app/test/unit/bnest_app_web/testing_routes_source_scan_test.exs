defmodule BnestAppWeb.TestingRoutesSourceScanTest do
  use ExUnit.Case, async: true

  alias BnestApp.SchemaSourceScan

  # Module segments that exist only in the test build. Code in lib/ may name them only inside the
  # compile-time gated block of the router. The pure gate `testing_routes.ex` never names them.
  @test_only_segments [:TestingControl, :TestInstance]
  @gate_file "bnest_app_web/testing_routes.ex"
  @router_file "bnest_app_web/router.ex"

  @router_path "apps/bnest-app/lib/bnest_app_web/router.ex"

  test "lib names no test-only module outside the compile-time gated router block" do
    violations =
      ["**", "*.ex"]
      |> SchemaSourceScan.wildcard()
      |> Enum.flat_map(fn path -> violations(path, SchemaSourceScan.read!(path)) end)

    assert violations == []
  end

  test "the router's compile-time gate mounts the testing control" do
    router = SchemaSourceScan.read_lib_file!(["bnest_app_web", "router.ex"])

    assert gate_mounts_control?(Code.string_to_quoted!(router))
  end

  test "the scan flags a regular module that names the testing control" do
    source = "defmodule Page do\n  alias BnestAppWeb.TestingControl\nend\n"

    assert [_violation] = violations("apps/bnest-app/lib/bnest_app_web/page.ex", source)
  end

  test "the scan flags a regular module that names the test instance" do
    source = "defmodule Page do\n  def go, do: BnestApp.TestInstance.spawn!()\nend\n"

    assert [_violation] = violations("apps/bnest-app/lib/bnest_app/page.ex", source)
  end

  test "the scan allows the testing control inside the router's compile-time gate" do
    source = """
    defmodule Router do
      if @testing_routes_mounted? do
        scope "/__bnest_testing/v1", BnestAppWeb.TestingControl do
          get "/state", InstanceController, :state
        end
      end
    end
    """

    assert violations(@router_path, source) == []
  end

  test "the scan flags the testing control in the router outside its compile-time gate" do
    source = """
    defmodule Router do
      scope "/__bnest_testing/v1", BnestAppWeb.TestingControl do
        get "/state", InstanceController, :state
      end
    end
    """

    assert [_violation] = violations(@router_path, source)
  end

  defp violations(path, source) do
    if String.ends_with?(path, @gate_file) do
      []
    else
      source
      |> Code.string_to_quoted!()
      |> outside_gate(String.ends_with?(path, @router_file))
      |> Enum.map(fn {line, segments} -> "#{path}:#{line} names #{inspect(segments)}" end)
    end
  end

  # Collects every alias that names a test-only segment. In the router, the gated `if` block is
  # skipped whole: returning a leaf node stops the walk from descending into it.
  defp outside_gate(ast, router?) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:if, _meta, [{:@, _, [{:testing_routes_mounted?, _, _}]}, _]}, found when router? ->
          {:gated_block, found}

        {:__aliases__, meta, segments} = node, found ->
          if Enum.any?(segments, &(&1 in @test_only_segments)) do
            {node, [{meta[:line], segments} | found]}
          else
            {node, found}
          end

        node, found ->
          {node, found}
      end)

    Enum.reverse(found)
  end

  defp gate_mounts_control?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:if, _meta, [{:@, _, [{:testing_routes_mounted?, _, _}]}, [do: body]]} = node, found ->
          {node, found or names_segment?(body, :TestingControl)}

        node, found ->
          {node, found}
      end)

    found
  end

  defp names_segment?(ast, segment) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _meta, segments} = node, found ->
          {node, found or segment in segments}

        node, found ->
          {node, found}
      end)

    found
  end
end
