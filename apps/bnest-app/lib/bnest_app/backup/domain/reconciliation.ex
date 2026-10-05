defmodule BnestApp.Backup.Domain.Reconciliation do
  @moduledoc """
  Whether the verified runs the ledger records still have their artifacts: each run is
  `:present` (the artifact is on disk with the recorded digest and size), `:missing` (no
  artifact), `:changed` (an artifact with other bytes), or `:not_expected`.

  A run is `:not_expected` when retention would legitimately have removed it: the run expected
  of each of the seven latest WIB dates is the newest verified run of that date, and every other
  run is superseded or older than the window. The grouping and the window are
  `BnestApp.Backup.Domain.Retention`'s, so the two cannot drift apart. A run is dated by its
  `finished_at`, the instant its receipt's `createdAt` carries, never by its slot: a slot of
  16:59 UTC retried at 17:01 UTC falls on the next WIB date. A run without a slot, such as the
  setup run of a new destination, is dated the same way.

  `report/1` and `render/1` are the one wording of a result. The log line, the telemetry
  metadata, the Mix task and the Schedules page label all render these parts, so no surface
  holds a second copy of the words. A report names a run by its WIB date and state only: it
  carries no path, digest, destination identifier or run ID, and an empty set of expected
  runs is never reported as present.

  Pure: the artifacts are what the caller read from the destination.
  """

  alias BnestApp.Backup.Domain.Retention

  @typedoc "A verified ledger run: its slot (`nil` for a setup run), finish and recorded artifact."
  @type run :: %{
          required(:run_id) => String.t(),
          required(:slot) => DateTime.t() | nil,
          required(:finished_at) => DateTime.t(),
          required(:artifact_basename) => String.t(),
          required(:artifact_sha256) => String.t(),
          required(:artifact_bytes) => non_neg_integer(),
          optional(atom()) => term()
        }

  @typedoc "What reading an artifact of the destination reported: its digest and size."
  @type artifact :: %{sha256: String.t(), bytes: non_neg_integer()}

  @type state :: :present | :missing | :changed | :not_expected

  @typedoc "One run's outcome: the WIB date it is reported on, its slot, artifact name and state."
  @type result :: %{
          date: Date.t(),
          slot: DateTime.t() | nil,
          artifact_basename: String.t(),
          state: state()
        }

  @typedoc """
  What a surface shows: the check is running (`:checking`, the page only), it finished with
  each run's result, or it could not be made, for whatever reason.
  """
  @type outcome :: :checking | {:ok, [result()]} | {:error, term()}

  @typedoc """
  The words of an outcome, in parts: the `label`, the `summary` that follows it, one line per
  problem run, an optional `footer`, and the exit status of a task that reports it, zero only
  when at least one backup is expected and every one is present.

  A check that could not be made also carries what each reader is told to do about it, for
  none of them can do what the other can: the `remedy` is addressed to the operator at the
  host, in the line the log and the Mix task print, and the `hint` to the reader of the
  Schedules page, who has no host to run a command on. Both are `nil` for every other outcome.
  """
  @type report :: %{
          label: String.t(),
          summary: String.t(),
          problems: [String.t()],
          footer: String.t() | nil,
          remedy: String.t() | nil,
          hint: String.t() | nil,
          exit_status: 0 | 1
        }

  @label "Backup files"
  @could_not_check "could not be checked."
  @remedy "Run mix bnest.backup.reconcile on the host."
  @hint "Reload this page to try again."

  @doc """
  The runs retention keeps a backup for: the newest run of each of the seven latest WIB dates
  that hold a run, latest date first.
  """
  @spec expected([run()]) :: [run()]
  def expected(runs) do
    runs
    |> Enum.sort_by(&age/1, :desc)
    |> Retention.retained_groups(& &1.finished_at)
    |> Enum.map(fn {_date, [newest | _older]} -> newest end)
  end

  @doc """
  Every run with its outcome, oldest first. `artifacts` holds, by basename, what was read of
  each expected run's artifact that exists; a run absent from it is `:missing`.
  """
  @spec classify([run()], %{optional(String.t()) => artifact()}) :: [result()]
  def classify(runs, artifacts) do
    expected_ids = runs |> expected() |> MapSet.new(& &1.run_id)

    runs
    |> Enum.sort_by(&age/1)
    |> Enum.map(fn run ->
      %{
        date: Retention.wib_date(run.finished_at),
        slot: run.slot,
        artifact_basename: run.artifact_basename,
        state: state(run, expected_ids, artifacts)
      }
    end)
  end

  @doc """
  The words of an `outcome`. Only the runs expected of a retained date are counted, so a run
  retention legitimately removed never appears; a reason an outcome could not be checked is
  never shown, because it may name a path. The remedy and the hint are fixed words, never built
  from the reason.
  """
  @spec report(outcome()) :: report()
  def report(:checking), do: parts("checking", [], 1)

  def report({:error, _reason}),
    do: %{parts(@could_not_check, [], 1) | remedy: @remedy, hint: @hint}

  def report({:ok, results}) do
    expected = Enum.reject(results, &(&1.state == :not_expected))
    problems = expected |> Enum.filter(&(&1.state in [:missing, :changed])) |> sort_by_date()

    case {length(expected), length(problems)} do
      {0, 0} -> parts("no verified backup to check yet", [], 1)
      {total, 0} -> parts(present_summary(total), [], 0)
      {total, count} -> parts(attention_summary(count, total), problem_lines(problems), 1)
    end
  end

  @doc """
  The lines a surface prints for a report: `Backup files: <summary>`, followed after a space by
  the remedy when the report has one, then the problems and the footer. The hint is the page's
  alone and is never printed here.
  """
  @spec render(report()) :: [String.t()]
  def render(report),
    do: [first_line(report) | report.problems] ++ List.wrap(report.footer)

  defp first_line(%{remedy: nil} = report), do: "#{report.label}: #{report.summary}"
  defp first_line(report), do: "#{report.label}: #{report.summary} #{report.remedy}"

  defp age(run), do: {DateTime.to_unix(run.finished_at), run.run_id}

  defp state(run, expected_ids, artifacts) do
    if MapSet.member?(expected_ids, run.run_id),
      do: observed_state(run, Map.fetch(artifacts, run.artifact_basename)),
      else: :not_expected
  end

  defp observed_state(_run, :error), do: :missing

  defp observed_state(run, {:ok, artifact}) do
    if artifact.sha256 == run.artifact_sha256 and artifact.bytes == run.artifact_bytes,
      do: :present,
      else: :changed
  end

  defp parts(summary, problems, exit_status),
    do: %{
      label: @label,
      summary: summary,
      problems: problems,
      footer: nil,
      remedy: nil,
      hint: nil,
      exit_status: exit_status
    }

  defp present_summary(1), do: "the retained backup is present"
  defp present_summary(total), do: "all #{total} retained backups are present"

  defp attention_summary(1, 1), do: "the retained backup needs attention"
  defp attention_summary(1, total), do: "1 of #{total} retained backups needs attention"
  defp attention_summary(count, total), do: "#{count} of #{total} retained backups need attention"

  defp sort_by_date(results), do: Enum.sort_by(results, & &1.date, Date)

  defp problem_lines(problems),
    do: Enum.map(problems, &"#{Date.to_iso8601(&1.date)}: file #{&1.state}")
end
