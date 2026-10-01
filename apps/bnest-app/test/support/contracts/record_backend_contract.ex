defmodule BnestApp.Test.Contracts.RecordBackendContract do
  @moduledoc """
  The behaviour every `BnestApp.Storage.Ports.RecordBackend` implementation shares. A test
  module uses this template and defines `new_store/1`, which takes the ExUnit context and
  returns a fresh backend state; the template then runs the whole contract against it.

  The records are synthetic theme preferences owned by `test-user-` identities, the one record
  kind that every backend stores without another context's registration.
  """

  use ExUnit.CaseTemplate

  @owner "test-user-contract"

  @doc "A valid theme-preference record for `owner` at `revision`."
  @spec theme(String.t(), non_neg_integer(), String.t()) :: map()
  def theme(theme, revision, owner \\ @owner) do
    %{
      "schemaVersion" => 1,
      "recordType" => "theme-preference",
      "ownerId" => owner,
      "sourceImportId" => nil,
      "revision" => revision,
      "theme" => theme,
      "updatedAt" => "2026-09-01T00:00:00Z"
    }
  end

  @spec owner() :: String.t()
  def owner, do: @owner

  using do
    quote do
      import BnestApp.Test.Contracts.RecordBackendContract, only: [theme: 2, owner: 0]

      alias BnestApp.Storage.Ports.RecordBackend

      setup context, do: [store: new_store(context)]

      describe "RecordBackend contract" do
        test "reads an absent record as missing", %{store: store} do
          assert RecordBackend.read(store, :theme, owner()) == {:error, :missing}
        end

        test "put_new stores a new record once", %{store: store} do
          record = theme("dark", 0)

          assert RecordBackend.put_new(store, :theme, owner(), record) == {:ok, record}
          assert RecordBackend.read(store, :theme, owner()) == {:ok, record}

          assert RecordBackend.put_new(store, :theme, owner(), theme("light", 0)) ==
                   {:error, :exists}

          assert RecordBackend.read(store, :theme, owner()) == {:ok, record}
        end

        test "replace changes only an existing record", %{store: store} do
          assert RecordBackend.replace(store, :theme, owner(), theme("dark", 0)) ==
                   {:error, :missing}

          {:ok, _record} = RecordBackend.put_new(store, :theme, owner(), theme("dark", 0))
          replacement = theme("light", 0)

          assert RecordBackend.replace(store, :theme, owner(), replacement) == {:ok, replacement}
          assert RecordBackend.read(store, :theme, owner()) == {:ok, replacement}
        end

        test "write assigns the next revision only from the expected one", %{store: store} do
          assert {:ok, %{"revision" => 0} = first} =
                   RecordBackend.write(store, :theme, owner(), nil, theme("dark", 0))

          assert RecordBackend.write(store, :theme, owner(), nil, theme("light", 0)) ==
                   {:error, :stale}

          assert RecordBackend.write(store, :theme, owner(), 5, theme("light", 0)) ==
                   {:error, :stale}

          assert RecordBackend.read(store, :theme, owner()) == {:ok, first}

          assert {:ok, %{"revision" => 1, "theme" => "light"} = second} =
                   RecordBackend.write(store, :theme, owner(), 0, theme("light", 0))

          assert RecordBackend.read(store, :theme, owner()) == {:ok, second}
        end

        test "remove_exact removes only the expected record", %{store: store} do
          {:ok, record} = RecordBackend.put_new(store, :theme, owner(), theme("dark", 0))

          assert RecordBackend.remove_exact(store, :theme, owner(), theme("light", 0)) ==
                   {:error, :changed}

          assert RecordBackend.read(store, :theme, owner()) == {:ok, record}
          assert RecordBackend.remove_exact(store, :theme, owner(), record) == :ok
          assert RecordBackend.read(store, :theme, owner()) == {:error, :missing}
          assert RecordBackend.remove_exact(store, :theme, owner(), record) == :ok
        end
      end
    end
  end
end
