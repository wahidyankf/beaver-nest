defmodule BnestApp.Storage.Lock do
  @moduledoc false

  alias BnestApp.Storage.Config

  @timeout_ms 30_000
  @poll_ms 10

  @spec with_shared((-> result)) :: result when result: var
  def with_shared(fun) do
    lease = acquire_shared(deadline())

    try do
      fun.()
    after
      File.rmdir(lease)
    end
  end

  @spec with_exclusive((-> result)) :: result when result: var
  def with_exclusive(fun) do
    exclusive = acquire_exclusive(deadline())

    try do
      wait_for_shared_leases(deadline())
      fun.()
    after
      File.rm(Path.join(exclusive, "owner"))
      File.rmdir(exclusive)
    end
  end

  defp acquire_shared(deadline) do
    ensure_root!()

    if File.exists?(exclusive_path()) do
      retry!(:shared, deadline)
    else
      lease = Path.join(shared_path(), random_id())
      :ok = File.mkdir(lease)

      if File.exists?(exclusive_path()) do
        File.rmdir(lease)
        retry!(:shared, deadline)
      else
        lease
      end
    end
  end

  defp acquire_exclusive(deadline) do
    ensure_root!()

    case File.mkdir(exclusive_path()) do
      :ok ->
        File.write!(Path.join(exclusive_path(), "owner"), System.pid())
        exclusive_path()

      {:error, :eexist} ->
        retry!(:exclusive, deadline)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create storage lock", path: exclusive_path()
    end
  end

  defp wait_for_shared_leases(deadline) do
    case File.ls!(shared_path()) do
      [] -> :ok
      _leases -> retry!(:drain, deadline)
    end
  end

  defp retry!(kind, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      raise "storage #{kind} lock timed out"
    end

    Process.sleep(@poll_ms)

    case kind do
      :shared -> acquire_shared(deadline)
      :exclusive -> acquire_exclusive(deadline)
      :drain -> wait_for_shared_leases(deadline)
    end
  end

  defp ensure_root! do
    File.mkdir_p!(shared_path())
    File.chmod!(root_path(), 0o700)
    File.chmod!(shared_path(), 0o700)
  end

  defp root_path, do: Config.pointer_path() <> ".lock"
  defp shared_path, do: Path.join(root_path(), "shared")
  defp exclusive_path, do: Path.join(root_path(), "exclusive")
  defp deadline, do: System.monotonic_time(:millisecond) + @timeout_ms
  defp random_id, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
end
