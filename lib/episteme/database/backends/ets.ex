defmodule Episteme.Database.Backends.Ets do
  @moduledoc """
  The default `Episteme.Database.Backend`: an in-memory `:ets` `:set`
  table keyed by `{name, arity}`, each row's value the predicate's own
  clause list -- so clause order (what backtracking order depends on) is
  exactly that Elixir list's order, never ETS's own unspecified
  multi-row traversal order. `:public` access, so any process holding
  the same `Episteme.Database.t()` value can read and mutate it, not
  just the process that called `init/1` -- there is no coordination
  beyond what `:ets` itself serializes, so concurrent `assert`/`retract`
  against the *same predicate* from multiple processes can race (a
  read-modify-write on one row); concurrent access to *different*
  predicates never conflicts.

  Table lifetime is tied to whichever process created it: like any ETS
  table, it is torn down automatically if that process dies, `close/1`
  or not.
  """

  @behaviour Episteme.Database.Backend

  @impl true
  def init(_opts), do: :ets.new(:episteme_database, [:set, :public])

  @impl true
  def clauses_for(table, name, arity) do
    case :ets.lookup(table, {name, arity}) do
      [{_key, clauses}] -> clauses
      [] -> []
    end
  end

  @impl true
  def replace_clauses(table, name, arity, clauses) do
    :ets.insert(table, {{name, arity}, clauses})
    :ok
  end

  @impl true
  def defined?(table, name, arity), do: :ets.member(table, {name, arity})

  @impl true
  def sync(_table), do: :ok

  @impl true
  def close(table) do
    :ets.delete(table)
    :ok
  end
end
