defmodule BnestApp.Codex.PortSession do
  @moduledoc false

  @behaviour BnestApp.Codex.Session
  use GenServer

  @impl BnestApp.Codex.Session
  def open(owner, thread_id, model, reasoning_effort) do
    GenServer.start(__MODULE__, {owner, thread_id, model, reasoning_effort})
  end

  @impl BnestApp.Codex.Session
  def send_prompt(session, prompt) do
    GenServer.call(session, {:send_prompt, prompt})
  end

  @impl BnestApp.Codex.Session
  def close(session) do
    GenServer.stop(session, :normal)
  catch
    :exit, _reason -> :ok
  end

  @spec bundled_runner() :: String.t()
  def bundled_runner do
    Application.app_dir(:bnest_app, "priv/codex/chat_runner.mjs")
  end

  @impl GenServer
  def init({owner, thread_id, model, reasoning_effort}) do
    monitor = Process.monitor(owner)

    {:ok,
     %{
       owner: owner,
       monitor: monitor,
       port: open_port(thread_id, model, reasoning_effort)
     }}
  end

  @impl GenServer
  def handle_call({:send_prompt, prompt}, _from, state) do
    payload = Jason.encode!(%{type: "prompt", prompt: prompt}) <> "\n"
    {:reply, port_command(state.port, payload), state}
  end

  @impl GenServer
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    notify_owner(state.owner, line)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    send(
      state.owner,
      {:codex, self(), {:error, "Codex runner exited with status #{status}."}}
    )

    {:stop, :normal, %{state | port: nil}}
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{monitor: monitor, owner: owner} = state
      ) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, %{port: port}) when is_port(port) do
    Port.close(port)
  catch
    :error, :badarg -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp open_port(thread_id, model, reasoning_effort) do
    config = Application.fetch_env!(:bnest_app, :codex)

    runner =
      System.get_env("BNEST_CODEX_RUNNER") || Keyword.get(config, :runner, bundled_runner())

    working_directory = Keyword.fetch!(config, :working_directory)
    executable = System.find_executable("node") || raise "Node.js is required to run Codex"

    Port.open(
      {:spawn_executable, String.to_charlist(executable)},
      [
        :binary,
        :exit_status,
        {:line, 1_048_576},
        {:args,
         Enum.map(
           [
             runner,
             working_directory,
             model,
             reasoning_effort,
             thread_id || ""
           ],
           &String.to_charlist/1
         )},
        {:cd, String.to_charlist(working_directory)}
      ]
    )
  end

  defp port_command(port, payload) do
    Port.command(port, payload)
    :ok
  rescue
    ArgumentError -> {:error, :closed}
  end

  defp notify_owner(owner, line) do
    case Jason.decode(line) do
      {:ok, event} ->
        forward_runner_event(owner, event)

      {:error, _reason} ->
        send(owner, {:codex, self(), {:error, "Codex runner returned invalid data."}})
    end
  end

  defp forward_runner_event(owner, %{"type" => "thread_started", "thread_id" => thread_id}),
    do: send(owner, {:codex, self(), {:thread_started, thread_id}})

  defp forward_runner_event(owner, %{
         "type" => "assistant_update",
         "item_id" => item_id,
         "text" => text
       }),
       do: send(owner, {:codex, self(), {:assistant_update, item_id, text}})

  defp forward_runner_event(owner, %{"type" => "assistant_update", "text" => text}),
    do: send(owner, {:codex, self(), {:assistant_update, "assistant-message", text}})

  defp forward_runner_event(owner, %{
         "type" => "reasoning_update",
         "item_id" => item_id,
         "text" => text
       }),
       do: send(owner, {:codex, self(), {:reasoning_update, item_id, text}})

  defp forward_runner_event(owner, %{
         "type" => "activity_update",
         "item_id" => item_id,
         "text" => text
       }),
       do: send(owner, {:codex, self(), {:activity_update, item_id, text}})

  defp forward_runner_event(owner, %{"type" => "turn_completed"}),
    do: send(owner, {:codex, self(), :turn_completed})

  defp forward_runner_event(owner, %{"type" => "error", "message" => message}),
    do: send(owner, {:codex, self(), {:error, message}})

  defp forward_runner_event(owner, %{"type" => "resume_failed", "message" => message}),
    do: send(owner, {:codex, self(), {:resume_failed, message}})

  defp forward_runner_event(owner, _event),
    do: send(owner, {:codex, self(), {:error, "Codex runner returned invalid data."}})
end
