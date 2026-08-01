# Episteme

A standalone Prolog-like resolution engine and clause database for
Elixir — terms, unification, SLD-resolution, backtracking, a genuine
clause-scoped cut, and a small builtin-predicate set, on top of
[Ichor](https://hex.pm/packages/ichor)'s search substrate. No parser,
no concrete surface syntax, no dependency on one: build a database and
goal terms directly, or put a reader on top (real Prolog syntax is
exactly what [Aletheia](https://hex.pm/packages/aletheia) — the
sibling project this split out of — puts on top of Episteme).

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
     %Compound{name: :",", args: [
       %Compound{name: :parent, args: [x, y]},
       %Compound{name: :parent, args: [y, z]}
     ]}}
  )

Episteme.query(%Compound{name: :grandparent, args: [tom, Term.new_var("Who")]}, db)
#=> {:ok, [%{"Who" => :ann}]}
```

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
         │              built directly or via consult_forms/2
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
- **`Episteme.Database`** — clause storage, indexed by `{name, arity}`.
- **`Episteme.Engine`** — the resolution engine: clause selection,
  subgoal sequencing, and control constructs (`,`/`;`/`->`/`!`/`\+`/
  `call/N`/`once/1`) over `Ichor.Backtrack`, plus a real clause-scoped
  cut (not a `once/1` stand-in — see the moduledoc on `Episteme.Engine`
  for why that distinction is load-bearing).
- **`Episteme.Builtins.*`** — arithmetic, exceptions, the list
  predicate family, and minimal I/O.

Episteme depends on [`ichor_runtime`](https://hex.pm/packages/ichor_runtime)
as its one real dependency (`Ichor.Backtrack`, `Ichor.Toolkit.TermWalk`).
It has no reader or grammar of its own, so — unlike Aletheia — `ichor`
(the Aether front-end, codegen) never appears here at all.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix docs
```

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

MIT — see [LICENSE](LICENSE).
