defmodule BnestAppWeb.TestingControl.LifecycleTest do
  # The testing-control routes answer their records and their error codes through the real endpoint
  # (ADR 001, section 2). Every account, password and key below is synthetic.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest

  alias BnestApp.Storage.Adapters.FileConfigStore
  alias BnestApp.Test.TestingControlWire, as: Wire
  alias BnestApp.TestInstance

  @endpoint BnestAppWeb.Endpoint
  @moduletag :testing_control
  @hex16 ~r/\A[a-z0-9]{16}\z/

  setup do
    run = TestInstance.application_run!()
    assert TestInstance.state() == nil
    secret = Wire.put_secret!()
    on_exit(&Wire.cleanup!/0)

    %{run: run, secret: secret}
  end

  describe "GET /state" do
    test "reports no instance before any spawn, with the run id", %{run: run} do
      conn = Wire.send_request(:get, route("/state"))

      assert conn.status == 200

      assert Wire.json(conn) == %{
               "schemaVersion" => 1,
               "runId" => run.run_id,
               "instance" => nil
             }
    end
  end

  describe "POST /instances" do
    test "spawns an empty sqlite_primary instance and answers its record", %{run: run} do
      conn = spawn_instance(run, %{"label" => "fresh-db"})

      assert conn.status == 201
      body = Wire.json(conn)
      id = body["instanceId"]

      assert id =~ @hex16
      assert body["label"] == "fresh-db"
      assert body["phase"] == "sqlite_primary"
      assert body["generation"] == "test-" <> id
      assert body["accounts"] == []

      assert body["environment"] == %{
               "BNEST_TEST_INSTANCE_ID" => id,
               "BNEST_RUNTIME_ROOT" => run.path,
               "BNEST_STORAGE_CONFIG" => FileConfigStore.pointer_path()
             }

      assert TestInstance.state().instance_id == id
    end

    test "the state route then describes the current instance", %{run: run} do
      id =
        spawn_instance(run, %{"label" => "described"}) |> Wire.json() |> Map.fetch!("instanceId")

      instance = Wire.json(Wire.send_request(:get, route("/state")))["instance"]

      assert %{
               "instanceId" => ^id,
               "label" => "described",
               "phase" => "sqlite_primary",
               "generation" => generation,
               "createdAt" => created_at
             } = instance

      assert generation == "test-" <> id
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(created_at)
    end

    test "a flat_primary spawn names its own flat instance root as the runtime root", %{run: run} do
      body = spawn_instance(run, %{"phase" => "flat_primary"}) |> Wire.json()
      id = body["instanceId"]

      assert body["phase"] == "flat_primary"

      assert body["environment"]["BNEST_RUNTIME_ROOT"] ==
               Path.join([run.path, "instances", id])
    end

    test "an unconfigured flat_primary spawn leaves no storage pointer for the setup page", %{
      run: run
    } do
      body =
        spawn_instance(run, %{"phase" => "flat_primary", "storage" => "unconfigured"})
        |> Wire.json()

      assert body["phase"] == "flat_primary"
      refute File.exists?(FileConfigStore.pointer_path())
      assert TestInstance.state().storage == :unconfigured
    end

    test "an unconfigured sqlite_primary spawn is a bad request and changes nothing", %{run: run} do
      conn = spawn_instance(run, %{"storage" => "unconfigured"})

      assert conn.status == 400
      assert TestInstance.state() == nil
      refute File.exists?(FileConfigStore.pointer_path())
    end

    test "a spawn seed naming an account is refused: the username cannot carry an id the client lacks",
         %{run: run} do
      before = Wire.snapshot()

      seed = %{
        "accounts" => [
          %{
            "username" => "test-user-0123abcd-admin",
            "password" => Wire.password(),
            "roles" => ["admin"]
          }
        ]
      }

      conn = spawn_instance(run, %{"seed" => seed})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "invalid_username",
               "path" => "accounts[0].username"
             }

      assert Wire.snapshot() == before
    end

    test "a client-chosen instance id becomes the spawned instance's id and generation", %{
      run: run
    } do
      id = random_id()

      conn = spawn_instance(run, %{"instanceId" => id})

      assert conn.status == 201
      body = Wire.json(conn)
      assert body["instanceId"] == id
      assert body["generation"] == "test-" <> id
      assert TestInstance.state().instance_id == id
    end

    test "seed accounts for a client-chosen id carry its short id, and the answer lists exactly them",
         %{run: run} do
      id = random_id()
      short = String.slice(id, 0, 8)

      conn = spawn_instance(run, %{"instanceId" => id, "seed" => Wire.account_seed(id)})

      assert conn.status == 201
      body = Wire.json(conn)
      assert body["instanceId"] == id

      {admin, parent} = Wire.usernames(id)
      assert Enum.map(body["accounts"], & &1["username"]) == [admin, parent]

      for account <- body["accounts"] do
        assert String.starts_with?(account["username"], "test-user-")
        assert short in String.split(account["username"], "-")
      end
    end

    test "an instance id that is not 16 lowercase letters or digits answers 400 and changes nothing",
         %{run: run} do
      before = Wire.snapshot()

      for id <- ["0123456789ABCDEF", "short", "0123456789abcdef0", 42] do
        conn = spawn_instance(run, %{"instanceId" => id})

        assert conn.status == 400

        assert error(conn) == %{
                 "code" => "invalid_request",
                 "detail" => "the instance id must be 16 lowercase letters or digits",
                 "path" => nil
               }
      end

      assert Wire.snapshot() == before
    end

    test "an instance id whose directories already exist answers 409 instance_active and changes nothing",
         %{run: run} do
      id = random_id()
      leftover = Path.join([run.sqlite_path, "instances", id])
      File.mkdir_p!(leftover)
      on_exit(fn -> File.rm_rf!(leftover) end)
      before = Wire.snapshot()

      conn = spawn_instance(run, %{"instanceId" => id})

      assert conn.status == 409

      assert error(conn) == %{
               "code" => "instance_active",
               "detail" => "an instance with that id already exists",
               "path" => nil
             }

      assert File.dir?(leftover)
      assert Wire.snapshot() == before
    end

    test "a spawn seed of a system message is applied before the spawn answers", %{run: run} do
      seed = %{
        "familyChat" => %{
          "messages" => [
            %{"sender" => "system", "body" => "Doa malam", "idempotencyKey" => "slot-1"}
          ]
        }
      }

      conn = spawn_instance(run, %{"seed" => seed})

      assert conn.status == 201
      assert TestInstance.state().instance_id == Wire.json(conn)["instanceId"]
    end

    test "a spawn seed that fails validation answers 422 and leaves nothing behind", %{run: run} do
      before = Wire.snapshot()

      seed = %{
        "familyChat" => %{
          "messages" => [
            %{"sender" => "test-user-ghost", "body" => "Salam", "idempotencyKey" => "k1"}
          ]
        }
      }

      conn = spawn_instance(run, %{"seed" => seed})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "unknown_sender",
               "path" => "familyChat.messages[0].sender"
             }

      assert Wire.snapshot() == before
    end

    test "a second spawn while an instance is current answers 409 instance_active and changes nothing",
         %{run: run} do
      spawn_instance(run, %{})
      before = Wire.snapshot()

      conn = spawn_instance(run, %{})

      assert conn.status == 409
      assert error(conn)["code"] == "instance_active"
      assert Wire.snapshot() == before
    end

    test "a refused lifecycle request logs its cause", %{run: run} do
      spawn_instance(run, %{})

      log = capture_log([level: :warning], fn -> spawn_instance(run, %{}) end)

      assert log =~ "testing control refused a lifecycle request"
      assert log =~ "instance_active"
    end

    test "a spawn that cannot take the switch lock answers 409 instance_active", %{run: run} do
      before = Wire.snapshot()
      parent = self()

      # The switch lock is held by another process, which stands for a concurrent spawn.
      holder =
        Task.async(fn ->
          :global.trans(
            {{TestInstance, :lock}, self()},
            fn ->
              send(parent, :lock_held)

              receive do
                :release -> :ok
              end
            end,
            [node()],
            0
          )
        end)

      assert_receive :lock_held

      try do
        conn = spawn_instance(run, %{})

        assert conn.status == 409
        assert error(conn)["code"] == "instance_active"
        assert Wire.snapshot() == before
      after
        send(holder.pid, :release)
      end

      assert Task.await(holder) == :ok
    end

    test "a spawn while a scheduler task runs answers 409 instance_busy and creates nothing",
         %{run: run} do
      before = Wire.snapshot()
      {:ok, task} = start_blocking_scheduler_task()

      try do
        conn = spawn_instance(run, %{})

        assert conn.status == 409
        assert error(conn)["code"] == "instance_busy"
        assert Wire.snapshot() == before
      after
        finish_blocking_scheduler_task(task)
      end
    end

    test "a run id that is not this run answers 409 run_mismatch and changes nothing", %{run: run} do
      before = Wire.snapshot()

      conn = spawn_instance(%{run | run_id: run.run_id <> "-other"}, %{})

      assert conn.status == 409
      assert error(conn)["code"] == "run_mismatch"
      assert Wire.snapshot() == before
    end

    for step <- [:create, :activate, :migrate, :seed] do
      test "a spawn that fails at #{step} answers 500 spawn_failed with that step, and is undone",
           %{run: run} do
        before = Wire.snapshot()
        Application.put_env(:bnest_app, :testing_control_fail_after, unquote(step))

        conn = spawn_instance(run, %{})

        assert conn.status == 500

        assert error(conn) == %{
                 "code" => "spawn_failed",
                 "detail" => error(conn)["detail"],
                 "path" => nil,
                 "step" => unquote(to_string(step))
               }

        refute Map.has_key?(Wire.json(conn), "instanceId")
        assert TestInstance.state() == nil
        assert Wire.snapshot() == before
      end
    end
  end

  describe "POST /instances/:id/seed" do
    test "applies a seed to the current instance, and answers a repeated key as not applied",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")

      first = seed_instance(id, "admins", Wire.account_seed(id))
      assert first.status == 200
      assert Wire.json(first) == %{"seedKey" => "admins", "applied" => true}

      again = seed_instance(id, "admins", Wire.account_seed(id))
      assert Wire.json(again) == %{"seedKey" => "admins", "applied" => false}
    end

    test "the seeded admin and parent log in through the production login path", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      assert seed_instance(id, "admins", Wire.account_seed(id)).status == 200

      {admin, parent} = Wire.usernames(id)

      for username <- [admin, parent] do
        conn =
          build_conn()
          |> post("/login", %{"login" => %{"username" => username, "password" => Wire.password()}})

        assert redirected_to(conn) == "/"
        assert conn.resp_cookies["_bnest_identity"]
      end
    end

    test "a seed key used with another body answers 409 seed_conflict and changes nothing",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      assert seed_instance(id, "admins", Wire.account_seed(id)).status == 200
      before = Wire.snapshot()

      other = %{
        "familyChat" => %{
          "messages" => [%{"sender" => "system", "body" => "Lain", "idempotencyKey" => "s9"}]
        }
      }

      conn = seed_instance(id, "admins", other)

      assert conn.status == 409
      assert error(conn)["code"] == "seed_conflict"
      assert Wire.snapshot() == before
    end

    test "a seed key outside the key form answers 422 unknown_seed_key at seedKey", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      before = Wire.snapshot()

      conn = seed_instance(id, "Admins Key", %{})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "unknown_seed_key",
               "path" => "seedKey"
             }

      assert Wire.snapshot() == before
    end

    test "a seed for an id that is not the current instance answers 409 not_current", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      other = if id == "0123456789abcdef", do: "fedcba9876543210", else: "0123456789abcdef"
      before = Wire.snapshot()

      conn = seed_instance(other, "admins", %{})

      assert conn.status == 409
      assert error(conn)["code"] == "not_current"
      assert Wire.snapshot() == before
    end

    test "a seed route with no seed body answers 400 invalid_request", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")

      conn = Wire.send_request(:post, route("/instances/#{id}/seed"), %{"seedKey" => "admins"})

      assert conn.status == 400
      assert error(conn)["code"] == "invalid_request"
    end

    test "a seed with an invalid username answers 422 invalid_username and writes nothing", %{
      run: run
    } do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      before = Wire.snapshot()

      account = %{
        "username" => "test-user-zz",
        "password" => Wire.password(),
        "roles" => ["parents"]
      }

      conn = seed_instance(id, "bad-name", %{"accounts" => [account]})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "invalid_username",
               "path" => "accounts[0].username"
             }

      assert Wire.snapshot() == before
    end

    test "a seed with an unknown role answers 422 invalid_role at the account's roles", %{
      run: run
    } do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      {admin, _parent} = Wire.usernames(id)
      before = Wire.snapshot()
      account = %{"username" => admin, "password" => Wire.password(), "roles" => ["wizard"]}

      conn = seed_instance(id, "bad-role", %{"accounts" => [account]})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "invalid_role",
               "path" => "accounts[0].roles"
             }

      assert Wire.snapshot() == before
    end

    test "a seed with a duplicate username answers 422 duplicate_username at the second account",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      {admin, _parent} = Wire.usernames(id)
      account = %{"username" => admin, "password" => Wire.password(), "roles" => ["parents"]}

      conn = seed_instance(id, "dupes", %{"accounts" => [account, account]})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "duplicate_username",
               "path" => "accounts[1].username"
             }
    end

    test "a seed with a sender nobody seeded answers 422 unknown_sender", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      {_admin, parent} = Wire.usernames(id)
      ghost = String.replace(parent, "parent", "ghost")

      seed = %{
        "familyChat" => %{
          "messages" => [%{"sender" => ghost, "body" => "Salam", "idempotencyKey" => "k1"}]
        }
      }

      conn = seed_instance(id, "chat", seed)

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "unknown_sender",
               "path" => "familyChat.messages[0].sender"
             }
    end

    test "a seed with a push owner nobody seeded answers 422 unknown_owner", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")

      seed = %{
        "pushSubscriptions" => [
          %{
            "owner" => "test-user-ghost",
            "endpoint" => "https://push.allowed.example.com/one",
            "p256dh" => "BBBB",
            "auth" => "AAAA"
          }
        ]
      }

      conn = seed_instance(id, "push", seed)

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "unknown_owner",
               "path" => "pushSubscriptions[0].owner"
             }
    end

    test "a seed with more accounts than the limit answers 422 too_many", %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      short = String.slice(id, 0, 8)

      accounts =
        for n <- 1..41 do
          %{
            "username" => "test-user-#{short}-n#{n}",
            "password" => Wire.password(),
            "roles" => ["parents"]
          }
        end

      conn = seed_instance(id, "many", %{"accounts" => accounts})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "too_many",
               "path" => "accounts"
             }
    end

    test "a seed with a key outside the seed schema answers 422 invalid_payload, without echoing the key",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")

      conn = seed_instance(id, "bogus", %{"Synthetic!Pass1Key" => []})

      assert conn.status == 422

      assert error(conn) == %{
               "code" => "seed_invalid",
               "detail" => "invalid_payload",
               "path" => "unknown"
             }

      refute conn.resp_body =~ "Synthetic!Pass1Key"
    end
  end

  describe "DELETE /instances/:id" do
    test "deletes the current instance with 204, and a second delete answers 409 not_current",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")

      first = Wire.send_request(:delete, route("/instances/#{id}"))
      assert first.status == 204
      assert first.resp_body == ""
      assert TestInstance.state() == nil

      second = Wire.send_request(:delete, route("/instances/#{id}"))
      assert second.status == 409
      assert error(second)["code"] == "not_current"
    end

    test "a delete while a scheduler task runs answers 409 instance_busy, and a later delete succeeds",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      {:ok, task} = start_blocking_scheduler_task()

      try do
        conn = Wire.send_request(:delete, route("/instances/#{id}"))

        assert conn.status == 409
        assert error(conn)["code"] == "instance_busy"
        assert TestInstance.state().instance_id == id
      after
        finish_blocking_scheduler_task(task)
      end

      assert Wire.send_request(:delete, route("/instances/#{id}")).status == 204
    end

    test "a delete that cannot remove the instance answers 500 cleanup_failed with its path, and a later delete succeeds",
         %{run: run} do
      id = spawn_instance(run, %{}) |> Wire.json() |> Map.fetch!("instanceId")
      instance = TestInstance.state()
      marker = Path.join(instance.paths.sqlite_instance_root, ".bnest-test-instance.json")
      original = File.read!(marker)
      File.write!(marker, "not a marker")

      try do
        conn = Wire.send_request(:delete, route("/instances/#{id}"))

        assert conn.status == 500
        assert error(conn)["code"] == "cleanup_failed"
        assert error(conn)["path"] == instance.paths.sqlite_instance_root
        assert String.starts_with?(error(conn)["path"], run.sqlite_path <> "/")
        assert TestInstance.state().instance_id == id
      after
        File.write!(marker, original)
      end

      assert Wire.send_request(:delete, route("/instances/#{id}")).status == 204
    end
  end

  describe "request bodies" do
    test "a body that is not declared as JSON answers 400 invalid_request", %{run: run} do
      conn =
        Wire.send_request(:post, route("/instances"), ~s({"runId":"#{run.run_id}","label":"x"}),
          headers: Wire.default_headers() ++ [{"content-type", "text/plain"}]
        )

      assert conn.status == 400

      assert error(conn) == %{
               "code" => "invalid_request",
               "detail" => "the content type must be application/json",
               "path" => nil
             }

      assert TestInstance.state() == nil
    end

    test "an unknown top-level field answers 400 invalid_request", %{run: run} do
      conn = spawn_instance(run, %{"owner" => "test-user-0123abcd"})

      assert conn.status == 400
      assert error(conn)["code"] == "invalid_request"
      assert TestInstance.state() == nil
    end

    test "a body over 256 KiB answers 400 by its content length", %{run: run} do
      body = %{
        "runId" => run.run_id,
        "label" => "big",
        "seed" => %{
          "familyChat" => %{
            "messages" => [
              %{
                "sender" => "system",
                "body" => String.duplicate("a", 270_000),
                "idempotencyKey" => "big"
              }
            ]
          }
        }
      }

      encoded = Jason.encode!(body)

      conn =
        Wire.send_request(:post, route("/instances"), encoded,
          headers:
            Wire.default_headers() ++
              [
                {"content-type", "application/json"},
                {"content-length", Integer.to_string(byte_size(encoded))}
              ]
        )

      assert conn.status == 400

      assert error(conn) == %{
               "code" => "invalid_request",
               "detail" => "the body is larger than 256 KiB",
               "path" => nil
             }

      assert TestInstance.state() == nil
    end

    test "a malformed JSON body gets the endpoint's own 400, the one a missing route gets", %{
      run: _run
    } do
      headers = Wire.default_headers() ++ [{"content-type", "application/json"}]
      conn = Wire.send_request(:post, route("/instances"), "{not json", headers: headers)

      assert conn.status == 400
      refute conn.resp_body =~ "invalid_request"
      assert Wire.summary(conn) == Wire.missing_route(:post, "{not json", headers: headers)
    end

    test "a label that is not a slug answers 400, and so does an unknown phase", %{run: run} do
      conn = spawn_instance(run, %{"label" => "Fresh Label"})
      assert conn.status == 400
      assert error(conn)["code"] == "invalid_request"

      conn = spawn_instance(run, %{"phase" => "sqlite"})
      assert conn.status == 400
      assert error(conn)["code"] == "invalid_request"
      assert TestInstance.state() == nil
    end
  end

  describe "answers and logs" do
    test "no answer or log line carries the secret or a password, and every path is inside the run",
         %{run: run, secret: secret} do
      previous_level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous_level) end)

      {bodies, logs} =
        capture_log_with_bodies(fn ->
          created = spawn_instance(run, %{"label" => "clean"})
          id = Wire.json(created) |> Map.fetch!("instanceId")

          [
            created,
            Wire.send_request(:get, route("/state")),
            seed_instance(id, "admins", Wire.account_seed(id)),
            seed_instance(id, "admins", %{"accounts" => []}),
            seed_instance(id, "Bad Key", %{}),
            spawn_instance(run, %{}),
            Wire.send_request(:delete, route("/instances/#{id}"))
          ]
        end)

      for conn <- bodies do
        assert_clean(conn.resp_body, secret, run)
      end

      refute logs =~ secret
      refute logs =~ Wire.password()
    end
  end

  # Helpers

  # A flat-primary spawn re-points `:runtime_root` at its own flat root. The guard's ownership check must still read
  # the run base, or every later request, including the delete that would drop the instance, answers 404.
  describe "a flat_primary instance" do
    test "keeps the routes answering after the spawn re-points the runtime root", %{run: run} do
      id =
        spawn_instance(run, %{"phase" => "flat_primary"})
        |> Wire.json()
        |> Map.fetch!("instanceId")

      state = Wire.send_request(:get, route("/state"))
      assert state.status == 200
      assert Wire.json(state)["instance"]["instanceId"] == id

      deleted = Wire.send_request(:delete, route("/instances/#{id}"))
      assert deleted.status == 204
      assert TestInstance.state() == nil
    end
  end

  defp route(path), do: Wire.prefix() <> path

  defp spawn_instance(run, extra) do
    body = Map.merge(%{"runId" => run.run_id, "label" => "lifecycle"}, extra)
    Wire.send_request(:post, route("/instances"), body)
  end

  defp seed_instance(id, seed_key, seed) do
    Wire.send_request(:post, route("/instances/#{id}/seed"), %{
      "seedKey" => seed_key,
      "seed" => seed
    })
  end

  defp error(conn), do: Wire.json(conn)["error"]

  defp random_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  # Every answer's text is one of the fixed shapes: no secret, no password, and each string that is
  # a path is inside the run's roots.
  defp assert_clean(text, secret, run) do
    refute text =~ secret
    refute text =~ Wire.password()

    for path <- path_strings(text) do
      assert inside?(path, run.path) or inside?(path, run.sqlite_path),
             "a path outside the run: #{path}"
    end
  end

  # The run base itself is inside the run; anything else must sit under it.
  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp path_strings(text) do
    case Jason.decode(text) do
      {:ok, value} -> collect_paths(value)
      {:error, _reason} -> []
    end
  end

  defp collect_paths(value) when is_binary(value),
    do: if(String.starts_with?(value, "/"), do: [value], else: [])

  defp collect_paths(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&collect_paths/1)

  defp collect_paths(value) when is_list(value), do: Enum.flat_map(value, &collect_paths/1)
  defp collect_paths(_value), do: []

  # Runs the requests and gathers their answers and every log line they wrote at debug level.
  defp capture_log_with_bodies(fun) do
    parent = self()
    ref = make_ref()

    logs =
      capture_log([level: :debug], fn ->
        send(parent, {ref, fun.()})
      end)

    receive do
      {^ref, bodies} -> {bodies, logs}
    end
  end

  defp start_blocking_scheduler_task do
    Task.Supervisor.start_child(BnestApp.Scheduler.Tasks, fn ->
      receive do
        :release -> :ok
      end
    end)
  end

  defp finish_blocking_scheduler_task(task) do
    ref = Process.monitor(task)
    send(task, :release)
    assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 1_000
    await_no_scheduler_tasks(50)
  end

  defp await_no_scheduler_tasks(0), do: flunk("scheduler task did not finish")

  defp await_no_scheduler_tasks(attempts) do
    case Task.Supervisor.children(BnestApp.Scheduler.Tasks) do
      [] ->
        :ok

      _running ->
        Process.sleep(10)
        await_no_scheduler_tasks(attempts - 1)
    end
  end
end
