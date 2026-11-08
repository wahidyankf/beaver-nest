defmodule BnestApp.TestInstance.RequestsTest do
  use ExUnit.Case, async: false

  # Lets `--only test_instance` select this layer's tests.
  @moduletag :test_instance

  alias BnestApp.TestInstance.Requests

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
end
