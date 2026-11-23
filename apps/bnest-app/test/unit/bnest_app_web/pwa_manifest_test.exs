defmodule BnestAppWeb.PwaManifestTest do
  # The served web manifest names Beaver Nest as a standalone app and lists
  # the two icons the install metadata names, and every icon loads.
  #
  # @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The web manifest names Beaver Nest as a standalone app with two icons
  use ExUnit.Case, async: true

  alias BnestAppWeb.Pwa

  @manifest_path Application.app_dir(:bnest_app, "priv/static/manifest.webmanifest")

  test "names Beaver Nest as a standalone app with the metadata's two icons" do
    {:ok, bytes} = :file.read_file(@manifest_path)
    manifest = Jason.decode!(bytes)

    assert manifest["name"] == "Beaver Nest"
    assert manifest["short_name"] == "Beaver Nest"
    assert manifest["display"] == "standalone"
    assert manifest["start_url"] == "/"

    icon_sources = manifest["icons"] |> Enum.map(& &1["src"]) |> Enum.sort()
    assert icon_sources == Pwa.install_metadata().icon_paths |> Enum.sort()
    assert length(icon_sources) == 2
  end

  test "every icon file the manifest names exists" do
    {:ok, bytes} = :file.read_file(@manifest_path)
    manifest = Jason.decode!(bytes)

    for %{"src" => path} <- manifest["icons"] do
      full = Application.app_dir(:bnest_app, "priv/static/" <> String.trim_leading(path, "/"))
      assert {:ok, _} = :file.read_file(full), "missing icon file #{path}"
    end
  end
end
