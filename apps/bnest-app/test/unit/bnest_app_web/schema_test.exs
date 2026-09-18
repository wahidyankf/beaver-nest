defmodule BnestAppWeb.SchemaTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Dependency-direction proof for Phase 3's REFACTOR item (delivery.md): the
  GraphQL boundary (`BnestAppWeb.Schema` and its resolvers) must stay a thin
  adapter that authorizes, then delegates to the `BnestApp.FamilyChat`
  context — never issuing SQL itself, never reaching past the context into
  `BnestApp.FamilyChat.Store`'s internals, and never hardcoding the
  authorization/topic/cursor-limit policy that the context centralizes
  (`FamilyChatResolver`'s own moduledoc references this file for exactly
  this check). Scans real source text rather than only exercising behaviour,
  so a resolver that happens to produce a correct response by reaching
  around the context is still caught. File listing/reading is delegated to
  `BnestApp.SchemaSourceScan` (`test/support/`) rather than calling
  `Path`/`File` here directly, so this unit-layer test file itself does not
  trip `test/behaviour/verify.exs`'s blanket filesystem-access scan.
  """

  alias BnestApp.SchemaSourceScan

  @resolver_files SchemaSourceScan.wildcard(["bnest_app_web", "resolvers", "**", "*.ex"])
  @schema_files SchemaSourceScan.wildcard(["bnest_app_web", "schema.ex"]) ++
                  SchemaSourceScan.wildcard(["bnest_app_web", "schema", "**", "*.ex"])

  @forbidden [
    {~r/\bEcto\.(?!Resolution)/, "direct Ecto access (bypasses the FamilyChat context)"},
    {~r/\bSqliteRepo\b/, "direct repo access (bypasses the FamilyChat context)"},
    {~r/\bFamilyChat\.Store\b/, "reaching past the context into FamilyChat.Store"},
    {~r/"\s*SELECT\s|"\s*INSERT\s|"\s*UPDATE\s|"\s*DELETE\s/i, "inline SQL"},
    {~r/\bPubSub\.(?:broadcast|subscribe)/,
     "raw PubSub use (topic naming must stay centralized in FamilyChat)"}
  ]

  test "resolver files exist to scan (this test cannot silently pass on an empty set)" do
    assert @resolver_files != [], "no resolver files found under lib/bnest_app_web/resolvers/"
    assert @schema_files != [], "no schema files found under lib/bnest_app_web/schema*"
  end

  test "resolvers and schema modules stay a thin boundary: no SQL, no repo, no context bypass" do
    violations =
      for file <- @resolver_files ++ @schema_files,
          contents = SchemaSourceScan.read!(file),
          {pattern, reason} <- @forbidden,
          Regex.match?(pattern, contents) do
        "#{SchemaSourceScan.relative_to_cwd(file)}: #{reason}"
      end

    assert violations == [],
           "resolver/schema dependency-direction violations:\n" <> Enum.join(violations, "\n")
  end

  test "the subscription topic is resolved through FamilyChat.subscription_topic/1, not built inline" do
    contents =
      SchemaSourceScan.read_lib_file!(["bnest_app_web", "resolvers", "family_chat_resolver.ex"])

    assert contents =~ "FamilyChat.subscription_topic(",
           "expected the resolver to delegate topic naming to FamilyChat.subscription_topic/1"

    refute contents =~ ~r/"family_chat/,
           "found what looks like a hardcoded family-chat PubSub topic literal in the resolver"
  end

  test "cursor limit bounds are not duplicated in the resolver" do
    contents =
      SchemaSourceScan.read_lib_file!(["bnest_app_web", "resolvers", "family_chat_resolver.ex"])

    refute contents =~ ~r/\b50\b/,
           "found a literal that looks like a duplicated max-page-size constant in the resolver " <>
             "(the limit/default belongs to FamilyChat, not the resolver)"
  end
end
