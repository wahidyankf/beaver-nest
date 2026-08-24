defmodule BnestApp.Codex.PortSession do
  @moduledoc false

  @behaviour BnestApp.Codex.Session
  use GenServer

  alias BnestApp.Codex.Settings

  @impl BnestApp.Codex.Session
  def open(owner), do: GenServer.start(__MODULE__, owner)

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

  @impl GenServer
  def init(owner) do
    monitor = Process.monitor(owner)
    {:ok, %{owner: owner, monitor: monitor, port: open_port()}}
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
    send(state.owner, {:codex, {:error, "Codex runner exited with status #{status}."}})
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

  defp open_port do
    config = Application.fetch_env!(:bnest_app, :codex)
    runner = System.get_env("BNEST_CODEX_RUNNER") || Keyword.fetch!(config, :runner)
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
           [runner, working_directory, Settings.model(), Settings.reasoning_effort()],
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
      {:ok, %{"type" => "assistant_update", "text" => text}} ->
        send(owner, {:codex, {:assistant_update, text}})

      {:ok, %{"type" => "turn_completed"}} ->
        send(owner, {:codex, :turn_completed})

      {:ok, %{"type" => "error", "message" => message}} ->
        send(owner, {:codex, {:error, message}})

      {:error, _reason} ->
        send(owner, {:codex, {:error, "Codex runner returned invalid data."}})
    end
  end
end
