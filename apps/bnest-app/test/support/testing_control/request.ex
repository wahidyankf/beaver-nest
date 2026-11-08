defmodule BnestAppWeb.TestingControl.Request do
  @moduledoc """
  The shape rules of a testing-control request, before any route acts (ADR 001, section 2): the
  content type, the body size by its content length, the top-level fields and their types.

  A refusal here answers 400 `invalid_request` with a fixed detail. The contents of a seed are not
  judged here: `BnestApp.TestInstance.Seed` judges them and answers 422 `seed_invalid`.

  Malformed JSON never reaches this module. `Plug.Parsers` runs in the endpoint, before the router,
  so a malformed body gets the endpoint's own 400, the same answer a missing route gets for it.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @max_body_bytes 262_144
  @max_label_bytes 60
  @label_pattern ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/
  @digits_pattern ~r/\A[0-9]+\z/
  @instance_id_pattern ~r/\A[a-z0-9]{16}\z/
  @instance_id_detail "the instance id must be 16 lowercase letters or digits"
  @phases %{"sqlite_primary" => :sqlite_primary, "flat_primary" => :flat_primary}

  @type invalid :: {:error, {:invalid_request, String.t()}}

  @doc "The content type and the content length of the request, before its body is judged."
  @spec envelope([String.t()], [String.t()]) :: :ok | invalid()
  def envelope(content_types, content_lengths) do
    with :ok <- json_type(content_types), do: length_within_limit(content_lengths)
  end

  @doc """
  The spawn body: `runId` and `label` are required; `instanceId`, `phase` and `seed` are optional,
  and no other field is allowed. `seed` is `:absent` or `{:present, value}`, so an explicit `null` is
  judged by the seed validator rather than dropped. `instanceId` is `nil` when absent: the server
  then generates the id. A present id is the client's own random 16-character id, so a client can
  name its usernames before the spawn (ADR 001, section 2).
  """
  @spec spawn_body(map()) ::
          {:ok,
           %{
             run_id: String.t(),
             label: String.t(),
             instance_id: String.t() | nil,
             phase: atom(),
             seed: :absent | {:present, term()}
           }}
          | invalid()
  def spawn_body(body) when is_map(body) do
    with :ok <- known_fields(body, ~w(runId label instanceId phase seed)),
         {:ok, run_id} <- required_string(body, "runId", "the body must name the run id"),
         {:ok, label} <- label(body),
         {:ok, instance_id} <- instance_id(body),
         {:ok, phase} <- phase(body) do
      {:ok,
       %{
         run_id: run_id,
         label: label,
         instance_id: instance_id,
         phase: phase,
         seed: optional(body, "seed")
       }}
    end
  end

  @doc "The seed route body: `seedKey` and `seed` are required, and no other field is allowed."
  @spec seed_body(map()) :: {:ok, %{seed_key: String.t(), seed: term()}} | invalid()
  def seed_body(body) when is_map(body) do
    with :ok <- known_fields(body, ~w(seedKey seed)),
         {:ok, seed_key} <- required_string(body, "seedKey", "the body must name the seed key"),
         {:ok, seed} <- required(body, "seed", "the body must carry the seed") do
      {:ok, %{seed_key: seed_key, seed: seed}}
    end
  end

  defp json_type([value]) do
    case value |> String.split(";") |> hd() |> String.trim() |> String.downcase() do
      "application/json" -> :ok
      _other -> invalid("the content type must be application/json")
    end
  end

  defp json_type(_types), do: invalid("the content type must be application/json")

  defp length_within_limit([]), do: :ok

  defp length_within_limit([value]) do
    cond do
      not Regex.match?(@digits_pattern, value) ->
        invalid("the content length must be one number")

      String.to_integer(value) > @max_body_bytes ->
        invalid("the body is larger than 256 KiB")

      true ->
        :ok
    end
  end

  defp length_within_limit(_values), do: invalid("the content length must be one number")

  defp known_fields(body, allowed) do
    if Enum.all?(Map.keys(body), &(&1 in allowed)),
      do: :ok,
      else: invalid("the body has an unknown field")
  end

  defp required_string(body, key, detail) do
    case Map.get(body, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> invalid(detail)
    end
  end

  defp label(body) do
    case Map.get(body, "label") do
      value when is_binary(value) and byte_size(value) <= @max_label_bytes ->
        if Regex.match?(@label_pattern, value),
          do: {:ok, value},
          else: invalid("the label must be a slug of at most 60 characters")

      _other ->
        invalid("the label must be a slug of at most 60 characters")
    end
  end

  defp instance_id(body) do
    case Map.fetch(body, "instanceId") do
      :error ->
        {:ok, nil}

      {:ok, value} when is_binary(value) ->
        if Regex.match?(@instance_id_pattern, value),
          do: {:ok, value},
          else: invalid(@instance_id_detail)

      {:ok, _other} ->
        invalid(@instance_id_detail)
    end
  end

  defp phase(body) do
    case Map.fetch(body, "phase") do
      :error -> {:ok, :sqlite_primary}
      {:ok, value} when is_map_key(@phases, value) -> {:ok, Map.fetch!(@phases, value)}
      {:ok, _other} -> invalid("the phase must be sqlite_primary or flat_primary")
    end
  end

  defp optional(body, key) do
    case Map.fetch(body, key) do
      :error -> :absent
      {:ok, value} -> {:present, value}
    end
  end

  defp required(body, key, detail) do
    case Map.fetch(body, key) do
      {:ok, value} -> {:ok, value}
      :error -> invalid(detail)
    end
  end

  defp invalid(detail), do: {:error, {:invalid_request, detail}}
end
