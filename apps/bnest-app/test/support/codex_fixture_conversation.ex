defmodule BnestApp.Test.CodexFixtureConversation do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # How the fixture Codex answers a prompt where a unit or integration driver plays Codex
  # itself. It makes the checks `codex_fixture_runner.mjs` makes at E2E: each answer depends on
  # the session the prompt reached (the thread it resumed, its model and reasoning effort) and
  # on the prompts that conversation's thread already answered. A prompt that reached the wrong
  # conversation, or a session with the wrong settings, is answered with the runner's error
  # instead of a response.

  @type session :: %{
          thread_id: String.t() | nil,
          new_thread_id: String.t(),
          model: String.t(),
          reasoning_effort: String.t()
        }
  @type threads :: %{optional(String.t()) => [String.t()]}

  @expected_settings %{
    "After model switch" => {"gpt-5.6-luna", "high"},
    "After effort switch" => {"gpt-5.6-terra", "high"},
    "After reload" => {"gpt-5.6-luna", "high"},
    "Fresh start" => {"gpt-5.6-luna", "high"}
  }

  # The canned replies `codex_fixture_runner.mjs` sends, read from the same file so the two stay in step.
  @replies_path Path.expand("codex_fixture_replies.json", __DIR__)
  @external_resource @replies_path
  @replies @replies_path |> File.read!() |> Jason.decode!()

  @doc """
  The events the fixture Codex sends for `prompt` on `session`, and the threads' answered
  prompts afterwards. A fresh session's thread is its `new_thread_id`.
  """
  @spec answer(threads(), session(), String.t()) :: {[term()], threads()}
  def answer(threads, session, prompt) do
    thread = session.thread_id || session.new_thread_id
    history = Map.get(threads, thread, [])

    case refusal(prompt, history, session) do
      nil ->
        {events(thread, prompt), Map.put(threads, thread, history ++ [prompt])}

      message ->
        {[{:error, message}], threads}
    end
  end

  @doc """
  Splits a reply's events after its first assistant update: the part a streaming client shows
  first, and the rest of the reply. A stream the page holds half-written is the first part alone.
  """
  @spec split_first_part([term()]) :: {[term()], [term()]}
  def split_first_part(events) do
    index = Enum.find_index(events, &match?({:assistant_update, _item_id, _text}, &1))
    Enum.split(events, index + 1)
  end

  defp events(thread, prompt) do
    case Map.fetch(@replies, prompt) do
      {:ok, %{"prefix" => prefix, "text" => text}} ->
        [
          {:thread_started, thread},
          {:assistant_update, "fixture-reply", prefix},
          {:assistant_update, "fixture-reply", text},
          :turn_completed
        ]

      :error ->
        [
          {:thread_started, thread},
          {:assistant_update, "fixture-answer", "Fixture response"},
          {:assistant_update, "fixture-answer", "Fixture response complete."},
          :turn_completed
        ]
    end
  end

  # The runner's checks, in its order.
  defp refusal(prompt, history, session) do
    resumed? = not is_nil(session.thread_id)

    continuity_refusal(prompt, history) || reload_refusal(prompt, resumed?) ||
      settings_refusal(prompt, session) || thread_refusal(prompt, resumed?)
  end

  defp continuity_refusal("Remember me", history) do
    unless "Hello, Beaver Nest" in history, do: "Fixture conversation was not preserved."
  end

  defp continuity_refusal(_prompt, _history), do: nil

  defp reload_refusal("After reload", false), do: "Fixture Codex thread was not resumed."
  defp reload_refusal(_prompt, _resumed?), do: nil

  defp settings_refusal(prompt, session) do
    expected = Map.get(@expected_settings, prompt)

    unless expected in [nil, {session.model, session.reasoning_effort}],
      do: "Fixture selected model or effort was not applied."
  end

  defp thread_refusal(prompt, false) when prompt in ["After model switch", "After effort switch"],
    do: "Fixture runtime setting switch started a new Codex thread."

  defp thread_refusal("Fresh start", true), do: "Fixture Codex thread was not cleared."
  defp thread_refusal(_prompt, _resumed?), do: nil
end
