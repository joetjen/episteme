defmodule Episteme.Database.Backend do
  @moduledoc """
  The storage contract `Episteme.Database` delegates every clause-storage
  operation to, so the database's actual persistence strategy is a
  pluggable choice rather than baked into `Episteme.Database` itself.
  Ships two implementations -- `Episteme.Database.Backends.Ets` (the
  default: an in-memory ETS table, indexed by `{name, arity}`) and
  `Episteme.Database.Backends.Dets` (the same shape, backed by a DETS
  file on disk, for a database that should survive past the owning
  process) -- and any third module implementing this behaviour works
  too: pass it as `Episteme.Database.new/1`'s `:backend` option.

  A backend only has to get one thing right: `replace_clauses/4` is the
  single write primitive every mutation in `Episteme.Database`
  (`add_clause/2`, `add_clause_first/2`, and `Episteme.Engine`'s
  `retract/1`/`retractall/1`) is built from, and `clauses_for/3` must
  return them back in exactly the order they were last written --
  clause-selection order is backtracking order, so a backend that
  reorders rows changes program behavior, not just performance.
  """

  @typedoc "Whatever a backend needs to find its own data again -- an ETS tid, a DETS table name, a pid, ..."
  @type state :: term()
  @type clause :: {head :: term(), body :: term()}

  @doc "Initializes fresh backend state from `opts` (backend-specific -- e.g. `:file` for `Episteme.Database.Backends.Dets`)."
  @callback init(keyword()) :: state()

  @doc "Every clause currently stored for `{name, arity}`, in declared/assert order."
  @callback clauses_for(state(), atom(), non_neg_integer()) :: [clause()]

  @doc "Replaces the entire clause list for `{name, arity}`."
  @callback replace_clauses(state(), atom(), non_neg_integer(), [clause()]) :: :ok

  @doc "Whether any clause has ever been stored for `{name, arity}` (including a since-emptied `retractall/1`)."
  @callback defined?(state(), atom(), non_neg_integer()) :: boolean()

  @doc "Completely removes `{name, arity}` from storage -- unlike `replace_clauses/4` with `[]`, `defined?/3` becomes false again afterward."
  @callback abolish(state(), atom(), non_neg_integer()) :: :ok

  @doc "Forces any buffered writes to durable storage. A no-op for a purely in-memory backend."
  @callback sync(state()) :: :ok

  @doc "Releases whatever resources the backend holds (an ETS table, an open DETS file, ...)."
  @callback close(state()) :: :ok
end
