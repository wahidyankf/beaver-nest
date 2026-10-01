defmodule BnestApp.Storage.Domain.RecordMapTest do
  use ExUnit.Case, async: true

  alias BnestApp.Storage.Domain.RecordMap

  @owner "user-test-map"

  test "classifies every flat-file record path" do
    for {path, type, record_type, owner, key} <- [
          {"system/bootstrap.json", :bootstrap, "bootstrap", nil, "singleton"},
          {"system/schema-registry.json", :schema_registry, "schema-registry", nil, "singleton"},
          {"system/accounts/#{@owner}.json", :account, "account", @owner, @owner},
          {"system/usernames/test-user-map.json", :username_index, "username-index", nil,
           "test-user-map"},
          {"system/sessions/digest.json", :session, "browser-session", nil, "digest"},
          {"system/manifests/import-map.json", :manifest, "import-manifest", nil, "import-map"},
          {"users/#{@owner}/imports/import-map.json", :browser_import, "browser-import", @owner,
           "#{@owner}:import-map"},
          {"users/#{@owner}/chat/current.json", :chat, "chat", @owner, @owner},
          {"users/#{@owner}/sifat-allah/progress.json", :sifat_allah, "sifat-allah-progress",
           @owner, @owner},
          {"users/#{@owner}/preferences/theme.json", :theme, "theme-preference", @owner, @owner}
        ] do
      assert RecordMap.classify(path) ==
               {:ok, %{type: type, record_type: record_type, owner_id: owner, record_key: key}},
             path
    end

    assert RecordMap.classify("users/#{@owner}/notes.json") == {:error, :unsupported_source}
    assert length(RecordMap.sources_for_migration()) == 10
  end

  test "names the SQLite identity of every record type" do
    for {type, identity, record_type, key, owner} <- [
          {:bootstrap, nil, "bootstrap", "singleton", nil},
          {:schema_registry, nil, "schema-registry", "singleton", nil},
          {:account, @owner, "account", @owner, @owner},
          {:username_index, "test-user-map", "username-index", "test-user-map", nil},
          {:session, "digest", "browser-session", "digest", nil},
          {:manifest, "import-map", "import-manifest", "import-map", nil},
          {:browser_import, {@owner, "import-map"}, "browser-import", "#{@owner}:import-map",
           @owner},
          {:chat, @owner, "chat", @owner, @owner},
          {:sifat_allah, @owner, "sifat-allah-progress", @owner, @owner},
          {:theme, @owner, "theme-preference", @owner, @owner}
        ] do
      assert RecordMap.identity_for(type, identity) ==
               {:ok, %{record_type: record_type, record_key: key, owner_id: owner}},
             inspect(type)
    end

    assert RecordMap.identity_for(:unknown, @owner) == {:error, :unsupported_record_type}
  end

  test "keys a destination by record type and record key" do
    assert RecordMap.destination_key("bootstrap", nil) == "bootstrap/singleton"
    assert RecordMap.destination_key("chat", @owner) == "chat/#{@owner}"
  end
end
