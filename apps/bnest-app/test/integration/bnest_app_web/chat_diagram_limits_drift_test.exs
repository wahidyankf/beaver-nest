defmodule BnestAppWeb.ChatDiagramLimitsDriftTest do
  @moduledoc """
  ADR 004, Decisions 2 and 3: the server (`ChatMarkdown.diagram_limits/0`) is the authority for the diagram caps
  and the allowed diagram types, and the browser keeps a copy in `assets/js/diagrams/diagram_limits.js`. This test
  reads that file as text and fails when the two copies differ, so a change to one side cannot reach production
  without the other.
  """
  use ExUnit.Case, async: true

  alias BnestAppWeb.ChatMarkdown

  @browser_limits Path.expand("../../../assets/js/diagrams/diagram_limits.js", __DIR__)

  setup_all do
    %{source: File.read!(@browser_limits)}
  end

  test "the browser's source-size cap equals the server's", %{source: source} do
    assert browser_number(source, "maxSourceBytes") ==
             ChatMarkdown.diagram_limits().max_source_bytes
  end

  test "the browser's line cap equals the server's", %{source: source} do
    assert browser_number(source, "maxLines") == ChatMarkdown.diagram_limits().max_lines
  end

  test "the browser's per-message cap equals the server's", %{source: source} do
    assert browser_number(source, "maxPerMessage") ==
             ChatMarkdown.diagram_limits().max_per_message
  end

  test "the browser allows exactly the diagram types the server allows", %{source: source} do
    assert browser_kinds(source) == Enum.sort(ChatMarkdown.diagram_limits().kinds)
  end

  # The words and the tokens a diagram may not contain. Both sides build their word pattern from these lists, so
  # equal lists mean the same refusals; the drift test compares the lists the code really uses, not the numbers.
  test "the browser refuses the same words and tokens as the server", %{source: source} do
    limits = ChatMarkdown.diagram_limits()

    assert browser_strings(source, "NOT_ALLOWED_WORDS") == Enum.sort(limits.not_allowed_words)
    assert browser_strings(source, "NOT_ALLOWED_TOKENS") == Enum.sort(limits.not_allowed_tokens)
  end

  # The strings of an exported array of string literals, read from the source text.
  defp browser_strings(source, name) do
    [_, block] =
      Regex.run(~r/export const #{name} = Object\.freeze\(\[(.*?)\]\);/su, source) ||
        flunk("diagram_limits.js does not export #{name} as an array of strings")

    ~r/"((?:[^"\\]|\\.)*)"/u
    |> Regex.scan(block, capture: :all_but_first)
    |> List.flatten()
    |> Enum.sort()
  end

  # `name: 1234,` inside the exported LIMITS object, read as a number.
  defp browser_number(source, name) do
    case Regex.run(~r/^\s*#{name}:\s*(\d+),?\s*$/mu, source) do
      [_, digits] -> String.to_integer(digits)
      nil -> flunk("diagram_limits.js does not set #{name} as a plain number")
    end
  end

  # The keys of the exported KINDS object, read as the type words. A key is a bare word or a quoted word.
  defp browser_kinds(source) do
    [_, block] = Regex.run(~r/export const KINDS = Object\.freeze\(\{(.*?)\}\);/su, source)

    ~r/^\s*"?([A-Za-z][A-Za-z0-9-]*)"?:\s*"/mu
    |> Regex.scan(block, capture: :all_but_first)
    |> List.flatten()
    |> Enum.sort()
  end
end
