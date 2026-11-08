defmodule BnestAppWeb.TestingControl.GuardEndpointTest do
  # Every guard failure answers the stock not-found response a missing route gets, and changes
  # nothing (ADR 001, section 2, guards 1 to 5). Each refusal is sent through the real endpoint, and
  # is compared with the same request to a route that does not exist and with the state before it.
  use ExUnit.Case, async: false

  alias BnestApp.Test.TestingControlWire, as: Wire
  alias BnestApp.TestInstance

  @moduletag :testing_control

  @secret_env "BNEST_TEST_CONTROL_SECRET"
  @current_id "0123456789abcdef"
  @other_id "fedcba9876543210"
  @forwarded ~w(x-forwarded-for x-forwarded-host x-forwarded-proto forwarded x-real-ip)

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil
    secret = Wire.put_secret!()
    on_exit(&Wire.cleanup!/0)

    %{run: run, secret: secret}
  end

  describe "with no instance current" do
    test "a request with no secret header is refused as a missing route, in the JSON not-found body",
         ctx do
      refuse_every_route(ctx, headers: [accept()])

      refused = Wire.send_request(:get, Wire.prefix() <> "/state", nil, headers: [accept()])
      Wire.assert_json_not_found(refused)
    end

    test "a request with a wrong secret is refused as a missing route", ctx do
      wrong = String.duplicate("w", byte_size(ctx.secret))
      refuse_every_route(ctx, headers: [accept(), {"x-bnest-testing", wrong}])
    end

    test "a request with a secret of the wrong length is refused as a missing route", ctx do
      refuse_every_route(ctx, headers: [accept(), {"x-bnest-testing", "x"}])
    end

    test "a request that sends the right secret twice is refused as a missing route", ctx do
      refuse_every_route(ctx, headers: [accept(), secret_header(ctx), secret_header(ctx)])
    end

    test "a request that asks for HTML is refused before any content negotiation", ctx do
      refuse_every_route(ctx, headers: [{"accept", "text/html"}])
    end

    test "a request that came through a proxy is refused, with the right secret", ctx do
      for name <- @forwarded do
        refuse_every_route(ctx,
          headers: [accept(), secret_header(ctx), {name, "203.0.113.7"}],
          label: name
        )
      end
    end

    test "a request from a peer that is not loopback is refused, with the right secret", ctx do
      for peer <- [{10, 0, 0, 5}, {127, 0, 0, 2}, {0, 0, 0, 0, 0, 0, 0, 2}] do
        refuse_every_route(ctx,
          headers: [accept(), secret_header(ctx)],
          remote_ip: peer,
          label: inspect(peer)
        )
      end
    end

    test "a refused request is answered 404 whatever its body says" do
      body = %{"runId" => "not-this-run", "label" => "guarded"}
      refuse(:post, Wire.prefix() <> "/instances", body, headers: [accept()])
    end

    test "an unset secret closes every route, even to a request that carries a value", ctx do
      System.delete_env(@secret_env)
      refuse_every_route(ctx, headers: [accept(), secret_header(ctx)], label: "unset")
    end

    test "a secret shorter than 32 bytes closes every route, even to a request that matches it" do
      short = String.duplicate("s", 31)
      System.put_env(@secret_env, short)

      refuse_every_route(%{run: TestInstance.application_run!()},
        headers: [accept(), {"x-bnest-testing", short}],
        label: "short"
      )
    end

    test "an instance id outside the lowercase sixteen-character form is refused", ctx do
      for id <- ["ABCDEF0123456789", "short", "0123456789abcdef0", "0123456789ABCDEF"] do
        headers = [accept(), secret_header(ctx)]

        refuse(:delete, Wire.prefix() <> "/instances/#{id}", nil, headers: headers)

        refuse(:post, Wire.prefix() <> "/instances/#{id}/seed", seed_body(), headers: headers)
      end
    end

    test "a runtime the test run does not own closes every route", ctx do
      previous = Application.get_env(:bnest_app, :test_runtime_owned)
      Application.put_env(:bnest_app, :test_runtime_owned, false)
      on_exit(fn -> Application.put_env(:bnest_app, :test_runtime_owned, previous) end)

      refuse_every_route(ctx, headers: [accept(), secret_header(ctx)], label: "unowned")
    end
  end

  describe "with an instance current" do
    setup %{run: run} do
      TestInstance.spawn!(run, instance_id: @current_id)
      :ok
    end

    test "refused requests change neither the instance nor its database", ctx do
      before = Wire.snapshot()
      headers = [accept()]

      refuse(:delete, Wire.prefix() <> "/instances/#{@current_id}", nil, headers: headers)

      refuse(:post, Wire.prefix() <> "/instances/#{@current_id}/seed", seed_body(),
        headers: headers
      )

      refuse(:post, Wire.prefix() <> "/instances", %{"runId" => ctx.run.run_id, "label" => "x"},
        headers: headers
      )

      assert Wire.snapshot() == before
      assert TestInstance.state().instance_id == @current_id
    end

    test "a refused delete leaves the instance in place for a later, authorised delete" do
      wrong = {"x-bnest-testing", "wrong"}

      refuse(:delete, Wire.prefix() <> "/instances/#{@current_id}", nil,
        headers: [accept(), wrong]
      )

      assert TestInstance.state().instance_id == @current_id

      allowed = Wire.send_request(:delete, Wire.prefix() <> "/instances/#{@current_id}")
      assert allowed.status == 204
      assert TestInstance.state() == nil
    end

    test "a refused request for another id is answered as a missing route, not as not_current" do
      refuse(:delete, Wire.prefix() <> "/instances/#{@other_id}", nil,
        headers: [accept(), {"x-bnest-testing", "wrong"}]
      )
    end

    test "a request that passes every guard is answered by its route" do
      conn = Wire.send_request(:get, Wire.prefix() <> "/state")

      assert conn.status == 200
      assert %{"instance" => %{"instanceId" => @current_id}} = Wire.json(conn)
    end
  end

  # Helpers

  defp accept, do: {"accept", "application/json"}

  defp secret_header(%{secret: secret}), do: {"x-bnest-testing", secret}

  defp seed_body, do: %{"seedKey" => "admins", "seed" => %{"accounts" => []}}

  # Every testing-control route, with a body that is valid apart from the guard being tested.
  defp routes(run_id) do
    [
      {:get, Wire.prefix() <> "/state", nil},
      {:post, Wire.prefix() <> "/instances", %{"runId" => run_id, "label" => "guarded"}},
      {:post, Wire.prefix() <> "/instances/#{@current_id}/seed", seed_body()},
      {:delete, Wire.prefix() <> "/instances/#{@current_id}", nil}
    ]
  end

  defp refuse_every_route(ctx, opts) do
    {label, opts} = Keyword.pop(opts, :label, "refusal")

    for {method, path, body} <- routes(ctx.run.run_id) do
      refuse(method, path, body, Keyword.put(opts, :label, label))
    end
  end

  # One refused request: its answer is the missing route's answer, and the state does not move.
  defp refuse(method, path, body, opts) do
    {label, opts} = Keyword.pop(opts, :label, "refusal")
    before = Wire.snapshot()
    conn = Wire.send_request(method, path, body, opts)

    Wire.assert_not_found(conn, Wire.missing_route(method, body, opts))
    assert Wire.snapshot() == before, "#{label}: #{method} #{path} changed state"
  end
end
