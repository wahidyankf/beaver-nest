defmodule BnestApp.TestInstance.RequestsTest do
  use ExUnit.Case, async: false

  require Phoenix.ChannelTest

  # Lets `--only test_instance` select this layer's tests.
  @moduletag :test_instance

  alias BnestApp.TestInstance.Requests
  alias Phoenix.Channel.Server, as: ChannelServer

  # `Phoenix.ChannelTest` runs its channels under the endpoint's own socket supervisors, as the browser's.
  @endpoint BnestAppWeb.Endpoint

  setup do
    Requests.attach!()
    assert Requests.in_flight() == 0
    :ok
  end

  # Phoenix's own logger listens to these events too, and detaches itself from metadata it does not understand.
  defp metadata(path), do: %{conn: %Plug.Conn{request_path: path}, options: []}

  # A request process as Phoenix runs it: it reports its start, waits, and reports how it ended.
  defp request(path, ending \\ :stop) do
    parent = self()

    pid =
      spawn(fn ->
        :telemetry.execute([:phoenix, :endpoint, :start], %{}, metadata(path))

        send(parent, {:started, self()})

        receive do
          :finish ->
            :telemetry.execute([:phoenix, :endpoint, ending], %{duration: 0}, metadata(path))
        end
      end)

    assert_receive {:started, ^pid}
    pid
  end

  defp finish(pid) do
    ref = Process.monitor(pid)
    send(pid, :finish)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  test "counts a request from its start to its stop" do
    pid = request("/chat")
    assert Requests.in_flight() == 1

    finish(pid)
    assert Requests.in_flight() == 0
  end

  test "an exception ends a request too" do
    pid = request("/chat", :exception)
    assert Requests.in_flight() == 1

    finish(pid)
    assert Requests.in_flight() == 0
  end

  test "does not count the testing-control routes" do
    pid = request("/__bnest_testing/v1/instances/abc")
    assert Requests.in_flight() == 0

    finish(pid)
  end

  test "forgets a request whose process died without reporting an end" do
    pid = request("/chat")
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}

    assert Requests.in_flight() == 0
  end

  test "attaching twice keeps one handler" do
    assert :ok = Requests.attach!()
    pid = request("/chat")

    assert Requests.in_flight() == 1
    finish(pid)
  end

  test "await_idle returns once the last request ends" do
    pid = request("/chat")
    task = Task.async(fn -> Requests.await_idle(2_000) end)

    finish(pid)

    assert Task.await(task) == :ok
  end

  test "await_idle gives up after the timeout while a request runs" do
    pid = request("/chat")

    assert Requests.await_idle(50) == {:error, :timeout}

    finish(pid)
  end

  # The GraphQL subscription socket as a browser holds it: connected with a session, and joined to Absinthe's
  # control channel. Its documents run in that channel's process, where no endpoint request reports them.
  #
  # `Phoenix.ChannelTest.subscribe_and_join/3` links the channel to the test and starts it outside the
  # endpoint's socket supervisors, which is not where a browser's channel lives. The join below uses the
  # endpoint's own starter, so the channel is supervised as a real one, and it ends with this test process,
  # the socket's transport.
  defp join_control_channel do
    session = %{"current_user" => %{"userId" => "test-user-socket-channel"}}

    {:ok, socket} =
      Phoenix.ChannelTest.connect(BnestAppWeb.UserSocket, %{}, connect_info: %{session: session})

    message = %Phoenix.Socket.Message{
      topic: "__absinthe__:control",
      event: "phx_join",
      payload: %{},
      ref: "1",
      join_ref: "1"
    }

    {:ok, _reply, channel} =
      ChannelServer.join(socket, Absinthe.Phoenix.Channel, message, [])

    channel
  end

  defp leave_channel(channel) do
    ref = Process.monitor(channel)
    GenServer.stop(channel)
    assert_receive {:DOWN, ^ref, :process, ^channel, _reason}
  end

  test "counts a GraphQL socket channel for as long as it lives" do
    channel = join_control_channel()
    assert Requests.in_flight() == 1

    leave_channel(channel)
    assert Requests.in_flight() == 0
  end

  test "await_idle gives up after the timeout while a GraphQL socket channel lives" do
    channel = join_control_channel()

    assert Requests.await_idle(50) == {:error, :timeout}

    leave_channel(channel)
    assert Requests.await_idle(50) == :ok
  end
end
