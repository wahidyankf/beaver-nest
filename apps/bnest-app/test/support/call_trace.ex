defmodule BnestApp.Test.CallTrace do
  @moduledoc """
  Test-only observation of what code actually ran: `record/2` runs a function in the
  calling process while the BEAM's call tracing reports every call into the watched
  functions, with the module whose code made each call and, where asked, the value each
  returned. Tracing follows the processes the caller spawns while it runs.

  The behaviour drivers use it to see which Scheduler task ran a claimed run and what that
  task called, instead of resolving the task themselves. It lives under `test/support`, like
  `BnestApp.TestBackupDestination`, because tracing is process access the unit-layer
  boundary scan refuses in the drivers' own source.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  @typedoc "A traced call, with its caller's module and arguments, or a traced return."
  @type event ::
          {:call, mfa(), caller :: module() | nil, args :: [term()]}
          | {:return, mfa(), result :: term()}

  @with_results [{:_, [], [{:message, {:caller}}, {:return_trace}]}]
  @calls_only [{:_, [], [{:message, {:caller}}]}]

  @doc """
  Runs `fun` while tracing calls into the watched functions and returns its result with the
  observed events, in order. Each watched entry is `{{module, function, arity}, options}`,
  where `function` and `arity` may be `:_`; `results: true` also reports what each call
  returned. Only calls from another module (remote calls) are traced.

  `processes:` names the processes traced, with every process each spawns while `fun` runs,
  instead of the calling process: tracing only a supervisor observes only the work its
  children did.
  """
  @spec record([{{module(), atom(), arity() | :_}, keyword()}], (-> result), keyword()) ::
          {result, [event()]}
        when result: term()
  def record(watched, fun, options \\ []) when is_function(fun, 0) do
    collector = spawn_link(&collect/0)

    Enum.each(watched, fn {{module, _function, _arity} = pattern, options} ->
      Code.ensure_loaded!(module)
      spec = if Keyword.get(options, :results, false), do: @with_results, else: @calls_only
      :erlang.trace_pattern(pattern, spec, [:global])
    end)

    options
    |> Keyword.get(:processes, [self()])
    |> Enum.each(&:erlang.trace(&1, true, [:call, :set_on_spawn, {:tracer, collector}]))

    result =
      try do
        fun.()
      after
        # Tracing every process off also stops the processes `fun` spawned, and
        # `trace_delivered/1` guarantees every trace message reached the collector.
        :erlang.trace(:all, false, [:call, :set_on_spawn])

        Enum.each(watched, fn {pattern, _options} ->
          :erlang.trace_pattern(pattern, false, [:global])
        end)

        ref = :erlang.trace_delivered(:all)

        receive do
          {:trace_delivered, :all, ^ref} -> :ok
        end
      end

    {result, events(collector)}
  end

  @doc "The traced calls into `module.function`, as `{caller, args}` in call order."
  @spec calls([event()], module(), atom()) :: [{module() | nil, [term()]}]
  def calls(events, module, function),
    do: for({:call, {^module, ^function, _arity}, caller, args} <- events, do: {caller, args})

  @doc "The traced calls `caller`'s code made into `module`, as `{function, arity}`."
  @spec calls_by([event()], module(), module()) :: [{atom(), arity()}]
  def calls_by(events, caller, module),
    do: for({:call, {^module, function, arity}, ^caller, _args} <- events, do: {function, arity})

  @doc "What the traced calls into `module.function` returned, in return order."
  @spec results([event()], module(), atom()) :: [term()]
  def results(events, module, function),
    do: for({:return, {^module, ^function, _arity}, result} <- events, do: result)

  defp events(collector) do
    ref = make_ref()
    send(collector, {:events, self(), ref})

    receive do
      {^ref, events} -> events
    end
  end

  defp collect, do: collect([])

  defp collect(events) do
    receive do
      {:trace, _pid, :call, {module, function, args}, caller} ->
        collect([{:call, {module, function, length(args)}, caller_module(caller), args} | events])

      {:trace, _pid, :return_from, mfa, result} ->
        collect([{:return, mfa, result} | events])

      {:events, from, ref} ->
        send(from, {ref, Enum.reverse(events)})
    end
  end

  defp caller_module({module, _function, _arity}), do: module
  defp caller_module(_undefined), do: nil
end
