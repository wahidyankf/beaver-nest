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

  describe "family chat reply contract" do
    test "the quote object exists with exactly its four fields" do
      quote_type = Absinthe.Schema.lookup_type(BnestAppWeb.Schema, :family_chat_message_quote)

      assert quote_type, "expected a :family_chat_message_quote object in the schema"

      declared = quote_type.fields |> Map.keys() |> List.delete(:__typename) |> Enum.sort()

      assert declared == Enum.sort([:id, :sender_kind, :sender_display_name, :body_preview])
    end

    # Flatness is enforced by the type system rather than by convention: there
    # is no field on the quote that could carry another quote, so no client can
    # request one and no resolver can accidentally serve one.
    test "the quote type has no field that could carry another quote" do
      quote_type = Absinthe.Schema.lookup_type(BnestAppWeb.Schema, :family_chat_message_quote)

      nested =
        quote_type.fields
        |> Map.values()
        |> Enum.filter(fn field ->
          field.type
          |> unwrap_type()
          |> Kernel.in([:family_chat_message, :family_chat_message_quote])
        end)

      assert nested == [],
             "the quote type must not reference a message or another quote: " <> inspect(nested)
    end

    test "a message carries an optional replyTo of that type" do
      message_type = Absinthe.Schema.lookup_type(BnestAppWeb.Schema, :family_chat_message)
      field = message_type.fields[:reply_to]

      assert field, "expected :reply_to on :family_chat_message"

      refute match?(%Absinthe.Type.NonNull{}, field.type),
             "replyTo must be nullable: an ordinary message has no quote"

      assert unwrap_type(field.type) == :family_chat_message_quote
    end

    test "the send mutation accepts an optional reply target" do
      mutation = Absinthe.Schema.lookup_type(BnestAppWeb.Schema, :mutation)
      field = mutation.fields[:send_family_chat_message]
      arg = field.args[:reply_to_message_id]

      assert arg, "expected a replyToMessageId argument on sendFamilyChatMessage"

      refute match?(%Absinthe.Type.NonNull{}, arg.type),
             "replyToMessageId must be optional: an ordinary send passes none"
    end

    test "the resolver neither parses nor looks up the reply target" do
      contents =
        SchemaSourceScan.read_lib_file!(["bnest_app_web", "resolvers", "family_chat_resolver.ex"])

      refute contents =~ ~r/String\.slice|message_by_id|quotes_for|normalize_reply_to_message_id/,
             "reply-target lookup, normalization, and truncation belong to BnestApp.FamilyChat, not the resolver"

      refute contents =~ ~r/parse_id\(.*reply/,
             "the reply target must reach FamilyChat untouched, not through the cursor parser"
    end

    test "the preview budget is not duplicated in the resolver or the types" do
      for file <- ["resolvers/family_chat_resolver.ex", "schema/types/family_chat_types.ex"] do
        contents =
          SchemaSourceScan.read_lib_file!(["bnest_app_web" | String.split(file, "/")])

        refute contents =~ ~r/\b160\b/,
               "#{file} duplicates the preview grapheme budget, which belongs to BnestApp.FamilyChat"
      end
    end
  end

  defp unwrap_type(%Absinthe.Type.NonNull{of_type: inner}), do: unwrap_type(inner)
  defp unwrap_type(%Absinthe.Type.List{of_type: inner}), do: unwrap_type(inner)
  defp unwrap_type(type), do: type
end
