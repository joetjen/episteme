defmodule Episteme.Database do
  @moduledoc """
  Clause storage: `{name, arity} -> ordered list of {head, body}`
  clauses, `body` a single term (`true` for a fact, matching real
  Prolog's own internal `Head :- Body` shape) -- looked up by
  `Episteme.Engine` on every user-predicate call, and mutated in place by
  `Episteme.Engine`'s `assert`/`asserta`/`assertz`/`retract`/`retractall`/
  `abolish`/`dynamic` dispatch. Populated either directly (`add_clause/2`/`add_fact/2`,
  building terms yourself with `Episteme.Term`) or via `consult_forms/2`,
  for any front-end that parses its own surface syntax into
  `{:fact, _}`/`{:rule, _, _}` forms (Aletheia's reader is one such
  front-end, but this module has no dependency on it or any particular
  concrete syntax).

  Storage itself is pluggable via `Episteme.Database.Backend`: `new/1`
  defaults to `Episteme.Database.Backends.Ets` (in-memory, indexed by
  `{name, arity}` -- O(1) lookup instead of a linear scan, and mutable
  in place so `assert`/`retract` effects are visible to every holder of
  the same `t()` value, including across separate `Episteme.query/2`
  calls). Pass `backend: Episteme.Database.Backends.Dets, file: path` for
  a database that persists to disk, or any other module implementing
  `Episteme.Database.Backend`.

  Because a `t()` now wraps a mutable resource (an ETS table, an open
  DETS file, ...) rather than being a plain immutable value, call
  `close/1` when you're done with a database you don't want to leak --
  an ETS-backed one is cleaned up automatically if its owning process
  exits, but a DETS-backed one holds an open file handle until closed.
  """

  alias Episteme.Database.Backends.Ets
  alias Episteme.Term.Compound

  @enforce_keys [:backend, :state]
  defstruct [:backend, :state]

  @type clause :: {head :: term(), body :: term()}
  @type indicator :: {atom(), non_neg_integer()}
  @type t :: %__MODULE__{backend: module(), state: Episteme.Database.Backend.state()}

  @doc """
  Builds an empty database. `opts[:backend]` (default
  `Episteme.Database.Backends.Ets`) picks the storage backend; any other
  option is backend-specific and passed straight to its `init/1` (e.g.
  `:file` for `Episteme.Database.Backends.Dets`).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    {backend, backend_opts} = Keyword.pop(opts, :backend, Ets)
    %__MODULE__{backend: backend, state: backend.init(backend_opts)}
  end

  @doc "Releases whatever resources the backend holds (an ETS table, an open DETS file, ...)."
  @spec close(t()) :: :ok
  def close(%__MODULE__{backend: backend, state: state}), do: backend.close(state)

  @doc "Forces any buffered writes to durable storage. A no-op on the default in-memory backend."
  @spec sync(t()) :: :ok
  def sync(%__MODULE__{backend: backend, state: state}), do: backend.sync(state)

  @spec add_clause(t(), clause()) :: t()
  def add_clause(%__MODULE__{} = db, {head, _body} = clause) do
    {name, arity} = indicator(head)

    :ok =
      db.backend.replace_clauses(db.state, name, arity, clauses_for(db, name, arity) ++ [clause])

    db
  end

  @doc "Like `add_clause/2`, but prepends -- the primitive `asserta/1` builds on."
  @spec add_clause_first(t(), clause()) :: t()
  def add_clause_first(%__MODULE__{} = db, {head, _body} = clause) do
    {name, arity} = indicator(head)

    :ok =
      db.backend.replace_clauses(db.state, name, arity, [clause | clauses_for(db, name, arity)])

    db
  end

  @spec add_fact(t(), term()) :: t()
  def add_fact(db, head), do: add_clause(db, {head, true})

  @spec clauses_for(t(), atom(), non_neg_integer()) :: [clause()]
  def clauses_for(%__MODULE__{} = db, name, arity),
    do: db.backend.clauses_for(db.state, name, arity)

  @doc "Replaces the entire clause list for `{name, arity}` -- the primitive `Episteme.Engine`'s `retract/1`/`retractall/1` build on."
  @spec replace_clauses(t(), atom(), non_neg_integer(), [clause()]) :: t()
  def replace_clauses(%__MODULE__{} = db, name, arity, clauses) do
    :ok = db.backend.replace_clauses(db.state, name, arity, clauses)
    db
  end

  @spec defined?(t(), atom(), non_neg_integer()) :: boolean()
  def defined?(%__MODULE__{} = db, name, arity), do: db.backend.defined?(db.state, name, arity)

  @doc """
  Completely removes `{name, arity}` -- unlike `replace_clauses/4` with
  `[]` (what `retractall/1` builds on), `defined?/3` becomes false
  again afterward, so a later plain call raises `existence_error`
  rather than just failing.
  """
  @spec abolish(t(), atom(), non_neg_integer()) :: t()
  def abolish(%__MODULE__{} = db, name, arity) do
    :ok = db.backend.abolish(db.state, name, arity)
    db
  end

  @doc """
  Marks `{name, arity}` as defined without adding a clause -- what
  `dynamic/1` builds on. A later plain call to it fails (no matching
  clauses) instead of raising `existence_error`, and `assert`/`retract`
  can be used on it immediately. A no-op if it's already defined
  (existing clauses are never touched).
  """
  @spec declare_dynamic(t(), atom(), non_neg_integer()) :: t()
  def declare_dynamic(%__MODULE__{} = db, name, arity) do
    if defined?(db, name, arity), do: db, else: replace_clauses(db, name, arity, [])
  end

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
