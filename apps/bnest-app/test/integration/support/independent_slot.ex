defmodule BnestApp.Test.IndependentSlot do
  @moduledoc false

  use Boundary, top_level?: true, check: [in: false, out: false]

  # A second application slot as production runs one beside the first: a separate OS
  # process with no distribution (`RELEASE_DISTRIBUTION=none`), running its own PubSub
  # server under the application's PubSub name, with a listener standing in for a socket
  # subscribed to the given topics. It is a `:peer` controlled over standard I/O, so the
  # two runtimes share no distribution at all; everything below `boot/1` runs in the peer.

  @pubsub BnestApp.PubSub
  @listener __MODULE__.Listener

  @doc "Starts the slot, subscribed to `topics`; its peer handle."
  @spec start!([String.t()]) :: pid()
  def start!(topics) do
    args = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    peer =
      case :peer.start(%{connection: :standard_io, args: args}) do
        {:ok, peer} -> peer
        {:ok, peer, _node} -> peer
      end

    :ok = :peer.call(peer, __MODULE__, :boot, [topics], 15_000)
    peer
  end

  @doc "Everything the slot's listener has received so far, oldest first."
  @spec received(pid()) :: [term()]
  def received(peer), do: :peer.call(peer, __MODULE__, :listener_received, [], 5_000)

  @doc """
  Broadcasts a control message on `topic` inside the slot itself and answers whether its
  listener received it: a listener that hears nothing from the other slot is shown live.
  """
  @spec hears_own_broadcast?(pid(), String.t()) :: boolean()
  def hears_own_broadcast?(peer, topic),
    do: :peer.call(peer, __MODULE__, :own_broadcast_heard?, [topic], 5_000)

  @doc "Stops the slot's runtime."
  @spec stop(pid()) :: :ok
  def stop(peer) do
    :peer.stop(peer)
  catch
    :exit, _already_stopped -> :ok
  end

  # --- in the peer ---

  @doc false
  def boot(topics) do
    {:ok, _apps} = Application.ensure_all_started(:phoenix_pubsub)
    booting = self()

    # Held by a process of its own: the call that boots the slot returns at once, and what
    # it linked would go with it.
    spawn(fn ->
      {:ok, _supervisor} =
        Supervisor.start_link([{Phoenix.PubSub, name: @pubsub}], strategy: :one_for_one)

      _listener = spawn_link(fn -> listen(topics, booting) end)
      Process.sleep(:infinity)
    end)

    receive do
      :listening -> :ok
    after
      10_000 -> {:error, :not_listening}
    end
  end

  @doc false
  def listener_received, do: ask_listener(:received)

  @doc false
  def own_broadcast_heard?(topic) do
    control = {:independent_slot_control, make_ref()}
    :ok = Phoenix.PubSub.broadcast(@pubsub, topic, control)
    wait_heard(control, 20)
  end

  defp wait_heard(_control, 0), do: false

  defp wait_heard(control, attempts) do
    if control in ask_listener(:received) do
      true
    else
      receive do
      after
        50 -> wait_heard(control, attempts - 1)
      end
    end
  end

  defp listen(topics, booting) do
    Process.register(self(), @listener)
    Enum.each(topics, &(:ok = Phoenix.PubSub.subscribe(@pubsub, &1)))
    send(booting, :listening)
    collect([])
  end

  defp collect(received) do
    receive do
      {:independent_slot_ask, :received, from, ref} ->
        send(from, {ref, Enum.reverse(received)})
        collect(received)

      message ->
        collect([message | received])
    end
  end

  defp ask_listener(question) do
    ref = make_ref()
    send(@listener, {:independent_slot_ask, question, self(), ref})

    receive do
      {^ref, answer} -> answer
    after
      5_000 -> raise "the independent slot's listener did not answer"
    end
  end
end
