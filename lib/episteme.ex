defmodule Episteme do
  @moduledoc """
  Top-level API for querying an already-built `Episteme.Database`:
  `query/2` solves a goal term against one, returning every solution's
  variable bindings. No parser lives here -- a goal is always an
  already-built term (`Episteme.Term.new_var/1`, `%Episteme.Term.Compound{}`,
  plain Elixir atoms/numbers/lists), and a database is built directly via
  `Episteme.Database.add_clause/2`/`add_fact/2`, or via `consult_forms/2`
  for a front-end that parses its own surface syntax into
  `{:fact, _}`/`{:rule, _, _}` forms. Aletheia's reader is one such
  front-end, built on top of this library; this library has no
  dependency on it or on any particular concrete syntax.

  Uncaught Prolog exceptions (a real `throw/1` no `catch/3` in the
  program itself caught) surface as `{:error, term}` here, at the
  outermost boundary, rather than as a raw Elixir `throw` escaping to
  the caller.
  """

  alias Episteme.{Database, Engine, Term}
  alias Ichor.Backtrack.Tree

  @type solution :: %{optional(String.t()) => term()}

  @doc """
  Solves `goal` against `db`, returning every solution's variable
  bindings as `%{name => term}` maps (`Episteme.Term.to_text/1`-ready
  values, already fully resolved). A real Prolog `throw/1` that escapes
  uncaught surfaces as `{:error, term}`.
  """
  @spec query(term(), Database.t()) :: {:ok, [solution()]} | {:error, term()}
  def query(goal_term, db), do: wrap_query_result(run_query(goal_term, db))

  defp wrap_query_result({:error, _} = err), do: err
  defp wrap_query_result(solutions) when is_list(solutions), do: {:ok, solutions}

  @doc "Like `query/2`, but returns only the first solution (or `:none`)."
  @spec query_once(term(), Database.t()) :: {:ok, solution()} | :none | {:error, term()}
  def query_once(goal_term, db) do
    case query(goal_term, db) do
      {:ok, [first | _]} -> {:ok, first}
      {:ok, []} -> :none
      {:error, _} = err -> err
    end
  end

  @doc """
  Like `query/2`, but doesn't force every solution eagerly -- returns the
  raw lazy solution stream plus the goal's own named variables, both
  meant to be passed straight to `next_solution/2`. For a REPL (or any
  caller that only wants the first few solutions of a possibly-infinite
  search) instead of `query/2`'s own "pull the whole list" behavior.
  """
  @spec query_lazy(term(), Database.t()) :: {Tree.t(), MapSet.t(Term.Var.t())}
  def query_lazy(goal_term, db) do
    {Engine.solve_query(goal_term, db), collect_named_vars(goal_term, MapSet.new())}
  end

  @doc """
  Pulls one solution from a `query_lazy/2` stream: `{:solution, bindings,
  rest}`, `:none` when exhausted, or `{:error, term}` for an uncaught
  Prolog exception raised while solving *this* solution (each pull is
  independently guarded, since a lazy caller may pull solutions across
  arbitrarily many separate calls, unlike `query/2`'s one eager pass).
  """
  @spec next_solution(Tree.t(), MapSet.t(Term.Var.t())) ::
          {:solution, solution(), Tree.t()} | :none | {:error, term()}
  def next_solution(stream, vars) do
    case Tree.next(stream) do
      :empty -> :none
      {:solution, bindings, rest} -> {:solution, solution_map(bindings, vars), rest}
    end
  catch
    {:episteme_throw, ball} -> {:error, ball}
  end

  defp run_query(goal_term, db) do
    {stream, vars} = query_lazy(goal_term, db)
    collect_all(stream, vars)
  end

  defp collect_all(stream, vars) do
    case next_solution(stream, vars) do
      :none ->
        []

      {:error, _} = err ->
        err

      {:solution, solution, rest} ->
        case collect_all(rest, vars) do
          {:error, _} = err -> err
          more -> [solution | more]
        end
    end
  end

  defp solution_map(bindings, vars) do
    Map.new(vars, fn %Term.Var{ref: ref, name: name} ->
      {name, Term.resolve_deep(%Term.Var{ref: ref, name: name}, bindings)}
    end)
  end

  defp collect_named_vars(%Term.Var{name: name} = var, acc) do
    if name == "_", do: acc, else: MapSet.put(acc, var)
  end

  defp collect_named_vars(%Term.Compound{args: args}, acc) do
    Enum.reduce(args, acc, &collect_named_vars/2)
  end

  defp collect_named_vars(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_named_vars/2)
  end

  defp collect_named_vars(_other, acc), do: acc
end
