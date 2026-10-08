defmodule Dandelion.Resilience do
  @moduledoc """
  Calling something that can fail or hang — another service, a webhook receiver,
  a payment provider — without letting it take you down. ≈ Go's
  `context.WithTimeout` + a retry loop + a circuit breaker (`sony/gobreaker`),
  in one call.

  Start it in your supervision tree:

      Dandelion.Resilience

  then wrap the call:

      case Dandelion.Resilience.call({:hook, host}, fn -> deliver(url, body) end,
             timeout: 5_000, retries: 2) do
        {:ok, response} -> :ok
        {:error, :circuit_open} -> try_later()
        {:error, reason} -> failed(reason)
      end

  The function returns `{:ok, value}` or `{:error, reason}` (anything else, or a
  raise or exit, counts as an error). Three protections, each with a number:

    * **Timeout** (`:timeout`, default 5 000 ms) — the call runs in its own process
      and is killed when the time is up: `{:error, :timeout}`.
    * **Retries** (`:retries`, default 0) — a failed call is made again after
      `:backoff` ms (default 200), doubling each time with ±20 % jitter, so a crowd of
      callers does not retry in step. `retry?: fn reason -> boolean end` says which
      errors are worth another try (a 400 is not).
    * **Circuit breaker** — after `:failure_threshold` calls in a row have failed
      (default 5, counted after their retries) the circuit for that `name` *opens*:
      calls return `{:error, :circuit_open}` at once, without calling, for
      `:reset_after` ms (default 30 000). Then one call is let through (*half-open*):
      if it succeeds the circuit closes, if it fails the circuit opens again. A
      service that is down is left alone instead of being hammered, and your callers
      are not stuck waiting for it.

  `name` is any term: use one per thing you call (`{:webhook, host}`), so one dead
  receiver does not open the circuit for the others.

  **Per node**, like `Dandelion.RateLimit`: each node learns for itself that a
  service is down. Nothing asks Postgres or the other nodes on a call, so the
  breaker can't be the thing that fails when the cluster is struggling. A node that
  restarts starts with every circuit closed.

  Telemetry: `[:dandelion, :resilience, :call]` for each call (measurements:
  `duration`; metadata: `name`, `result` — `:ok`, `:error`, `:timeout` or
  `:circuit_open`) and `[:dandelion, :resilience, :circuit]` when a circuit changes
  state (metadata: `name`, `state`: `:open`, `:half_open` or `:closed`).
  """
  use Supervisor

  @table __MODULE__
  @tasks Dandelion.Resilience.Tasks

  @defaults [
    timeout: 5_000,
    retries: 0,
    backoff: 200,
    failure_threshold: 5,
    reset_after: 30_000
  ]

  @doc false
  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Supervisor.init([{Task.Supervisor, name: @tasks}], strategy: :one_for_one)
  end

  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Calls `fun` under the protections above. Returns what it returned, or
  `{:error, :timeout}`, `{:error, :circuit_open}`, or `{:error, reason}`.
  """
  @spec call(term(), (-> result()), keyword()) :: result()
  def call(name, fun, opts \\ []) when is_function(fun, 0) do
    opts = Keyword.merge(@defaults, opts)
    started = System.monotonic_time()

    result =
      case admit(name, opts) do
        :ok -> run(name, fun, opts)
        :open -> {:error, :circuit_open}
      end

    :telemetry.execute(
      [:dandelion, :resilience, :call],
      %{duration: System.monotonic_time() - started},
      %{name: name, result: label(result)}
    )

    result
  end

  @doc """
  `:closed`, `:open` or `:half_open` for `name` on this node. An open circuit stays
  `:open` here until the next call, after `:reset_after`, lets one through.
  """
  @spec state(term()) :: :closed | :open | :half_open
  def state(name) do
    case :ets.lookup(@table, name) do
      [{_, state, _, _}] -> state
      [] -> :closed
    end
  end

  @doc "Closes the circuit for `name` and forgets its failures (for tests, or by hand)."
  def reset(name), do: :ets.delete(@table, name)

  # -- the breaker ---------------------------------------------------------------

  # Row: {name, state, consecutive_failures, opened_at_ms}
  defp admit(name, opts) do
    case :ets.lookup(@table, name) do
      [{_, :open, failures, opened_at}] = row ->
        if System.monotonic_time(:millisecond) - opened_at >= opts[:reset_after] do
          # one caller wins the right to probe; the others still see an open circuit
          probe = [{name, :half_open, failures, opened_at}]

          if :ets.select_replace(@table, [{hd(row), [], [{:const, hd(probe)}]}]) == 1 do
            circuit(name, :half_open)
            :ok
          else
            :open
          end
        else
          :open
        end

      [{_, :half_open, _, _}] ->
        :open

      _ ->
        :ok
    end
  end

  defp succeeded(name) do
    case :ets.lookup(@table, name) do
      [] ->
        :ok

      [{_, :closed, _, _}] ->
        :ets.delete(@table, name)

      [_open_or_half_open] ->
        :ets.delete(@table, name)
        circuit(name, :closed)
    end
  end

  defp failed(name, opts) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, name) do
      [{_, :half_open, failures, _}] ->
        :ets.insert(@table, {name, :open, failures + 1, now})
        circuit(name, :open)

      _ ->
        failures = :ets.update_counter(@table, name, {3, 1}, {name, :closed, 0, 0})

        if failures >= opts[:failure_threshold] do
          :ets.insert(@table, {name, :open, failures, now})
          circuit(name, :open)
        end
    end
  end

  defp circuit(name, state),
    do: :telemetry.execute([:dandelion, :resilience, :circuit], %{}, %{name: name, state: state})

  # -- the call, with its retries --------------------------------------------------

  defp run(name, fun, opts), do: attempt(name, fun, opts, 0)

  defp attempt(name, fun, opts, tries) do
    case once(fun, opts[:timeout]) do
      {:ok, _} = ok ->
        succeeded(name)
        ok

      {:error, reason} = error ->
        retry? = Keyword.get(opts, :retry?, fn _ -> true end)

        if tries < opts[:retries] and retry?.(reason) do
          Process.sleep(backoff(opts[:backoff], tries))
          attempt(name, fun, opts, tries + 1)
        else
          failed(name, opts)
          error
        end
    end
  end

  defp once(fun, timeout) do
    task = Task.Supervisor.async_nolink(@tasks, fn -> normalise(fun) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  defp normalise(fun) do
    case fun.() do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other -> {:error, {:unexpected, other}}
    end
  rescue
    exception -> {:error, {:raised, exception}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # base * 2^tries, ±20 %
  defp backoff(base, tries) do
    wait = base * Integer.pow(2, tries)
    round(wait * (0.8 + :rand.uniform() * 0.4))
  end

  defp label({:ok, _}), do: :ok
  defp label({:error, :timeout}), do: :timeout
  defp label({:error, :circuit_open}), do: :circuit_open
  defp label({:error, _}), do: :error
end
