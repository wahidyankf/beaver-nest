defmodule BnestAppWeb.RootLayoutDiagramEngineTest do
  # ADR 004, Decision 3: the browser learns where the diagram engine is from one meta tag, rendered
  # through the verified static-path helper, so a release with a new digest always names its own engine.
  # The path helper needs the endpoint running, so this is an integration test, not a unit test.
  use BnestAppWeb.ConnCase, async: false

  import Phoenix.ConnTest

  test "the root layout names the lazy diagram engine in a meta tag" do
    html = html_response(get(build_conn(), "/login"), 200)

    assert html =~
             ~s(<meta name="bnest-diagram-engine" content="/assets/js/diagrams/engine.js")
  end
end
