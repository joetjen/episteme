defmodule Episteme.Database do
  @moduledoc """
  Clause storage: `{name, arity} -> ordered list of {head, body}`
  clauses, `body` a single term (`true` for a fact, matching real
  Prolog's own internal `Head :- Body` shape) -- looked up by
  `Episteme.Engine` on every user-predicate call. Populated either
  directly (`add_clause/2`/`add_fact/2`, building terms yourself with
  `Episteme.Term`) or via `consult_forms/2`, for any front-end that
  parses its own surface syntax into `{:fact, _}`/`{:rule, _, _}` forms
  (Aletheia's reader is one such front-end, but this module has no
  dependency on it or any particular concrete syntax). `assert`/`retract`
  as callable predicates are a later milestone; `add_clause/2` is the
  primitive both `consult_forms/2` today and `assert` later build on.
  """

  alias Episteme.Term.Compound

  defstruct clauses: %{}

  @type clause :: {head :: term(), body :: term()}
  @type indicator :: {atom(), non_neg_integer()}
  @type t :: %__MODULE__{clauses: %{indicator() => [clause()]}}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add_clause(t(), clause()) :: t()
  def add_clause(%__MODULE__{} = db, {head, _body} = clause) do
    key = indicator(head)
    %{db | clauses: Map.update(db.clauses, key, [clause], &(&1 ++ [clause]))}
  end

  @spec add_fact(t(), term()) :: t()
  def add_fact(db, head), do: add_clause(db, {head, true})

  @spec clauses_for(t(), atom(), non_neg_integer()) :: [clause()]
  def clauses_for(%__MODULE__{} = db, name, arity), do: Map.get(db.clauses, {name, arity}, [])

  @spec defined?(t(), atom(), non_neg_integer()) :: boolean()
  def defined?(%__MODULE__{} = db, name, arity), do: Map.has_key?(db.clauses, {name, arity})

  @spec indicator(term()) :: indicator()
  def indicator(%Compound{name: name, args: args}), do: {name, length(args)}
  def indicator(atom) when is_atom(atom), do: {atom, 0}

  @doc """
  Loads every `{:fact, head}`/`{:rule, head, body}` form into `db`.
  `{:directive, _}` forms are ignored here -- a front-end reader's own
  directives (an `op/3` table mutation, say) are that front-end's
  concern, not the database's.
  """
  @spec consult_forms(t(), list()) :: t()
  def consult_forms(db, forms) do
    Enum.reduce(forms, db, fn
      {:fact, head}, db -> add_fact(db, head)
      {:rule, head, body}, db -> add_clause(db, {head, body})
      {:directive, _goal}, db -> db
    end)
  end
end
