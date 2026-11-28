defmodule BnestApp.ScheduledGatesWorkflow do
  @moduledoc """
  Pure check of the scheduled quality-gates workflow against the Playwright projects and the gate registry.

  It takes the three texts (the workflow, the Playwright config, and `repo-config.yml`) and returns the
  findings as messages, empty when everything holds. It reads no file, no path, and no process state, so a unit
  test can feed it inline fixtures and an integration test can feed it the real files. The repository has no YAML
  parser dependency, so the texts are read by their fixed two-space layout.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @setup_project "one-time-setup"
  @frontend_job "bnest-test-e2e-fe"
  @backend_job "bnest-test-e2e-be"
  @cron "0 6,18 * * *"
  @zone "Asia/Jakarta"
  @backend_run "./rhino gate run --surface scheduled --entry test-e2e-be\n"
  @frontend_run "./rhino gate run --surface scheduled --entry test-e2e-fe-${{ matrix.project }}\n"

  @doc """
  The findings for the three texts, in the order the scenario states them. An empty list means the workflow runs
  at 06:00 and 18:00 WIB, on manual dispatch, serially, and runs each end-to-end suite as its own job.
  """
  @spec findings(String.t(), String.t(), String.t()) :: [String.t()]
  def findings(workflow, playwright_config, registry) do
    top = blocks_at(workflow, 0)
    jobs = top |> block("jobs") |> blocks_at(2)
    entries = registry_entries(registry)
    backend = block(jobs, @backend_job)
    frontend = block(jobs, @frontend_job)
    matrix = matrix_projects(frontend)
    projects = playwright_projects(playwright_config)

    trigger_findings(block(top, "on")) ++
      concurrency_findings(block(top, "concurrency")) ++
      job_findings(jobs, backend, frontend) ++
      integration_findings(workflow, jobs, entries) ++
      matrix_findings(matrix, projects, entries) ++
      leg_findings(backend, frontend, matrix, entries) ++
      registry_findings(matrix, entries)
  end

  defp trigger_findings(trigger) do
    crons = scan(trigger, ~r/^\s+- cron: "([^"]*)"$/m)
    zones = scan(trigger, ~r/^\s+timezone: "([^"]*)"$/m)

    expect(
      crons == [@cron],
      "the workflow must run on exactly one cron, #{@cron}; it runs on #{inspect(crons)}"
    ) ++
      expect(
        zones == [@zone],
        "the schedule must run in the #{@zone} zone; it runs in #{inspect(zones)}"
      ) ++
      expect(
        Regex.match?(~r/^ {2}workflow_dispatch:/m, trigger),
        "the workflow must run on manual dispatch (workflow_dispatch)"
      )
  end

  defp concurrency_findings(concurrency) do
    expect(
      Regex.match?(~r/^ {2}group: \S+$/m, concurrency),
      "the workflow must run in one concurrency group (group: <name>)"
    ) ++
      expect(
        Regex.match?(~r/^ {2}cancel-in-progress: false$/m, concurrency) and
          not Regex.match?(~r/cancel-in-progress: (?!false\b)/, concurrency),
        "the workflow must run serially and never cancel a run in progress (cancel-in-progress: false)"
      )
  end

  defp job_findings(jobs, backend, frontend) do
    names = jobs |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    expect(
      names == Enum.sort([@backend_job, @frontend_job]),
      "the workflow must declare one job for the back-end suite and one for the front-end suite, and no other; " <>
        "it declares #{inspect(names)}"
    ) ++
      expect(
        not String.contains?(backend, "--entry test-e2e-fe"),
        "the back-end job must run no front-end entry"
      ) ++
      expect(
        not String.contains?(frontend, "--entry test-e2e-be"),
        "the front-end job must run no back-end entry"
      ) ++
      wait_findings(@backend_job, backend, "back-end", @frontend_job, "front-end") ++
      wait_findings(@frontend_job, frontend, "front-end", @backend_job, "back-end")
  end

  # A job must not wait for the other suite's job. A needs the check cannot read in full is a finding of its own,
  # because reading it as waiting for nothing would let a wait pass unseen.
  defp wait_findings(job_name, job, label, other_name, other_label) do
    case needs(job) do
      {:ok, names} ->
        expect(
          other_name not in names,
          "the #{label} job must not wait for the #{other_label} job (needs #{inspect(names)})"
        )

      {:unreadable, raw} ->
        [
          "unreadable needs in job #{job_name} (the #{label} job): #{inspect(raw)}; " <>
            "write it as a job name, a flow list of job names, or a block list of job names"
        ]
    end
  end

  defp integration_findings(workflow, jobs, entries) do
    integration = Enum.find(entries, &(&1.id == "test-integration"))
    scheduled_integration = Enum.filter(scheduled_ids(entries), &(&1 =~ "integration"))
    integration_jobs = jobs |> Enum.map(&elem(&1, 0)) |> Enum.filter(&(&1 =~ "integration"))

    expect(
      integration != nil and integration.surfaces == ["pull-request"],
      "the registry entry test-integration must run on the pull-request surface only"
    ) ++
      expect(
        scheduled_integration == [],
        "no scheduled registry entry may run integration; found #{inspect(scheduled_integration)}"
      ) ++
      expect(
        integration_jobs == [],
        "the workflow must have no integration job; found #{inspect(integration_jobs)}"
      ) ++
      expect(
        not Regex.match?(~r/--entry test-integration|test:integration/, workflow),
        "no workflow step may run the integration entry or target"
      )
  end

  defp matrix_findings(matrix, projects, entries) do
    registered =
      entries |> Enum.map(& &1.id) |> Enum.filter(&String.starts_with?(&1, "test-e2e-fe-"))

    expected_ids = Enum.map(projects, &"test-e2e-fe-#{&1}")

    expect(
      projects != [],
      "the Playwright config must declare a project besides #{@setup_project}"
    ) ++
      expect(
        matrix == projects,
        "the front-end matrix must list the Playwright projects in playwright.config.mts, " <>
          "except #{@setup_project}, in order; expected #{inspect(projects)}, found #{inspect(matrix)}"
      ) ++
      expect(
        registered == expected_ids,
        "the registry must list one test-e2e-fe entry per Playwright project, in the same order; " <>
          "expected #{inspect(expected_ids)}, found #{inspect(registered)}"
      )
  end

  defp leg_findings(backend, frontend, matrix, entries) do
    expect(
      String.contains?(backend, @backend_run),
      "the back-end job must run #{String.trim(@backend_run)}"
    ) ++
      expect(
        String.contains?(frontend, @frontend_run),
        "the front-end job must run #{String.trim(@frontend_run)}"
      ) ++
      leg_entry_findings("test-e2e-be", nil, entries) ++
      Enum.flat_map(matrix, &leg_entry_findings("test-e2e-fe-#{&1}", &1, entries))
  end

  # A leg's registry entry runs on the scheduled surface only and, for a front-end leg, runs only its project.
  defp leg_entry_findings(id, project, entries) do
    case Enum.find(entries, &(&1.id == id)) do
      nil ->
        ["the registry has no entry #{id}"]

      leg ->
        expect(
          leg.surfaces == ["scheduled"],
          "the registry entry #{id} must run on the scheduled surface only; it runs on #{inspect(leg.surfaces)}"
        ) ++ project_findings(id, project, leg)
    end
  end

  defp project_findings(_id, nil, _leg), do: []

  defp project_findings(id, project, leg) do
    flags = scan(leg.body, ~r/--project=(\S+) \}/)

    expect(
      flags == [project],
      "#{id} must run only --project=#{project}; it runs #{inspect(flags)}"
    )
  end

  defp registry_findings(matrix, entries) do
    run = ["test-e2e-be" | Enum.map(matrix, &"test-e2e-fe-#{&1}")]
    scheduled = scheduled_ids(entries)

    expect(
      scheduled == run,
      "every scheduled registry entry must have a job that runs it, and no job may lack its entry: " <>
        "a scheduled registry entry has no job, or a job has no entry; " <>
        "the registry schedules #{inspect(scheduled)}, the workflow runs #{inspect(run)}"
    )
  end

  defp scheduled_ids(entries) do
    for entry <- entries, "scheduled" in entry.surfaces, do: entry.id
  end

  defp expect(true, _message), do: []
  defp expect(false, message), do: [message]

  defp scan(text, regex), do: Regex.scan(regex, text, capture: :all_but_first) |> Enum.map(&hd/1)

  defp block(blocks, name) do
    case List.keyfind(blocks, name, 0) do
      {^name, text} -> text
      nil -> ""
    end
  end

  # The text under each `key:` that stands alone on a line at the given indent, in declared order. A block
  # runs to the next key at the same indent. Text before the first key is dropped.
  defp blocks_at(text, indent) do
    key = Regex.compile!("^ {#{indent}}([A-Za-z0-9_-]+):\\s*$")

    text
    |> String.split("\n")
    |> Enum.reduce([], fn line, blocks ->
      case {Regex.run(key, line, capture: :all_but_first), blocks} do
        {[name], _} -> [{name, []} | blocks]
        {nil, [{name, lines} | rest]} -> [{name, [line | lines]} | rest]
        {nil, []} -> []
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {name, lines} -> {name, lines |> Enum.reverse() |> Enum.join("\n")} end)
  end

  # The job names under a job's `needs:`, as `{:ok, names}`: a plain name, a flow list (on one line or spread over
  # several), or a block list of `- a` lines. A list marker, quotes, and a trailing comment are not part of a name.
  # A job without `needs:` waits for nothing. Anything else the check cannot read in full, such as a mapping, a
  # block scalar, an anchor, an alias, a tag, an expression, an unterminated quote, a list that never closes, or an
  # empty value, comes back as `{:unreadable, raw}`, never as an empty list, so it fails closed.
  defp needs(job) do
    lines = String.split(job, "\n")

    case Enum.find_index(lines, &Regex.match?(~r/^ {4}needs:/, &1)) do
      nil ->
        {:ok, []}

      start ->
        inline = lines |> Enum.at(start) |> String.replace(~r/^ {4}needs:/, "") |> strip_comment()
        read_needs(inline, Enum.drop(lines, start + 1))
    end
  end

  defp read_needs("", rest) do
    case block_items(rest) do
      {[], _tail} -> {:unreadable, "no value"}
      {items, tail} -> items |> Enum.map(&scalar/1) |> collect(tail)
    end
  end

  defp read_needs("[" <> opened = inline, rest) do
    case flow_body(opened, rest, []) do
      {:ok, body, tail} -> body |> flow_items() |> collect(tail)
      :unreadable -> {:unreadable, inline}
    end
  end

  defp read_needs(inline, rest), do: collect([scalar(inline)], rest)

  # The text of a flow list up to its `]`, from however many lines it spans, and the lines after it. Only a comment
  # may follow the `]`, and a list that never closes is unreadable.
  defp flow_body(text, rest, acc) do
    case String.split(text, "]", parts: 2) do
      [body, ""] ->
        {:ok, join_flow([body | acc]), rest}

      [_body, _trailing] ->
        :unreadable

      [_open] when rest == [] ->
        :unreadable

      [open] ->
        [next | more] = rest
        flow_body(strip_comment(next), more, [open | acc])
    end
  end

  defp join_flow(parts) do
    parts
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp flow_items(""), do: []

  defp flow_items(body) do
    items = body |> String.split(",") |> Enum.map(&String.trim/1)
    items = if List.last(items) == "" and length(items) > 1, do: Enum.drop(items, -1), else: items
    Enum.map(items, &scalar/1)
  end

  # One name: a job id, bare or in a matching pair of quotes. Any other shape is unreadable.
  defp scalar(text) do
    name = text |> strip_comment() |> unquote_pair()

    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_-]*$/, name),
      do: {:ok, name},
      else: {:unreadable, text}
  end

  defp unquote_pair(text) do
    case Regex.run(~r/^(["'])(.*)\1$/, text) do
      [_whole, _quote, inner] -> inner
      nil -> text
    end
  end

  defp strip_comment(text), do: text |> String.replace(~r/(^|\s)#.*$/, "") |> String.trim()

  # The names when every item was readable and the value ends where the next job key starts; the first unreadable
  # item, or a line still indented under the value, otherwise.
  defp collect(results, tail) do
    case Enum.find(results, &match?({:unreadable, _raw}, &1)) do
      nil ->
        if ends_cleanly?(tail),
          do: {:ok, for({:ok, name} <- results, do: name)},
          else: {:unreadable, hd(tail)}

      unreadable ->
        unreadable
    end
  end

  # The next line that is neither blank nor a comment must be a key of the job or a later block, not a continuation.
  defp ends_cleanly?(lines) do
    case Enum.find(lines, &(not Regex.match?(~r/^\s*(#.*)?$/, &1))) do
      nil -> true
      line -> Regex.match?(~r/^ {0,4}\S/, line)
    end
  end

  # The items of a block list, as written after the marker, and the lines after the list. Blank and comment lines
  # inside it are skipped, and the first other line ends it.
  defp block_items([]), do: {[], []}

  defp block_items([line | rest] = lines) do
    cond do
      Regex.match?(~r/^\s*(#.*)?$/, line) ->
        block_items(rest)

      Regex.match?(~r/^\s+-(\s|$)/, line) ->
        {items, tail} = block_items(rest)
        {[String.replace(line, ~r/^\s+-\s*/, "") | items], tail}

      true ->
        {[], lines}
    end
  end

  defp matrix_projects(frontend) do
    case scan(frontend, ~r/^ {8}project:\s*\[([^\]]*)\]/m) do
      [listed | _] -> listed |> String.split(",") |> Enum.map(&String.trim/1)
      [] -> []
    end
  end

  # The Playwright projects other than the shared setup project, in the order the config declares them.
  defp playwright_projects(config) do
    case String.split(config, "projects: [", parts: 2) do
      [_before, after_projects] ->
        after_projects
        |> scan(~r/^ {6}name: "([^"]+)"/m)
        |> Enum.reject(&(&1 == @setup_project))

      [_no_projects] ->
        []
    end
  end

  # Registry entries in declared order, each with the surfaces under its `run-on:` key.
  defp registry_entries(registry) do
    ~r/^ {4}- id: (\S+)$/m
    |> Regex.split(registry, include_captures: true)
    |> tl()
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [header, rest] -> [registry_entry(header, rest)]
      [_header] -> []
    end)
  end

  defp registry_entry(header, rest) do
    [body | _] = Regex.split(~r/^\S/m, rest, parts: 2)
    run_on = scan(body, ~r/run-on:\n((?: {8}.*(?:\n|$))*)/)

    %{
      id: header |> String.trim() |> String.replace_prefix("- id: ", ""),
      body: body,
      surfaces: Enum.flat_map(run_on, &scan(&1, ~r/^ {8}([a-z-]+):/m))
    }
  end
end
