defmodule BnestAppWeb.DiagramEngineBundleTest do
  # ADR 004, Decision 4: the diagram engine is a second esbuild profile with code splitting. The main
  # `bnest_app` profile stays one classic IIFE, so the page script and app.js do not change size.
  use ExUnit.Case, async: true

  @required_flags [
    "--bundle",
    "--splitting",
    "--format=esm",
    "--target=es2022",
    "--outdir=../priv/static/assets/js/diagrams",
    "--chunk-names=chunks/[name]-[hash]",
    "--alias:elkjs/lib/elk.bundled.js=./js/diagrams/elk_disabled.js"
  ]

  test "the diagram profile bundles engine.js into split ES modules with elkjs stubbed" do
    profile = Application.get_env(:esbuild, :bnest_app_diagrams)

    assert is_list(profile), "the bnest_app_diagrams esbuild profile must be configured"
    assert "js/diagrams/engine.js" in profile[:args]

    for flag <- @required_flags do
      assert flag in profile[:args], "missing esbuild flag #{flag}"
    end

    # A plain string check: the unit layer reads configuration only and never touches the filesystem.
    assert String.ends_with?(profile[:cd], "/assets")
  end

  test "the main bundle keeps its classic IIFE output and no splitting" do
    args = Application.get_env(:esbuild, :bnest_app)[:args]

    refute "--splitting" in args
    refute "--format=esm" in args
    refute Enum.any?(args, &String.starts_with?(&1, "--alias:elkjs"))
  end

  test "assets.build and assets.deploy build the diagram profile" do
    aliases = Mix.Project.config()[:aliases]

    assert Enum.any?(aliases[:"assets.build"], &(&1 == "esbuild bnest_app_diagrams"))

    assert Enum.any?(
             aliases[:"assets.deploy"],
             &String.starts_with?(&1, "esbuild bnest_app_diagrams")
           )
  end
end
