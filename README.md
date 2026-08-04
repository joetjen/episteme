# Episteme

**New to logic programming?** This README assumes some familiarity
with Prolog-style terminology (facts, rules, unification,
backtracking...) since it's written for evaluating Episteme as a
dependency. [TUTORIAL.md](TUTORIAL.md) explains every one of those
terms from scratch, with plain-English walkthroughs and no assumed
background at all — start there instead if any of the paragraph below
is unfamiliar.

A standalone Prolog-like resolution engine and clause database for
Elixir: you store **facts** and **rules** (statements, and statements
that hold whenever some other statement does), ask **goals** (questions)
against them, and get back every answer the engine can find by
searching through what it knows and automatically trying alternatives
(**backtracking**) when one path doesn't work out. Concretely, that's
terms, unification (the core "make these two things match, filling in
any blanks as needed" operation), backtracking search, a genuine
clause-scoped cut (a real "commit to this choice" control construct,
not an approximation of one), a dynamic database (`assert`/`retract`),
solution aggregation (`findall`/`forall`), and a small builtin-predicate
set, on top of [Ichor](https://hex.pm/packages/ichor)'s search
substrate. No parser, no concrete surface syntax, no dependency on one:
build a database and goal terms directly, or put a reader on top (real
Prolog syntax is exactly what [Aletheia](https://hex.pm/packages/aletheia)
— the sibling project this split out of — puts on top of Episteme).

```elixir
alias Episteme.{Database, Term}
alias Episteme.Term.Compound

tom = :tom
{x, y, z} = {Term.new_var("X"), Term.new_var("Y"), Term.new_var("Z")}

db =
  Database.new()
  |> Database.add_fact(%Compound{name: :parent, args: [tom, :bob]})
  |> Database.add_fact(%Compound{name: :parent, args: [:bob, :ann]})
  |> Database.add_clause(
    {%Compound{name: :grandparent, args: [x, z]},
     %Compound{name: :and, args: [
       %Compound{name: :parent, args: [x, y]},
       %Compound{name: :parent, args: [y, z]}
     ]}}
  )

Episteme.query(%Compound{name: :grandparent, args: [tom, Term.new_var("Who")]}, db)
#=> {:ok, [%{"Who" => :ann}]}
```

## Documentation

- **[TUTORIAL.md](TUTORIAL.md)** — a from-scratch, step-by-step
  walkthrough. Start here if you're new to Episteme.
- **[REFERENCE.md](REFERENCE.md)** — every control construct,
  comparison, type check, arithmetic feature, and exception/database/
  list/I/O predicate, in full detail with a verified example each.
- **[EXAMPLES.md](EXAMPLES.md)** — complete, verified-runnable programs
  (a family tree, graph reachability, a key-value store, FizzBuzz, and
  more).
- **[CHEATSHEET.md](CHEATSHEET.md)** — every predicate and Elixir-side
  function, one page, for once you know your way around ([REFERENCE.md](REFERENCE.md)
  is the page behind each row of it).
- **[CHANGELOG.md](CHANGELOG.md)** — release history.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — workflow, commit style, what
  has to pass before a change lands.
- **[LICENSE](LICENSE)** — MIT.

## Why a separate package from Aletheia

Aletheia is the embedded-Prolog-*syntax* half — `:-`, `,`/`;`, `=`, the
standard operator table, a reader built on `Ichor.Toolkit.Pratt`.
Episteme is everything underneath that a concrete syntax never actually
needed: the term representation, unification and backtracking, clause
storage, SLD-resolution, cut, and the builtin-predicate set. Splitting
them means anyone who wants a Prolog-like rule engine/query layer in
Elixir — without buying into Aletheia's `.alp` syntax at all — can
depend on Episteme alone.

## Installation

Not yet published to Hex. For now, add it as a path or git dependency
alongside a checkout of this repository:

```elixir
def deps do
  [
    {:episteme, path: "../episteme"}
  ]
end
```

## How it fits together

```text
   Database.t()  ──── clause storage: {name, arity} -> [{head, body}, ...],
         │              indexed + mutated via a pluggable Database.Backend
         │              (Backends.Ets by default, Backends.Dets for
         │              on-disk persistence); built directly, via
         │              consult_forms/2, or at runtime via assert/retract
         ▼
   Episteme.query/2 (or query_once/2, query_lazy/2 + next_solution/2)
         │
         ▼
   Episteme.Engine  ──── SLD-resolution over Ichor.Backtrack.Tree/
         │                Bindings, cut-barrier mechanism, builtin
         │                predicate dispatch (Episteme.Builtins.*)
         ▼
      solutions
```

- **`Episteme.Term`** — the term representation: atoms/numbers are
  plain Elixir atoms/integers/floats, lists are native Elixir lists
  (decomposing as ISO's own `'.'/2` cons functor so unification can
  recurse into them), variables and compounds get dedicated structs.
- **`Episteme.Database`** — clause storage, indexed by `{name, arity}`,
  storage strategy pluggable via `Episteme.Database.Backend` (in-memory
  ETS by default, on-disk DETS built in, bring your own by implementing
  the behaviour).
- **`Episteme.Engine`** — the resolution engine: clause selection,
  subgoal sequencing, control constructs (`and`/`or`/`if_then`/
  `if_then_else`/`cut`/`not`/`call/N`/`once/1` — plain English names,
  not real Prolog's `,`/`;`/`->`/`!`/`\+`, since there's no reader here
  for that punctuation to be conventional syntax against) over
  `Ichor.Backtrack`, plus a real clause-scoped cut (not a `once/1`
  stand-in — see the moduledoc on `Episteme.Engine` for why that
  distinction is load-bearing), a dynamic database (`assert/1`,
  `asserta/1`, `assertz/1`, `retract/1`, `retractall/1`), and solution
  aggregation (`findall/3`, `forall/2`).
- **`Episteme.Builtins.*`** — arithmetic (plus `between/3`), exceptions,
  the list predicate family, and minimal I/O.

Episteme depends on [`ichor_runtime`](https://hex.pm/packages/ichor_runtime)
as its one real dependency (`Ichor.Backtrack`, `Ichor.Toolkit.TermWalk`).
It has no reader or grammar of its own, so — unlike Aletheia — `ichor`
(the Aether front-end, codegen) never appears here at all.

## Dynamic database and solution aggregation

`assertz/1`/`asserta/1` (`assert/1` is an alias for `assertz/1`) add a
clause at runtime — a bare term is a fact, `Head :- Body` a rule —
`retract/1` removes the first stored clause whose head *and* body unify
with its argument, and `retractall/1` removes every clause whose head
unifies with its argument (always succeeds, even against an undefined
predicate). Effects are immediately visible to every subsequent call
against the same `Database.t()`, including from separate `Episteme.query/2`
calls — not undone by backtracking, exactly like real Prolog:

```elixir
db = Database.new()
Episteme.query(%Compound{name: :assertz, args: [%Compound{name: :fact, args: [1]}]}, db)
Episteme.query(%Compound{name: :fact, args: [Term.new_var("X")]}, db)
#=> {:ok, [%{"X" => 1}]}
```

`findall/3` collects every solution's template into a list (`[]` if
there are none); `forall/2` succeeds iff every solution of its first
goal has at least one solution of its second. Both are cut-opaque and
bind nothing outside themselves, same as `not/1`.

## Storage backends

`Database.new/1` takes a `:backend` option — `Episteme.Database.Backends.Ets`
(the default: in-memory, indexed by `{name, arity}`) or
`Episteme.Database.Backends.Dets` (the same shape, persisted to a file,
so a database survives past the process or the VM that built it):

```elixir
db = Database.new(backend: Episteme.Database.Backends.Dets, file: "facts.dets")
# ... assert/consult as usual ...
Database.sync(db)   # flush to disk now, rather than whenever :dets gets to it
Database.close(db)  # release the file handle
```

Because a `Database.t()` now wraps a mutable resource rather than being
a plain immutable value, call `Database.close/1` when you're done with
one you don't want to leak (an ETS-backed database is cleaned up
automatically if its owning process exits; a DETS-backed one holds an
open file handle until closed). Any other storage strategy — an Agent,
a remote store, whatever a given deployment needs — is a matter of
implementing `Episteme.Database.Backend`'s five callbacks and passing
that module as `:backend`.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix docs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow (git flow
branching, commit style, what `mix precommit` runs, and what to update
when adding a new predicate).
