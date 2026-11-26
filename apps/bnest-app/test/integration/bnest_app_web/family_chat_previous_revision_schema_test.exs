defmodule BnestAppWeb.FamilyChatPreviousRevisionSchemaTest do
  @moduledoc """
  Pins the frozen previous-revision fixture's schema to the 4ee4027 schema sources.

  `family_chat_previous_revision.json` names, under `rolledBackSlot.schema`, the object
  types, root fields, argument types, and root kinds that the rolled-back browser slot
  answers from. This test checks each of them against verbatim copies of the 4ee4027
  schema sources kept beside the fixture. It reads only those files: never git history,
  never the network, and never a database.

  Each copy is also pinned to the git blob SHA of its source at 4ee4027, so an edit to a
  copy fails the test too.
  """
  use ExUnit.Case, async: true

  @support_dir Path.expand("../../../assets/test/support", __DIR__)
  @previous_revision_path Path.join(@support_dir, "family_chat_previous_revision.json")
  @previous_revision_sources [
    "family_chat_previous_revision.4ee4027.schema.ex",
    "family_chat_previous_revision.4ee4027.family_chat_types.ex",
    "family_chat_previous_revision.4ee4027.web_push_types.ex"
  ]
  # Each verbatim 4ee4027 copy, pinned to the git blob SHA of its source at 4ee4027. An edit to a
  # copy fails this test even while the fixture still matches it.
  @previous_revision_pins %{
    # 4ee4027:apps/bnest-app/lib/bnest_app_web/schema.ex
    "family_chat_previous_revision.4ee4027.schema.ex" =>
      "80e780a2232d135094528b17e587ddf828e0636c",
    # 4ee4027:apps/bnest-app/lib/bnest_app_web/schema/types/family_chat_types.ex
    "family_chat_previous_revision.4ee4027.family_chat_types.ex" =>
      "0d6a9d32824bf7beb3983fdbfd05c0129c8ff56c",
    # 4ee4027:apps/bnest-app/lib/bnest_app_web/schema/types/web_push_types.ex
    "family_chat_previous_revision.4ee4027.web_push_types.ex" =>
      "6d2ad3117117e5ffc8636427e1792f67db913a8b"
  }
  @scalars %{
    string: "String",
    id: "ID",
    integer: "Int",
    boolean: "Boolean",
    float: "Float",
    datetime: "DateTime"
  }

  test "the fixture's rolled-back schema matches the 4ee4027 schema snapshot" do
    drift = previous_revision_drift(previous_revision_schema!(), previous_revision_snapshot!())

    assert drift == [],
           "family_chat_previous_revision.json drifts from 4ee4027:\n" <> Enum.join(drift, "\n")
  end

  test "each 4ee4027 snapshot copy is byte-identical to its pinned git blob" do
    assert Enum.sort(Map.keys(@previous_revision_pins)) == Enum.sort(@previous_revision_sources)

    for {name, pinned} <- @previous_revision_pins do
      actual =
        @support_dir
        |> Path.join(name)
        |> File.read!()
        |> git_blob_sha()

      assert actual == pinned,
             "#{name} differs from its pinned 4ee4027 source (git blob #{pinned}, now #{actual}); " <>
               "restore the verbatim copy"
    end
  end

  # The SHA git gives a file's contents, computed here so the test needs no git process.
  defp git_blob_sha(content) do
    :crypto.hash(:sha, "blob " <> Integer.to_string(byte_size(content)) <> <<0>> <> content)
    |> Base.encode16(case: :lower)
  end

  defp previous_revision_schema! do
    schema =
      @previous_revision_path
      |> File.read!()
      |> Jason.decode!()
      |> get_in(["rolledBackSlot", "schema"])

    assert map_size(schema["objects"]) > 0 and map_size(schema["roots"]) > 0
    schema
  end

  # Parses the verbatim 4ee4027 sources with Elixir's own parser. A format change cannot
  # pass the comparison on an empty snapshot: the counts asserted below must be non-zero.
  defp previous_revision_snapshot! do
    nodes =
      Enum.flat_map(@previous_revision_sources, fn name ->
        @support_dir
        |> Path.join(name)
        |> File.read!()
        |> Code.string_to_quoted!()
        |> snapshot_nodes()
      end)

    objects =
      for {:object, _, [type, [do: body]]} <- nodes, into: %{} do
        {snapshot_type_name(type), snapshot_object_fields(body)}
      end

    roots =
      for {op, _, [[do: body]]} <- nodes,
          op in [:query, :mutation, :subscription],
          {:field, _, [name, type | rest]} <- snapshot_nodes(body),
          is_atom(name),
          into: %{} do
        {snapshot_field_name(name), snapshot_root_field(op, type, rest)}
      end

    assert map_size(objects) > 0 and map_size(roots) > 0
    %{objects: objects, roots: roots}
  end

  defp snapshot_nodes(ast) do
    {_, nodes} = Macro.prewalk(ast, [], fn node, acc -> {node, [node | acc]} end)
    Enum.reverse(nodes)
  end

  defp snapshot_object_fields(body) do
    for {:field, _, [name, type | _]} <- snapshot_nodes(body), is_atom(name), into: %{} do
      {snapshot_field_name(name), snapshot_named_type(type)}
    end
  end

  defp snapshot_root_field(op, type, rest) do
    args =
      case rest do
        [[do: block]] ->
          for {:arg, _, [name, arg_type]} <- snapshot_nodes(block), into: %{} do
            {snapshot_field_name(name), snapshot_graphql_type(arg_type)}
          end

        [] ->
          %{}
      end

    %{kind: Atom.to_string(op), type: snapshot_named_type(type), args: args}
  end

  # Fields and arguments are lowerCamel, object types UpperCamel, as Absinthe names them.
  defp snapshot_field_name(atom) do
    [head | tail] = atom |> Atom.to_string() |> String.split("_")
    Enum.join([head | Enum.map(tail, &String.capitalize/1)])
  end

  defp snapshot_type_name(atom) do
    atom |> Atom.to_string() |> String.split("_") |> Enum.map_join(&String.capitalize/1)
  end

  defp snapshot_named_type({:non_null, _, [inner]}), do: snapshot_named_type(inner)
  defp snapshot_named_type({:list_of, _, [inner]}), do: snapshot_named_type(inner)
  defp snapshot_named_type(atom), do: Map.get(@scalars, atom, snapshot_type_name(atom))

  defp snapshot_graphql_type({:non_null, _, [inner]}), do: snapshot_graphql_type(inner) <> "!"

  defp snapshot_graphql_type({:list_of, _, [inner]}) do
    "[" <> snapshot_graphql_type(inner) <> "]"
  end

  defp snapshot_graphql_type(atom), do: snapshot_named_type(atom)

  # Every difference between the fixture's rolled-back schema and the 4ee4027 snapshot.
  defp previous_revision_drift(fixture, snapshot) do
    object_drift =
      Enum.flat_map(fixture["objects"], fn {type, fields} ->
        case snapshot.objects[type] do
          nil -> ["object #{type}: not in the 4ee4027 schema"]
          snap_fields -> previous_object_drift(type, fields, snap_fields)
        end
      end)

    root_drift =
      Enum.flat_map(fixture["roots"], fn {name, root} ->
        case snapshot.roots[name] do
          nil -> ["root #{name}: not in the 4ee4027 schema"]
          snap -> previous_root_drift(name, root, snap)
        end
      end)

    object_drift ++ root_drift
  end

  defp previous_object_drift(type, fixture_fields, snap_fields) do
    only_snapshot = Map.keys(snap_fields) -- Map.keys(fixture_fields)
    only_fixture = Map.keys(fixture_fields) -- Map.keys(snap_fields)

    mismatched =
      for {name, want} <- fixture_fields,
          Map.has_key?(snap_fields, name),
          not previous_named_matches?(want, snap_fields[name]),
          do:
            "#{type}.#{name}: fixture #{inspect(want)}, " <>
              "4ee4027 #{inspect(snap_fields[name])}"

    Enum.map(only_snapshot, &"#{type}.#{&1}: in the 4ee4027 schema, not the fixture") ++
      Enum.map(only_fixture, &"#{type}.#{&1}: in the fixture, not the 4ee4027 schema") ++
      mismatched
  end

  # A null in the fixture is a scalar field; a name is the object type the field returns.
  defp previous_named_matches?(nil, snap), do: snap in Map.values(@scalars)
  defp previous_named_matches?(want, snap), do: want == snap

  defp previous_root_drift(name, root, snap) do
    checks = [
      {"kind", root["kind"], snap.kind},
      {"type", root["type"], snap.type},
      {"args", root["args"], snap.args}
    ]

    for {what, fixture_value, snapshot_value} <- checks, fixture_value != snapshot_value do
      "root #{name}.#{what}: fixture #{inspect(fixture_value)}, " <>
        "4ee4027 #{inspect(snapshot_value)}"
    end
  end
end
