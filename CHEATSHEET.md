# Cheatsheet

A quick, no-prose lookup table for everything Episteme understands —
both the plain Elixir functions you call directly, and the vocabulary
of questions/statements ("goals," below) the engine can answer. If
you're new to Episteme or to logic programming in general, read
[TUTORIAL.md](TUTORIAL.md) first — it explains all of this from
scratch, with plain-English walkthroughs; this page is for once you
already know the concepts and just need to remember the exact name or
argument order (for full detail and a worked example on any one row,
see [REFERENCE.md](REFERENCE.md); for complete programs, see
[EXAMPLES.md](EXAMPLES.md)). Every goal below is written `foo(A, B)`
style for readability; build it as an Elixir value the same way
[TUTORIAL.md](TUTORIAL.md) does — `%Compound{name: :foo, args: [a, b]}`.
Unlike real Prolog, goal names here are plain English words (`and`,
`or`, `not`, `unify`, ...), not ISO Prolog's punctuation operators
(`,`, `;`, `\+`, `=`, ...) — Episteme has no reader/text-syntax of its
own for those operators to be conventional *against*, so a name you can
actually remember won its case over matching ISO Prolog symbol-for-symbol.

## Terms used on this page

Skip this if you've read [TUTORIAL.md](TUTORIAL.md) already — it's the
same vocabulary, defined there at more length.

- **goal** — a statement or question you ask the engine to prove, e.g.
  "is Tom Bob's parent?"
- **fact** — a statement stored as unconditionally true.
- **rule** (also called a **clause**) — a statement stored as true
  *whenever some other goal holds*; a fact is really just a rule whose
  condition is always true.
- **variable** / **unbound** — a blank waiting to be filled in;
  "unbound" means the blank hasn't been filled in yet. "Binds" a
  variable means fills in that blank with a value.
- **unify** / **unification** — the core matching operation: given two
  values (possibly containing blanks), figure out how to fill in
  blanks on either side to make them identical, or fail if there's no
  way to. Almost everything below is built out of this one operation.
- **backtracking** — automatically undoing a choice and trying the next
  alternative when the current one doesn't lead anywhere; how the
  engine finds *every* answer, not just the first one it stumbles on.
- **cut-opaque** — a boundary a cut (`cut`, "commit to this choice, stop
  backtracking past this point" — see [TUTORIAL.md §6](TUTORIAL.md#6-cut-committing-to-a-choice))
  cannot reach through; a cut used inside a cut-opaque goal only
  affects choices made *inside* that goal, never the caller's own.
- **functor** — the name of a statement, together with how many fields
  it has (its **arity**) — `parent/2` is shorthand for "a statement
  named `parent` with 2 fields." A **predicate** is the same idea: "the
  `parent/2` predicate" means every fact and rule stored under that
  name and field count.
- **resolve** — look up what a variable currently points to (recursing
  into every nested variable too, for "fully/deeply resolve"); a
  "resolved" term has had every one of its filled-in blanks replaced
  with the actual value.

## Building terms (Elixir side)

| Prolog shape | Elixir |
|---|---|
| atom `foo` | `:foo` |
| integer `42` | `42` |
| float `3.14` | `3.14` |
| variable `X` | `Term.new_var("X")` (anonymous: `Term.new_var()`, name defaults to `"_"`) |
| compound `foo(A, B)` | `%Compound{name: :foo, args: [a, b]}` |
| list `[1, 2, 3]` | `[1, 2, 3]` (a native Elixir list) |
| list `[H\|T]` | `[h \| t]` |
| clause `foo(X) :- bar(X)` | `{%Compound{name: :foo, args: [x]}, %Compound{name: :bar, args: [x]}}` (a fact is `{head, true}`) |

## Running a query

| Call | Returns |
|---|---|
| `Episteme.query(goal, db)` | `{:ok, [solution, ...]}` (every solution, eagerly) or `{:error, term}` |
| `Episteme.query_once(goal, db)` | `{:ok, solution}`, `:none`, or `{:error, term}` |
| `Episteme.query_lazy(goal, db)` | `{stream, vars}` — pass to `next_solution/2` one at a time |
| `Episteme.next_solution(stream, vars)` | `{:solution, solution, rest}`, `:none`, or `{:error, term}` |

A `solution` is `%{"VarName" => resolved_term}` for every *named*
(non-`"_"`) variable that appeared in the query.

## Building a database

| Call | Effect |
|---|---|
| `Database.new(opts \\ [])` | Empty database. `opts[:backend]` defaults to `Backends.Ets`; pass `backend: Backends.Dets, file: path` for on-disk storage. |
| `Database.add_fact(db, head)` | Appends `{head, true}`. |
| `Database.add_clause(db, {head, body})` | Appends a rule. |
| `Database.add_clause_first(db, {head, body})` | Prepends (what `asserta/1` builds on). |
| `Database.consult_forms(db, forms)` | Bulk-loads `{:fact, head}` / `{:rule, head, body}` / `{:directive, _}` (ignored) forms. |
| `Database.clauses_for(db, name, arity)` | `[{head, body}, ...]`, in declared order. |
| `Database.defined?(db, name, arity)` | Whether the predicate has ever been declared (even if currently empty). |
| `Database.replace_clauses(db, name, arity, clauses)` | Overwrites the whole clause list — the primitive `retract`/`retractall` build on. |
| `Database.sync(db)` | Flushes to durable storage now (a no-op on the default ETS backend). |
| `Database.close(db)` | Releases the backend's resources (an open DETS file, an ETS table). |

## Control constructs

| Goal | Meaning |
|---|---|
| `true` | Always succeeds, once. |
| `fail` / `false` | Always fails. |
| `cut` | Commits to the current clause and every choice made since entering it. |
| `and(A, B)` | Conjunction. |
| `or(A, B)` | Disjunction. |
| `if_then_else(Cond, Then, Else)` | Commits to `Cond`'s first solution; runs `Then` if it has one, `Else` otherwise. |
| `if_then(Cond, Then)` | Like `if_then_else/3` with no `Else` — fails outright if `Cond` fails. |
| `not(G)` | Negation as failure: succeeds iff `G` has no solutions. Binds nothing. |
| `once(G)` | Commits to `G`'s first solution. |
| `call(G, Extra...)` | Calls `G` with `Extra` args appended; cut-opaque. |
| `findall(Template, G, List)` | Collects `Template` for every solution of `G` into `List` (`[]` if none). Cut-opaque, binds nothing else. |
| `forall(Cond, Action)` | Succeeds iff every solution of `Cond` has a solution of `Action`. Cut-opaque, binds nothing. |

## Matching and comparing values (unification)

| Goal | Meaning |
|---|---|
| `unify(A, B)` | Unify. |
| `not_unify(A, B)` | Succeeds iff `A` and `B` do *not* unify (binds nothing). |
| `equal(A, B)` | Structural equality on already-resolved terms (`equal(1, 1.0)` is false). |
| `not_equal(A, B)` | Structural inequality. |
| `order_less(A, B)`, `order_greater(A, B)` | Standard order of terms: `Var < Number < Atom < Compound` (real Prolog `@<`, `@>`). |
| `order_less_or_equal(A, B)`, `order_greater_or_equal(A, B)` | Real Prolog `@=<`, `@>=`. |
| `compare(Order, A, B)` | Unifies `Order` with `<`, `=`, or `>` per the standard order of terms. |
| `copy_term(Term, Copy)` | Unifies `Copy` with `Term`, every still-unbound variable renamed apart (sharing preserved). |

## Type checks

| Goal | True for |
|---|---|
| `var(X)` | An unbound variable. |
| `nonvar(X)` | Anything else. |
| `atom(X)` | A plain atom. |
| `atomic(X)` | An atom or number (not a variable, compound, or list). |
| `number(X)` | An integer or float. |
| `integer(X)` | An integer. |
| `float(X)` | A float. |
| `compound(X)` | A `%Compound{}` or a non-empty list. |
| `callable(X)` | An atom, `%Compound{}`, or non-empty list. |
| `is_list(X)` | A proper (nil-terminated) list. |
| `ground(X)` | No unbound variable anywhere in `X`, at any depth. |

## Term construction and inspection

| Goal | Meaning |
|---|---|
| `functor(Term, Name, Arity)` | `Term` bound: decomposes it. `Term` unbound: builds it from `Name`/`Arity` (`Arity` 0 unifies `Term` with `Name`; `Arity` > 0 needs an atom `Name`, builds fresh-variable args). |
| `arg(N, Term, Arg)` | `Arg` is `Term`'s `N`th argument, 1-based. Out of range fails, not an error. |
| `univ(Term, List)` | Real Prolog `=..`. `Term` bound: `List` = `[Name \| Args]` (or `[Term]` if atomic). `Term` unbound: builds `Term` from a fully-instantiated `List`. |

## Arithmetic

| Goal | Meaning |
|---|---|
| `X is Expr` | Evaluates `Expr`, unifies `X` with the result. |
| `numeric_equal(A, B)` | Numerically equal. |
| `numeric_not_equal(A, B)` | Numerically unequal. |
| `A < B`, `A > B` | Numeric ordering (kept as ordinary math symbols). |
| `less_or_equal(A, B)`, `greater_or_equal(A, B)` | Numeric ordering, inclusive. |
| `between(Low, High, X)` | `X` bound: checks `less_or_equal(Low, X)` and `less_or_equal(X, High)`. `X` unbound: enumerates every integer in `[Low, High]` on backtracking (no solutions if `Low > High`). `Low`/`High` are themselves arithmetic expressions. |

Evaluable functors for `is/2` and the comparisons above:

| Functor | Meaning |
|---|---|
| `+`, `-`, `*` | The usual, integer in, integer out unless a float is involved. |
| `/` | Integer division if it divides evenly, else float. |
| `//` | Integer floor division; `domain_error(non_zero, 0)` on divide by zero. |
| `mod` | Floored modulo (result has the divisor's sign); same zero-divisor error. |
| `rem` | Truncated remainder (result has the dividend's sign); same zero-divisor error. |
| `**`, `^` | Power. Integer base/non-negative integer exponent stays integer; anything else is a float. |
| `abs(X)` | Absolute value. |
| `sign(X)` | `1`, `-1`, or `0`. |
| `min(A, B)`, `max(A, B)` | The usual. |
| `sqrt(X)` | Always a float. |
| unary `-X`, `+X` | Negation / identity. |

## Exceptions

| Goal | Meaning |
|---|---|
| `throw(Term)` | Raises a Prolog exception carrying `Term`. |
| `catch(Goal, Catcher, Recovery)` | Runs `Goal`; if it throws a ball that unifies with `Catcher`, runs `Recovery` with that unification in place. |
| `type_error(Type, Culprit)` | Throws `error(type_error(Type, Culprit), _)`. |
| `domain_error(Domain, Culprit)` | Throws `error(domain_error(Domain, Culprit), _)`. |
| `instantiation_error` | Throws `error(instantiation_error, _)`. |

Thrown automatically:
- An unbound variable anywhere a goal or an arithmetic expression is
  evaluated → `instantiation_error`.
- Calling a predicate with no clauses *and no prior `assert`/`retractall`
  declaring it* → `error(existence_error(procedure, Name/Arity), _)`.
- An unrecognized arithmetic functor, or a non-numeric operand → `error(type_error(evaluable, _), _)`.

An uncaught throw surfaces from `Episteme.query/2` as `{:error, term}`
rather than escaping as a raw Elixir exception.

## Dynamic database

| Goal | Meaning |
|---|---|
| `assertz(Clause)` / `assert(Clause)` | Appends `Clause` (a bare term is a fact; `Head :- Body` a rule). Unbound variables in `Clause` become that stored clause's own private variables. |
| `asserta(Clause)` | Same, but prepends. |
| `retract(Clause)` | Removes the *first* stored clause whose head and body both unify with `Clause`; keeps the resulting bindings. Fails (no mutation) if nothing unifies. Deterministic on success — does not backtrack into further matches. |
| `retractall(Head)` | Removes every clause whose head unifies with `Head`. Always succeeds, binds nothing, and — like real Prolog — leaves the predicate *defined* (with zero clauses) rather than undefined, so later calls fail rather than raising `existence_error`. |

Effects are visible immediately to every later call against the same
`Database.t()`, including from separate `Episteme.query/2` calls, and are
**not** undone by backtracking.

## Lists

| Goal | Meaning |
|---|---|
| `length(List, N)` | Either direction: `List` bound gives `N`; `N` bound (with `List` unbound) builds a list of `N` fresh variables. |
| `append(A, B, C)` | `C = A ++ B`. With `A` unbound and `C` bound, enumerates every split of `C` on backtracking. |
| `member(X, List)` | Enumerates every element of `List` on backtracking. |
| `reverse(A, B)` | Either direction. |
| `nth0(Index, List, Elem)` | 0-based. `Index` unbound enumerates every `{index, element}` pair. |
| `nth1(Index, List, Elem)` | 1-based, same modes as `nth0/3`. |
| `last(List, Elem)` | Fails on `[]`. |
| `msort(List, Sorted)` | Sorts by standard order of terms, keeps duplicates. |
| `sort(List, Sorted)` | Sorts and removes duplicates (`compare/3 == =`, not plain `==`). |
| `permutation(List, Perm)` | Enumerates every reordering, `N!` of them. `List` must be bound. |
| `sum_list(List, Sum)` | `Sum = 0` for `[]`. |
| `max_list(List, Max)`, `min_list(List, Min)` | Fail on `[]`. |
| `list_to_set(List, Set)` | Dedups, keeps first-occurrence order (unsorted). |

## Higher-order list predicates

`Goal` is called via the same mechanism as `call/N`, once per element
(or per row, across lists in lockstep), cut-opaque.

| Goal | Meaning |
|---|---|
| `include(Goal, List, Kept)` | Elements where `call(Goal, Elem)` succeeds. |
| `exclude(Goal, List, Kept)` | Elements where it doesn't. |
| `foldl(Goal, List, V0, V)` (also `/5`, `/6` for 2–3 lists) | Threads an accumulator: `call(Goal, Elem, AccIn, AccOut)` per element. |
| `maplist(Goal, List1, ..., ListN)` | Succeeds iff `call(Goal, E1_i, ..., EN_i)` succeeds for every row. At least one list must be bound; others get built fresh. |

## I/O

| Goal | Meaning |
|---|---|
| `write(Term)` | Prints canonical `functor(args)` text (via `Term.to_text/1`), no trailing newline. |
| `writeln(Term)` | Same, with a trailing newline. |
| `print(Term)` | Same as `write/1`. |
| `nl` | Prints a newline. |

No operator-aware pretty-printing (e.g. `1+2` prints as `+(1, 2)`) — a
front-end reader is where that would live.

## `Episteme.Term` (Elixir side)

| Function | Meaning |
|---|---|
| `Term.new_var(name \\ "_")` | A fresh logic variable. |
| `Term.resolve_deep(term, bindings)` | Fully resolves `term` and every value nested inside it. |
| `Term.fresh_copy(term)` | Renames every variable in `term` apart, preserving sharing. |
| `Term.structurally_equal?(a, b)` | Same shape/value on two already-resolved terms; an integer never equals a float. |
| `Term.to_text(term)` | Canonical `functor(args)` text for an already-resolved term. |
