defmodule BnestAppWeb.TestingControl.RequestTest do
  use ExUnit.Case, async: true

  alias BnestAppWeb.TestingControl.Request

  @json "application/json"

  describe "envelope" do
    test "accepts one application/json content type, with or without parameters" do
      assert Request.envelope([@json], []) == :ok
      assert Request.envelope(["application/json; charset=utf-8"], ["12"]) == :ok
    end

    test "refuses a missing, other or repeated content type as invalid_request" do
      detail = "the content type must be application/json"

      for types <- [[], ["text/plain"], ["application/x-www-form-urlencoded"], [@json, @json]] do
        assert Request.envelope(types, []) == {:error, {:invalid_request, detail}}
      end
    end

    test "refuses a body over 256 KiB by its content length, and admits exactly 256 KiB" do
      assert Request.envelope([@json], ["262144"]) == :ok

      assert Request.envelope([@json], ["262145"]) ==
               {:error, {:invalid_request, "the body is larger than 256 KiB"}}
    end

    test "refuses a content length that is not a plain number, or that is repeated" do
      for lengths <- [["-1"], ["12x"], [""], [" 12"], ["1", "2"]] do
        assert {:error, {:invalid_request, _detail}} = Request.envelope([@json], lengths)
      end
    end

    test "a body without a content length is bounded only by the endpoint's parser" do
      assert Request.envelope([@json], []) == :ok
    end
  end

  describe "spawn body" do
    test "accepts a run id and a label, with the default phase, no seed and no instance id" do
      assert Request.spawn_body(%{"runId" => "run-1", "label" => "fresh-db"}) ==
               {:ok,
                %{
                  run_id: "run-1",
                  label: "fresh-db",
                  phase: :sqlite_primary,
                  storage: :configured,
                  seed: :absent,
                  instance_id: nil
                }}
    end

    test "accepts an unconfigured storage choice only for a flat-primary instance" do
      assert {:ok, %{phase: :flat_primary, storage: :unconfigured}} =
               Request.spawn_body(%{
                 "runId" => "r",
                 "label" => "l",
                 "phase" => "flat_primary",
                 "storage" => "unconfigured"
               })

      assert {:ok, %{storage: :configured}} =
               Request.spawn_body(%{"runId" => "r", "label" => "l", "storage" => "configured"})

      assert {:error,
              {:invalid_request, "an unconfigured storage choice needs the flat_primary phase"}} =
               Request.spawn_body(%{"runId" => "r", "label" => "l", "storage" => "unconfigured"})
    end

    test "refuses a storage choice that is neither configured nor unconfigured" do
      for storage <- ["chosen", "UNCONFIGURED", nil, 1] do
        assert {:error, {:invalid_request, "the storage must be configured or unconfigured"}} =
                 Request.spawn_body(%{"runId" => "r", "label" => "l", "storage" => storage})
      end
    end

    test "accepts a client-chosen instance id of exactly 16 lowercase letters or digits" do
      for id <- ["0123456789abcdef", "abcdefghijklmnop", "a1b2c3d4e5f6g7h8"] do
        assert {:ok, %{instance_id: ^id}} =
                 Request.spawn_body(%{"runId" => "r", "label" => "l", "instanceId" => id})
      end
    end

    test "refuses an instance id that is not 16 lowercase letters or digits, as invalid_request" do
      detail = "the instance id must be 16 lowercase letters or digits"

      bad = [
        "",
        "0123456789abcde",
        "0123456789abcdef0",
        "0123456789ABCDEF",
        "0123456789abcde-",
        " 0123456789abcdef",
        "0123456789abcdef\n",
        "0123456789abcdé",
        nil,
        7
      ]

      for id <- bad do
        assert Request.spawn_body(%{"runId" => "r", "label" => "l", "instanceId" => id}) ==
                 {:error, {:invalid_request, detail}}
      end
    end

    test "accepts flat_primary, and passes a seed of any shape on to the seed validator" do
      assert {:ok, %{phase: :flat_primary, seed: {:present, %{"familyChat" => %{}}}}} =
               Request.spawn_body(%{
                 "runId" => "run-1",
                 "label" => "flat",
                 "phase" => "flat_primary",
                 "seed" => %{"familyChat" => %{}}
               })

      assert {:ok, %{seed: {:present, nil}}} =
               Request.spawn_body(%{"runId" => "run-1", "label" => "flat", "seed" => nil})
    end

    test "refuses an unknown top-level field" do
      assert Request.spawn_body(%{"runId" => "r", "label" => "l", "owner" => "x"}) ==
               {:error, {:invalid_request, "the body has an unknown field"}}
    end

    test "a JSON array arrives under _json, so it is refused as an unknown field" do
      assert {:error, {:invalid_request, "the body has an unknown field"}} =
               Request.spawn_body(%{"_json" => [1, 2]})
    end

    test "refuses a missing or non-string run id" do
      for body <- [
            %{"label" => "l"},
            %{"runId" => 7, "label" => "l"},
            %{"runId" => nil, "label" => "l"}
          ] do
        assert {:error, {:invalid_request, _detail}} = Request.spawn_body(body)
      end
    end

    test "refuses a label that is not a lowercase slug of at most 60 characters" do
      bad = ["", "Fresh", "a--", "-a", "a b", "a_b", String.duplicate("a", 61)]

      for label <- bad do
        assert {:error, {:invalid_request, "the label must be a slug of at most 60 characters"}} =
                 Request.spawn_body(%{"runId" => "r", "label" => label})
      end

      assert {:ok, _spawn} =
               Request.spawn_body(%{"runId" => "r", "label" => String.duplicate("a", 60)})
    end

    test "refuses a phase that is neither sqlite_primary nor flat_primary" do
      for phase <- ["sqlite", "FLAT_PRIMARY", nil, 1] do
        assert {:error, {:invalid_request, "the phase must be sqlite_primary or flat_primary"}} =
                 Request.spawn_body(%{"runId" => "r", "label" => "l", "phase" => phase})
      end
    end
  end

  describe "seed body" do
    test "accepts a seed key and a seed" do
      assert Request.seed_body(%{"seedKey" => "admins", "seed" => %{"accounts" => []}}) ==
               {:ok, %{seed_key: "admins", seed: %{"accounts" => []}}}
    end

    test "refuses a missing or non-string seed key, a missing seed, and an unknown field" do
      assert {:error, {:invalid_request, _}} = Request.seed_body(%{"seed" => %{}})
      assert {:error, {:invalid_request, _}} = Request.seed_body(%{"seedKey" => 1, "seed" => %{}})
      assert {:error, {:invalid_request, _}} = Request.seed_body(%{"seedKey" => "admins"})

      assert {:error, {:invalid_request, "the body has an unknown field"}} =
               Request.seed_body(%{"seedKey" => "a", "seed" => %{}, "runId" => "r"})
    end
  end
end
