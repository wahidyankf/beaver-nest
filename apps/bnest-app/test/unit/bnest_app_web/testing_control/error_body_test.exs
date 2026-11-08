defmodule BnestAppWeb.TestingControl.ErrorBodyTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.TestingControl.ErrorBody

  @run_path "/synthetic/data/test/runs/run-1/instances/0123456789abcdef"

  test "every refusal has one status and one code, as the error table sets" do
    table = [
      {{:invalid_request, "the body has an unknown field"}, 400, "invalid_request"},
      {:run_mismatch, 409, "run_mismatch"},
      {:instance_active, 409, "instance_active"},
      {:instance_exists, 409, "instance_active"},
      {:not_current, 409, "not_current"},
      {:instance_busy, 409, "instance_busy"},
      {:seed_conflict, 409, "seed_conflict"},
      {{:seed_invalid, :invalid_username, "accounts[0].username"}, 422, "seed_invalid"},
      {{:spawn_failed, :migrate}, 500, "spawn_failed"},
      {{:cleanup_failed, @run_path}, 500, "cleanup_failed"},
      {:seed_failed, 500, "seed_failed"}
    ]

    for {reason, status, code} <- table do
      assert {^status, %{"error" => %{"code" => ^code}}} = ErrorBody.render(reason)
    end
  end

  test "every body has the code, detail and path keys, a string detail, and step only for spawns" do
    for reason <- [:run_mismatch, {:spawn_failed, :create}, {:cleanup_failed, @run_path}] do
      {_status, %{"error" => error}} = ErrorBody.render(reason)

      assert Enum.all?(["code", "detail", "path"], &Map.has_key?(error, &1))
      assert is_binary(error["detail"])
      assert Map.keys(error) -- ["code", "detail", "path", "step"] == []
    end

    assert {_status, %{"error" => error}} = ErrorBody.render(:run_mismatch)
    refute Map.has_key?(error, "step")
  end

  test "a spawn failure names its step and carries no path" do
    for step <- [:create, :activate, :migrate, :seed] do
      assert {500, %{"error" => error}} = ErrorBody.render({:spawn_failed, step})

      assert error == %{
               "code" => "spawn_failed",
               "detail" => error["detail"],
               "path" => nil,
               "step" => to_string(step)
             }
    end
  end

  test "a client-chosen id whose directories exist is refused with a fixed detail and no path" do
    assert {409, %{"error" => error}} = ErrorBody.render(:instance_exists)

    assert error == %{
             "code" => "instance_active",
             "detail" => "an instance with that id already exists",
             "path" => nil
           }
  end

  test "a cleanup failure names the retained path it was given, and nothing else" do
    assert {500, %{"error" => %{"code" => "cleanup_failed", "path" => @run_path}}} =
             ErrorBody.render({:cleanup_failed, @run_path})
  end

  test "a seed refusal's detail is its reason, and its path names the field" do
    assert {422,
            %{
              "error" => %{
                "code" => "seed_invalid",
                "detail" => "invalid_username",
                "path" => "accounts[0].username"
              }
            }} =
             ErrorBody.render({:seed_invalid, :invalid_username, "accounts[0].username"})

    assert {422, %{"error" => %{"detail" => "unknown_seed_key", "path" => "seedKey"}}} =
             ErrorBody.render({:seed_invalid, :unknown_seed_key, "seedKey"})
  end

  test "the interrupted-import reasons are reported as their own reason, at their field" do
    for {reason, path} <- [
          {:wrong_phase, "records[0].kind"},
          {:unsupported_source, "records[0].value.storageKey"},
          {:oversized, "records[0].value.payload"}
        ] do
      assert {422, %{"error" => %{"detail" => detail, "path" => ^path}}} =
               ErrorBody.render({:seed_invalid, reason, path})

      assert detail == Atom.to_string(reason)
    end
  end

  test "a seed reason outside the seed's own vocabulary is reported as invalid_payload" do
    assert {422, %{"error" => %{"detail" => "invalid_payload"}}} =
             ErrorBody.render({:seed_invalid, :anything_else, "accounts"})
  end

  test "a seed path that names a key outside the seed schema is reported as unknown" do
    assert {422, %{"error" => %{"path" => "unknown"}}} =
             ErrorBody.render({:seed_invalid, :invalid_payload, "bogus"})

    assert {422, %{"error" => %{"path" => "unknown"}}} =
             ErrorBody.render({:seed_invalid, :invalid_payload, "accounts[0].password_hint"})

    assert {422, %{"error" => %{"path" => "unknown"}}} =
             ErrorBody.render({:seed_invalid, :invalid_payload, "records[0].value.secretFlag"})
  end

  test "a seed path made of schema names and indexes is kept as it is" do
    for path <- [
          "seed",
          "seedKey",
          "accounts",
          "accounts[1].roles",
          "familyChat.messages[0].sender",
          "pushSubscriptions[0].p256dh",
          "records[0].value.theme"
        ] do
      assert {422, %{"error" => %{"path" => ^path}}} =
               ErrorBody.render({:seed_invalid, :invalid_payload, path})
    end
  end

  test "a spawn step outside the lifecycle is reported as unknown, so no other step leaks" do
    assert {500, %{"error" => %{"step" => "unknown"}}} = ErrorBody.render({:spawn_failed, :other})
  end

  test "no body echoes a password, a secret or a filesystem path other than the retained one" do
    reasons = [
      {:invalid_request, "the body has an unknown field"},
      {:seed_invalid, :invalid_username, "accounts[0].username"},
      {:spawn_failed, :seed},
      {:cleanup_failed, @run_path},
      :seed_failed
    ]

    for reason <- reasons do
      {_status, body} = ErrorBody.render(reason)
      encoded = Jason.encode!(body)

      refute encoded =~ "password"
      refute encoded =~ "secret"
      refute encoded =~ "/home/"
    end
  end
end
