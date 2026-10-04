defmodule BnestApp.Test.IntegrityLabel do
  @moduledoc """
  Test-only reading and checks of the Schedules page's `Backup files` label, shared by the unit
  and integration behaviour drivers (`scheduled_backups.feature`, the backup-integrity page
  scenarios). A driver opens the page in its layer and keeps what it rendered in the context
  (`:label_first` right after the connected mount, `:label_page` once the check finished,
  `:label_after_save` and `:label_settled_after_save` around a save); this module reads those
  renders and answers each Then from them.

  The label is found by the markup the selected design fixes, and nothing else:

    * the schedule row `[data-schedule-key="prod-sqlite-backup-daily"]`;
    * inside it a `dt` whose text is `Backup files`, after the `Last result` term, and its parent
      element (the item) holding the `dd` description;
    * the `dd` text without its list and decorative markers is the summary; each `li` of the
      `dd` is one problem line;
    * one `[aria-live="polite"]` element of the row that contains the description.

  What the page should say is read from the destination's files (`BackupIntegrity.expected_label/1`)
  and printed in the exact copy of the plan's States and Real Copy table; no check calls the
  wording function it verifies. A server-rendered layer cannot scroll, focus or announce, so
  the checks that name those properties assert the markup that would break them (a truncating
  or width-forcing style, a focusable element or focus command in the label, a page change
  outside the label when the result arrives, an assertive region); the browser journeys prove
  the properties themselves.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias BnestApp.Test.BackupIntegrity
  alias BnestApp.Test.ObservedArtifactStore
  alias Phoenix.LiveView.Async

  @row ~s([data-schedule-key="prod-sqlite-backup-daily"])
  @term "Backup files"
  @last_result "Last result"
  @checking "checking"
  @could_not_check "could not be checked. Run mix bnest.backup.reconcile on the host."
  @nothing_to_check "no verified backup to check yet"
  @problem_line ~r/^\d{4}-\d{2}-\d{2}: file (?:missing|changed)$/
  @date ~r/\d{4}-\d{2}-\d{2}/
  @result_summary ~r/(?:are present|is present|attention)$/

  # The ceiling the page waits for the check, lowered through application configuration so a
  # reconciliation that never ends is cancelled within the test; the page's default is five
  # seconds. The key is the one seam the page is built to read (an assumption recorded in the
  # scenario's report): `config :bnest_app, BnestAppWeb.AdminScheduleSettingsLive,
  # integrity_ceiling_ms: <milliseconds>`.
  @ceiling_ms 300
  @ceiling_config {BnestAppWeb.AdminScheduleSettingsLive, :integrity_ceiling_ms}

  # How long a driver waits for a check to finish: longer than the page's default ceiling, so
  # a page that ignores the lowered one still ends within it.
  @settle_ms 8_000
  @cancel_wait_ms 1_500
  @quiet_ms 300

  # Elements and class tokens that make text truncate, clip or force a width.
  @truncating_tags ~w(marquee)
  @truncating_classes ~w(truncate whitespace-nowrap text-ellipsis overflow-hidden overflow-x-hidden overflow-x-auto overflow-x-scroll overflow-auto overflow-scroll)
  @truncating_style ~r/nowrap|ellipsis|overflow|(?:^|[;\s])(?:min-|max-)?width|position:\s*(?:absolute|fixed)/i

  @outcomes [
    :label_states_all_present,
    :label_no_problem_dates,
    :label_counts_attention,
    :label_lists_problems,
    :label_counts_intact_present,
    :label_states_could_not_check,
    :page_and_forms_usable,
    :label_states_nothing_to_check,
    :label_not_present,
    :label_checking_then_result,
    :label_one_needs_attention,
    :focus_does_not_move,
    :rendered_destination_unchanged,
    :label_private_free,
    :label_matches_report,
    :forms_usable_before_result,
    :label_checking_until_ceiling,
    :label_could_not_check_at_ceiling,
    :check_cancelled_at_ceiling,
    :no_reconciliation_started,
    :label_reflows,
    :problem_lines_whole,
    :problems_conveyed_by_text,
    :label_announced_in_place,
    :focus_order_unchanged,
    :result_announced_politely
  ]

  @doc "The Then checks this module answers."
  @spec outcomes() :: [atom()]
  def outcomes, do: @outcomes

  # ---------------------------------------------------------------------------------------
  # Seams the drivers use
  # ---------------------------------------------------------------------------------------

  @doc "How long a driver waits for the page's check to finish."
  @spec settle_ms() :: pos_integer()
  def settle_ms, do: @settle_ms

  @doc "The lowered ceiling, in milliseconds."
  @spec ceiling_ms() :: pos_integer()
  def ceiling_ms, do: @ceiling_ms

  @doc "A monotonic clock reading, in milliseconds."
  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)

  @doc """
  Lowers the page's check ceiling for the calling test and restores it afterwards.
  """
  @spec lower_ceiling!(pos_integer()) :: :ok
  def lower_ceiling!(milliseconds \\ @ceiling_ms) do
    {module, key} = @ceiling_config
    previous = Application.get_env(:bnest_app, module)
    Application.put_env(:bnest_app, module, Keyword.put(previous || [], key, milliseconds))

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:bnest_app, module, previous),
        else: Application.delete_env(:bnest_app, module)
    end)
  end

  @doc """
  Delivers the results of the checks a unit-layer socket started, the way the LiveView channel
  delivers them to a running page, until none is pending or `timeout` milliseconds have passed.
  The unit layer mounts the page without a channel, so nothing else would hand the result to
  the socket. A result of a check that a newer one superseded is dropped, as the channel
  drops it.
  """
  @spec settle(Phoenix.LiveView.Socket.t(), non_neg_integer()) :: Phoenix.LiveView.Socket.t()
  def settle(socket, timeout \\ @settle_ms), do: settle_until(socket, now() + timeout)

  defp settle_until(socket, deadline) do
    if pending?(socket) do
      receive do
        {:phoenix, :async_result, {kind, {reference, _component, keys, result}}} ->
          socket
          |> Async.handle_async(nil, kind, keys, reference, result)
          |> settle_until(deadline)
      after
        max(deadline - now(), 0) -> socket
      end
    else
      socket
    end
  end

  defp pending?(socket), do: map_size(Map.get(socket.private, :live_async, %{})) > 0

  @doc """
  What happened to the work of a check that was held past the ceiling: the processes that
  were waiting, whether each of them died, and how many artifact reads were made when the
  result was in and after a quiet period. `elapsed_ms` is how long the page took to give its
  result.
  """
  @spec observe_ceiling(integer()) :: map()
  def observe_ceiling(elapsed_ms) do
    blocked = ObservedArtifactStore.blocked_pids()
    monitors = Enum.map(blocked, &{&1, Process.monitor(&1)})

    all_down? =
      Enum.all?(monitors, fn {pid, reference} ->
        receive do
          {:DOWN, ^reference, :process, ^pid, _reason} -> true
        after
          @cancel_wait_ms -> false
        end
      end)

    reads_when_cancelled = ObservedArtifactStore.read_count()
    Process.sleep(@quiet_ms)

    %{
      elapsed_ms: elapsed_ms,
      blocked_pids: blocked,
      all_down?: all_down?,
      reads_when_cancelled: reads_when_cancelled,
      reads_later: ObservedArtifactStore.read_count()
    }
  end

  # ---------------------------------------------------------------------------------------
  # Reading the page
  # ---------------------------------------------------------------------------------------

  @doc """
  The label of the production backup row in `page`, or `nil` when the row carries no
  `Backup files` term. `html` is the item's markup, text and attributes alike.
  """
  @spec read(LazyHTML.t()) :: map() | nil
  def read(page) do
    row = nodes(LazyHTML.query(page, @row))

    case find_item(row) do
      nil -> nil
      item -> label(row, item)
    end
  end

  defp label(row, item) do
    dd = item |> children() |> all() |> Enum.find(&(tag(&1) == "dd"))
    summary = if dd, do: text(dd, &(decoration?(&1) or tag(&1) in ["ul", "ol"])), else: ""
    terms = row |> all() |> Enum.filter(&(tag(&1) == "dt")) |> Enum.map(&text/1)

    %{
      item: item,
      html: LazyHTML.to_html(LazyHTML.from_tree([item])),
      summary: summary,
      description: if(dd, do: text(dd, &decoration?/1), else: ""),
      problems:
        if(dd,
          do: dd |> all() |> Enum.filter(&(tag(&1) == "li")) |> Enum.map(&plain_text/1),
          else: []
        ),
      in_place?: ordered?(terms, @last_result, @term),
      region: polite_region(row, summary)
    }
  end

  defp find_item(nodes) do
    Enum.find_value(nodes, fn
      {_tag, _attributes, children} = node ->
        if Enum.any?(children, &term?/1), do: node, else: find_item(children)

      _text ->
        nil
    end)
  end

  defp term?({"dt", _attributes, _children} = node), do: text(node) == @term
  defp term?(_node), do: false

  defp ordered?(terms, first, second) do
    first = Enum.find_index(terms, &(&1 == first))
    second = Enum.find_index(terms, &(&1 == second))
    first != nil and second != nil and first < second
  end

  defp polite_region(row, summary) do
    row
    |> all()
    |> Enum.filter(&(attribute(&1, "aria-live") == "polite"))
    |> Enum.find(&String.contains?(plain_text(&1), summary))
  end

  @doc "Whether the page renders both forms, each with its fields and an enabled submit."
  @spec forms_usable?(LazyHTML.t()) :: boolean()
  def forms_usable?(page) do
    [
      "form[phx-submit=save_schedule] input[name='schedule[daily_time_wib]']",
      "form[phx-submit=save_schedule] button[type=submit]:not([disabled])",
      "form[phx-submit=save_backup] input[name='backup[destination_directory]']",
      "form[phx-submit=save_backup] button[type=submit]:not([disabled])"
    ]
    |> Enum.all?(&(Enum.count(LazyHTML.query(page, &1)) > 0))
  end

  # ---------------------------------------------------------------------------------------
  # Then
  # ---------------------------------------------------------------------------------------

  @doc "Whether the renders a Then reads confirm what it states."
  @spec outcome?(map(), atom(), list()) :: boolean()
  def outcome?(context, :label_states_all_present, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.problems == [] and label.problems == [] and
      label.summary == all_present(truth.total)
  end

  def outcome?(context, :label_no_problem_dates, []) do
    label = read(context.label_page)
    placed?(label) and label.problems == [] and not Regex.match?(@date, label.description)
  end

  def outcome?(context, :label_counts_attention, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.problems != [] and
      label.summary == needs_attention(length(truth.problems), truth.total)
  end

  def outcome?(context, :label_lists_problems, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)
    placed?(label) and truth.problems != [] and label.problems == truth.problems
  end

  # The intact dates are counted as present: the total includes them, none is listed as a
  # problem, and the intact ones are what remains of the total.
  def outcome?(context, :label_counts_intact_present, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.intact > 0 and
      label.summary == needs_attention(length(truth.problems), truth.total) and
      label.problems == truth.problems and truth.total - length(label.problems) == truth.intact
  end

  def outcome?(context, :label_states_could_not_check, []) do
    label = read(context.label_page)
    placed?(label) and label.summary == @could_not_check and label.problems == []
  end

  def outcome?(context, :page_and_forms_usable, []) do
    page = context.label_page

    forms_usable?(page) and
      LazyHTML.text(LazyHTML.query(page, "h1")) == "Schedules & backups" and
      Enum.count(LazyHTML.query(page, @row)) > 0
  end

  def outcome?(context, :label_states_nothing_to_check, []) do
    label = read(context.label_page)
    placed?(label) and label.summary == @nothing_to_check and label.problems == []
  end

  def outcome?(context, :label_not_present, []) do
    label = read(context.label_page)

    placed?(label) and label.summary != @checking and
      not Regex.match?(~r/present/i, label.description) and
      not Regex.match?(@date, label.description)
  end

  def outcome?(context, :label_checking_then_result, []) do
    saving = read(context.label_after_save)
    result = read(context.label_settled_after_save)

    placed?(saving) and placed?(result) and saving.summary == @checking and
      result_state?(result.summary)
  end

  def outcome?(context, :label_one_needs_attention, []) do
    truth = BackupIntegrity.expected_label(context)
    result = read(context.label_settled_after_save)

    placed?(result) and length(truth.problems) == 1 and
      result.summary == needs_attention(1, truth.total) and result.problems == truth.problems
  end

  # Focus is a browser property: here, the page changes nowhere but in the label when the
  # result arrives, and the label holds nothing that could take or send focus.
  def outcome?(context, :focus_does_not_move, []) do
    result = read(context.label_settled_after_save)

    placed?(result) and focus_inert?(result) and
      without_labels(nodes(context.label_after_save)) ==
        without_labels(nodes(context.label_settled_after_save))
  end

  # The check ran (the missing artifact is named), so an unchanged destination is a measured
  # result and not the absence of a check.
  def outcome?(context, :rendered_destination_unchanged, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.problems != [] and label.problems == truth.problems and
      BackupIntegrity.outcome?(context, :destination_unchanged, [])
  end

  def outcome?(context, :label_private_free, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.problems != [] and label.problems == truth.problems and
      not BackupIntegrity.leaks_private_value?(context, label.html)
  end

  def outcome?(context, :label_matches_report, []) do
    label = read(context.label_page)

    placed?(label) and label.problems != [] and
      hd(context.task.lines) == "#{@term}: #{label.summary}" and
      tl(context.task.lines) == label.problems
  end

  def outcome?(context, :forms_usable_before_result, []) do
    first = read(context.label_first)
    placed?(first) and first.summary == @checking and forms_usable?(context.label_first)
  end

  # Nothing but the ceiling can end a read that never returns, so the result arrived no
  # earlier than the ceiling.
  def outcome?(context, :label_checking_until_ceiling, []) do
    first = read(context.label_first)
    ceiling = context.ceiling

    placed?(first) and first.summary == @checking and ceiling.blocked_pids != [] and
      ceiling.elapsed_ms >= @ceiling_ms
  end

  def outcome?(context, :label_could_not_check_at_ceiling, []) do
    label = read(context.label_page)

    placed?(label) and label.summary == @could_not_check and context.ceiling.blocked_pids != []
  end

  def outcome?(context, :check_cancelled_at_ceiling, []) do
    ceiling = context.ceiling

    ceiling.blocked_pids != [] and ceiling.all_down? and
      ceiling.reads_later == ceiling.reads_when_cancelled
  end

  # A visit by a denied visitor read nothing; the same probe sees an administrator's visit
  # read, so the empty count is a measurement.
  def outcome?(context, :no_reconciliation_started, []),
    do: context.denied_reads == 0 and context.control_reads > 0

  def outcome?(context, :label_reflows, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    match?({width, height} when width > 0 and height > 0, context[:viewport]) and
      placed?(label) and length(truth.problems) == 2 and label.problems == truth.problems and
      not truncating?(label.item)
  end

  def outcome?(context, :problem_lines_whole, []) do
    truth = BackupIntegrity.expected_label(context)
    label = read(context.label_page)

    placed?(label) and truth.problems != [] and label.problems == truth.problems and
      Enum.all?(label.problems, &(not String.contains?(&1, ["…", "..."]))) and
      not truncating?(label.item)
  end

  def outcome?(context, :problems_conveyed_by_text, []) do
    label = read(context.label_page)

    placed?(label) and label.problems != [] and
      Enum.all?(label.problems, &Regex.match?(@problem_line, &1)) and
      String.ends_with?(label.summary, "attention")
  end

  def outcome?(context, :label_announced_in_place, []) do
    label = read(context.label_page)

    placed?(label) and result_state?(label.summary) and polite?(label) and
      named_by_term?(context.label_page, label) and before_first_form?(context.label_page, label)
  end

  # Focus order is the order of the page's focusable elements; the label adds none and
  # takes none from the order.
  def outcome?(context, :focus_order_unchanged, []) do
    page = nodes(context.label_page)
    label = read(context.label_page)

    placed?(label) and focus_inert?(label) and focus_order(page) != [] and
      focus_order(page) == focus_order(without_labels(page))
  end

  def outcome?(context, :result_announced_politely, []) do
    first = read(context.label_first)
    result = read(context.label_page)

    placed?(first) and placed?(result) and first.summary == @checking and
      result_state?(result.summary) and polite?(first) and polite?(result) and
      same_region?(first.region, result.region) and focus_inert?(result) and
      without_labels(nodes(context.label_first)) == without_labels(nodes(context.label_page))
  end

  # ---------------------------------------------------------------------------------------
  # The copy of the plan's States and Real Copy table
  # ---------------------------------------------------------------------------------------

  defp all_present(1), do: "the retained backup is present"
  defp all_present(total), do: "all #{total} retained backups are present"

  defp needs_attention(1, 1), do: "the retained backup needs attention"
  defp needs_attention(1, total), do: "1 of #{total} retained backups needs attention"
  defp needs_attention(count, total), do: "#{count} of #{total} retained backups need attention"

  defp result_state?(summary),
    do:
      summary in [@could_not_check, @nothing_to_check] or
        (summary != @checking and Regex.match?(@result_summary, summary))

  defp placed?(nil), do: false
  defp placed?(label), do: label.in_place?

  # ---------------------------------------------------------------------------------------
  # Markup properties
  # ---------------------------------------------------------------------------------------

  defp polite?(label) do
    region = label.region

    region != nil and
      not Enum.any?(all([label.item]), fn node ->
        attribute(node, "role") == "alert" or attribute(node, "aria-live") == "assertive"
      end)
  end

  # The region is named by the term: it holds the term, or is labelled by it.
  defp named_by_term?(page, label) do
    region = label.region

    String.contains?(text(region), @term) or attribute(region, "aria-label") == @term or
      labelled_by_term?(nodes(page), attribute(region, "aria-labelledby"))
  end

  defp labelled_by_term?(_nodes, nil), do: false

  defp labelled_by_term?(nodes, ids) do
    wanted = String.split(ids)

    nodes
    |> all()
    |> Enum.filter(&(attribute(&1, "id") in wanted))
    |> Enum.map(&text/1)
    |> Enum.join(" ")
    |> Kernel.==(@term)
  end

  defp same_region?(first, result),
    do:
      first != nil and result != nil and
        {tag(first), attributes(first)} == {tag(result), attributes(result)}

  defp before_first_form?(page, label) do
    nodes = page |> nodes() |> all()
    term = Enum.find_index(nodes, &(&1 == label.item))
    form = Enum.find_index(nodes, &(tag(&1) == "form"))
    term != nil and form != nil and term < form
  end

  # The label holds no element that takes focus and nothing that sends it elsewhere.
  defp focus_inert?(label) do
    nodes = all([label.item])

    not Enum.any?(nodes, fn node ->
      focusable?(node) or attribute(node, "autofocus") != nil or
        Enum.any?(attributes(node), fn {name, value} ->
          String.starts_with?(name, "phx-") and String.contains?(value, "focus")
        end)
    end)
  end

  defp truncating?(item) do
    Enum.any?(all([item]), fn node ->
      classes = node |> attribute("class") |> to_string() |> String.split()

      tag(node) in @truncating_tags or Enum.any?(classes, &(&1 in @truncating_classes)) or
        Enum.any?(classes, &String.starts_with?(&1, ["w-[", "min-w-[", "max-w-["])) or
        Regex.match?(@truncating_style, to_string(attribute(node, "style")))
    end)
  end

  defp focus_order(nodes) do
    nodes
    |> all()
    |> Enum.filter(&focusable?/1)
    |> Enum.map(&{tag(&1), attribute(&1, "id") || attribute(&1, "name") || text(&1)})
  end

  defp focusable?(node) do
    cond do
      attribute(node, "disabled") != nil -> false
      tag(node) == "a" -> attribute(node, "href") != nil
      tag(node) == "input" -> attribute(node, "type") != "hidden"
      tag(node) in ~w(button select textarea summary) -> true
      true -> tabbable?(attribute(node, "tabindex"))
    end
  end

  defp tabbable?(nil), do: false

  defp tabbable?(value) do
    case Integer.parse(value) do
      {index, ""} -> index >= 0
      _other -> false
    end
  end

  # Every element that holds a `Backup files` term as a direct child, with everything inside it.
  defp without_labels(nodes) do
    nodes
    |> Enum.reject(fn
      {_tag, _attributes, children} -> Enum.any?(children, &term?/1)
      _text -> false
    end)
    |> Enum.map(fn
      {tag, attributes, children} -> {tag, attributes, without_labels(children)}
      other -> other
    end)
  end

  # ---------------------------------------------------------------------------------------
  # Trees
  # ---------------------------------------------------------------------------------------

  defp nodes(lazy), do: LazyHTML.to_tree(lazy)

  defp all(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &self_and_below/1)
  defp self_and_below({_tag, _attributes, children} = node), do: [node | all(children)]
  defp self_and_below(_text_or_comment), do: []

  defp children({_tag, _attributes, children}), do: children

  defp tag({tag, _attributes, _children}), do: tag
  defp attributes({_tag, attributes, _children}), do: attributes

  defp attribute({_tag, attributes, _children}, name) do
    Enum.find_value(attributes, fn
      {^name, value} -> value
      _other -> nil
    end)
  end

  defp decoration?(node), do: tag(node) == "svg" or attribute(node, "aria-hidden") == "true"

  # What a reader hears of a node: its text without decorative markers.
  defp plain_text(node), do: text(node, &decoration?/1)

  defp text(node_or_nodes, skip? \\ fn _node -> false end)

  defp text(nodes, skip?) when is_list(nodes),
    do: nodes |> Enum.map_join("", &raw_text(&1, skip?)) |> squeeze()

  defp text(node, skip?), do: node |> raw_text(skip?) |> squeeze()

  defp raw_text({_tag, _attributes, children} = node, skip?),
    do: if(skip?.(node), do: "", else: Enum.map_join(children, "", &raw_text(&1, skip?)))

  defp raw_text(text, _skip?) when is_binary(text), do: text
  defp raw_text(_comment, _skip?), do: ""

  defp squeeze(text), do: text |> String.split() |> Enum.join(" ")
end
