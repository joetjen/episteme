defmodule Episteme.QueryHelper do
  @moduledoc """
  Shared `build a database, run a goal` shorthand for tests -- Episteme
  has no reader, so tests build clauses and goals directly out of
  `Episteme.Term` (exactly what a caller embedding Episteme without
  Aletheia's syntax on top would do).
  """

  alias Episteme.{Database, Term}
  alias Episteme.Term.Compound

  @doc "A variable, named for display (defaults to anonymous)."
  @spec var(String.t()) :: Term.Var.t()
  def var(name \\ "_"), do: Term.new_var(name)

  @doc "Shorthand for building a compound term."
  @spec c(atom(), [term()]) :: Compound.t()
  def c(name, args), do: %Compound{name: name, args: args}

  @doc "Builds a database from `{:fact, head}`/`{:rule, head, body}` forms."
  @spec db([{:fact, term()} | {:rule, term(), term()}]) :: Database.t()
  def db(clauses \\ []), do: Database.consult_forms(Database.new(), clauses)

  @spec solutions(Database.t(), term()) :: [Episteme.solution()] | {:error, term()}
  def solutions(db, goal) do
    case Episteme.query(goal, db) do
      {:ok, solutions} -> solutions
      {:error, _} = err -> err
    end
  end
end
