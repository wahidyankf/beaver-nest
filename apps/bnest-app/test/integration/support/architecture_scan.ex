defmodule BnestApp.ArchitectureScan do
  @moduledoc """
  Static layering scan behind `BnestApp.HexagonalLayeringTest`, the rules L1 to L4 of the
  hexagonal architecture standard.

  `boundary` checks references between boundaries and to infrastructure applications. It
  cannot see the standard library (`File`, `System`, `:os`), which is no separate
  application, and it ignores bare alias references. This scan covers both by parsing each
  `lib/` source file with `Code.string_to_quoted/2` and walking the quoted form, so
  comments and strings never match. It lives under `test/integration/support/` because the
  unit layer may not read files.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @lib_root Path.expand("../../../lib", __DIR__)

  # L1: effects belong in adapters.
  @effect_modules [
    File,
    Port,
    :os,
    :file,
    Req,
    Ecto.Adapters.SQL,
    Ecto.Migrator,
    Ecto.UUID,
    Exqlite
  ]
  @effect_functions [
    {System, :cmd},
    {System, :get_env},
    {System, :fetch_env},
    {System, :fetch_env!}
  ]

  # L2: the domain is pure, so it also may not read the clock or touch processes.
  @impure_modules @effect_modules ++ [Process, GenServer, Phoenix, Logger]
  @impure_functions @effect_functions ++ [{DateTime, :utc_now}, {System, :monotonic_time}]

  # Infrastructure entry points that L1 exempts besides the `*.Adapters.*` modules.
  @effect_owners [
    BnestApp.SqliteRepo,
    BnestApp.Application,
    BnestApp.Release,
    BnestAppWeb.Endpoint,
    BnestAppWeb.Telemetry
  ]

  # L3: the core modules that belong to no context, besides the `BnestApp` root itself.
  @core_owners [BnestApp.SqliteRepo, BnestApp.Application, BnestApp.Release, BnestApp.Mailer]

  @type violation :: %{
          rule: :l1 | :l2 | :l3 | :l4,
          module: module(),
          ref: module() | atom() | nil,
          fun: atom() | nil,
          file: String.t(),
          line: non_neg_integer()
        }

  @doc "Every L1, L2, L3 and L4 violation under `lib/`."
  @spec violations() :: [violation()]
  def violations do
    sources = sources()
    reference_violations(sources) ++ unclassified(sources)
  end

  @doc "Formats violations one per line for an assertion message."
  @spec format([violation()]) :: String.t()
  def format(violations) do
    Enum.map_join(violations, "\n", fn v ->
      rule = v.rule |> Atom.to_string() |> String.upcase()
      "#{rule} #{v.file}:#{v.line} #{inspect(v.module)} #{subject(v)}"
    end)
  end

  defp subject(%{rule: :l3}), do: "is in no context"
  defp subject(%{ref: ref, fun: nil}), do: "-> #{inspect(ref)}"
  defp subject(%{ref: ref, fun: fun}), do: "-> #{inspect(ref)}.#{fun}"

  defp reference_violations(sources) do
    for {file, ast} <- sources,
        {module, body, _line} <- modules(ast, nil),
        ref <- body_references(body, module),
        rule <- broken_rules(module, ref) do
      %{rule: rule, module: module, ref: ref.module, fun: ref.fun, file: file, line: ref.line}
    end
  end

  # L3: a core module outside every context would fall into the relaxed root boundary.
  defp unclassified(sources) do
    owners = contexts(sources) ++ @core_owners

    for {file, ast} <- sources,
        core_file?(file),
        {module, _body, line} <- modules(ast, nil),
        module != BnestApp,
        not Enum.any?(owners, &within?(module, &1)) do
      %{rule: :l3, module: module, ref: nil, fun: nil, file: file, line: line}
    end
  end

  defp core_file?(file),
    do: file == "lib/bnest_app.ex" or String.starts_with?(file, "lib/bnest_app/")

  # A declared context is a `BnestApp.<Name>` facade that declares a strict boundary.
  defp contexts(sources) do
    for {_file, ast} <- sources,
        {module, body, _line} <- modules(ast, nil),
        match?(["BnestApp", _name], Module.split(module)),
        strict_boundary?(body),
        do: module
  end

  defp strict_boundary?(body) do
    {_ast, strict?} =
      Macro.prewalk(body, false, fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        {:use, _, [{:__aliases__, _, [:Boundary]}, opts]} = node, acc when is_list(opts) ->
          {node, acc or Keyword.get(opts, :type) == :strict}

        node, acc ->
          {node, acc}
      end)

    strict?
  end

  defp broken_rules(module, ref) do
    [
      {:l1, l1?(module) and effect?(ref, @effect_modules, @effect_functions)},
      {:l2, domain?(module) and effect?(ref, @impure_modules, @impure_functions)},
      {:l4, inbound?(module) and internal?(ref.module)}
    ]
    |> Enum.filter(fn {_rule, broken?} -> broken? end)
    |> Enum.map(fn {rule, _} -> rule end)
  end

  defp l1?(module) do
    not segment?(module, "Adapters") and
      not Enum.any?(@effect_owners, &within?(module, &1))
  end

  defp domain?(module), do: segment?(module, "Domain")

  defp inbound?(module), do: within?(module, BnestAppWeb) or within?(module, Mix.Tasks.Bnest)

  defp effect?(%{module: ref, fun: fun}, modules, functions) do
    Enum.any?(modules, &within?(ref, &1)) or {ref, fun} in functions
  end

  defp internal?(ref) do
    within?(ref, BnestApp) and
      (segment?(ref, "Adapters") or segment?(ref, "Ports") or within?(ref, BnestApp.SqliteRepo) or
         within?(ref, BnestApp.Storage.Records))
  end

  defp within?(module, parent) when is_atom(module) and is_atom(parent) do
    module == parent or String.starts_with?(Atom.to_string(module), Atom.to_string(parent) <> ".")
  end

  defp segment?(module, name), do: name in Module.split(module)

  defp sources do
    for path <- Path.wildcard(Path.join(@lib_root, "**/*.ex")) |> Enum.sort() do
      {:ok, ast} = path |> File.read!() |> Code.string_to_quoted(columns: false)
      {"lib/" <> Path.relative_to(path, @lib_root), ast}
    end
  end

  # Every `defmodule` with its full name, its own body and its line; nested modules are
  # listed separately.
  defp modules(ast, parent) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:defmodule, meta, [name, [do: body]]}, acc ->
          module = module_name(name, parent)
          {nil, acc ++ [{module, body, meta[:line] || 0} | modules(body, module)]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp module_name({:__aliases__, _, parts}, nil), do: Module.concat(parts)
  defp module_name({:__aliases__, _, parts}, parent), do: Module.concat([parent | parts])

  defp body_references(body, module) do
    aliases = aliases(body, module)

    {_ast, refs} =
      Macro.prewalk(body, [], fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        # A boundary declaration names dependencies; it does not call them.
        {:use, _, [{:__aliases__, _, [:Boundary]} | _]}, acc ->
          {nil, acc}

        {:alias, meta, [target | _]}, acc ->
          targets = alias_targets(target, module)
          {nil, acc ++ Enum.map(targets, &%{module: &1, fun: nil, line: meta[:line] || 0})}

        # Keep walking the arguments, but not the callee, so a call counts once.
        {{:., meta, [callee, fun]}, _, args} = node, acc when is_atom(fun) ->
          rest = if is_list(args), do: {:__block__, [], args}, else: nil

          case resolve(callee, aliases, module) do
            nil -> {node, acc}
            ref -> {rest, acc ++ [%{module: ref, fun: fun, line: meta[:line] || 0}]}
          end

        {:__aliases__, meta, _parts} = node, acc ->
          ref = resolve(node, aliases, module)
          {nil, acc ++ [%{module: ref, fun: nil, line: meta[:line] || 0}]}

        node, acc ->
          {node, acc}
      end)

    Enum.reject(refs, &is_nil(&1.module))
  end

  # Lexical aliases of one module body, plus the implicit alias of each nested module.
  defp aliases(body, module) do
    {_ast, aliases} =
      Macro.prewalk(body, %{}, fn
        {:defmodule, _, [{:__aliases__, _, [first | _]}, _]}, acc ->
          {nil, Map.put(acc, first, Module.concat([module, first]))}

        {:alias, _, [target]}, acc ->
          {nil, Enum.reduce(alias_targets(target, module), acc, &Map.put(&2, last(&1), &1))}

        {:alias, _, [target, opts]}, acc when is_list(opts) ->
          case {alias_targets(target, module), Keyword.get(opts, :as)} do
            {[full], {:__aliases__, _, [as]}} -> {nil, Map.put(acc, as, full)}
            {targets, _} -> {nil, Enum.reduce(targets, acc, &Map.put(&2, last(&1), &1))}
          end

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp alias_targets({{:., _, [base, :{}]}, _, children}, module) do
    prefix = expand(base, %{}, module)
    for {:__aliases__, _, parts} <- children, do: Module.concat([prefix | parts])
  end

  defp alias_targets(target, module), do: [expand(target, %{}, module)]

  defp resolve(callee, _aliases, _module) when is_atom(callee), do: callee

  defp resolve({:__aliases__, _, _} = callee, aliases, module),
    do: expand(callee, aliases, module)

  defp resolve({:__MODULE__, _, _}, _aliases, module), do: module
  defp resolve(_callee, _aliases, _module), do: nil

  defp expand({:__aliases__, _, [{:__MODULE__, _, _} | rest]}, _aliases, module),
    do: Module.concat([module | rest])

  defp expand({:__aliases__, _, [first | rest]}, aliases, _module) when is_atom(first) do
    case Map.fetch(aliases, first) do
      {:ok, full} -> Module.concat([full | rest])
      :error -> Module.concat([first | rest])
    end
  end

  defp expand({:__MODULE__, _, _}, _aliases, module), do: module
  defp expand(_other, _aliases, _module), do: nil

  defp last(module), do: module |> Module.split() |> List.last() |> String.to_atom()
end
