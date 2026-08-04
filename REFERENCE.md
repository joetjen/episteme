# Reference

A complete, detailed reference for every control construct, comparison
operator, type check, arithmetic feature, exception-handling predicate,
database-mutation predicate, list predicate, and I/O predicate Episteme
understands — one entry per feature, each with a full explanation and a
verified, runnable example. If [CHEATSHEET.md](CHEATSHEET.md) is the
one-page lookup table, this is the page behind each row of it.

No prior Prolog or logic-programming background is assumed — read
[TUTORIAL.md](TUTORIAL.md) first if terms like "unify," "backtracking,"
or "cut" are new to you; this document builds on the vocabulary that
one introduces rather than re-explaining it from scratch every time.
[EXAMPLES.md](EXAMPLES.md) has complete worked programs instead of
one-feature-at-a-time snippets.

Every example below was actually executed against this version of
Episteme — the shown result is real, captured output, not hand-derived.
Paste any of them into `iex -S mix` from a checkout of this repository
with this in scope first:

```elixir
alias Episteme.{Database, Term}
alias Episteme.Term.Compound
c = fn name, args -> %Compound{name: name, args: args} end
```

## Contents

- [Control constructs](#control-constructs) — `true`, `fail`/`false`,
  `cut`, `and`, `or`, `if_then`/`if_then_else`, `not`, `once`, `call`,
  `findall`, `forall`
- [Matching and comparing values](#matching-and-comparing-values) —
  `unify`, `not_unify`, `equal`, `not_equal`, standard order of terms
  (`order_less`, `order_greater`, `order_less_or_equal`,
  `order_greater_or_equal`, `compare`), `copy_term`
- [Type checks](#type-checks) — `var`, `nonvar`, `atom`, `atomic`,
  `number`, `integer`, `float`, `compound`, `callable`, `is_list`,
  `ground`
- [Term construction and inspection](#term-construction-and-inspection)
  — `functor`, `arg`, `univ`
- [Arithmetic](#arithmetic) — `is`, comparisons, `between`, every
  evaluable functor
- [Exceptions](#exceptions) — `throw`, `catch`, `type_error`,
  `domain_error`, `instantiation_error`, and what's raised automatically
- [Dynamic database](#dynamic-database) — `assert`, `asserta`,
  `assertz`, `retract`, `retractall`
- [Lists](#lists) — `length`, `append`, `member`, `reverse`, `nth0`,
  `nth1`, `last`, `msort`, `sort`, `permutation`, `sum_list`,
  `max_list`, `min_list`, `list_to_set`
- [Higher-order list predicates](#higher-order-list-predicates) —
  `include`, `exclude`, `foldl`, `maplist`
- [I/O](#io) — `write`, `writeln`, `print`, `nl`

A note before diving in: every goal name below is a plain English word
(`and`, `or`, `unify`, ...), not real Prolog's punctuation operator
(`,`, `;`, `=`, ...) for the same idea. Episteme has no reader of its
own for any of that punctuation to be conventional syntax *against* —
see `Episteme`'s moduledoc — so each entry below names the traditional
Prolog operator once, for readers coming from Prolog, and then never
uses it again.

---

## Control constructs

### `true`

Always succeeds, exactly once, binding nothing. The "do nothing, just
say yes" goal — useful as a rule body that should always hold, or as
the `Then`/`Else` half of an if-then(-else) you don't need to do
anything in.

```elixir
Episteme.query(true, Database.new())
#=> {:ok, [%{}]}
```

### `fail` / `false`

Always fails — zero answers, immediately. `fail` and `false` are
interchangeable (both are recognized directly by the engine); useful
for forcing backtracking on purpose, or as an explicit "this branch
never holds."

```elixir
Episteme.query(:fail, Database.new())
#=> {:ok, []}

Episteme.query(false, Database.new())
#=> {:ok, []}
```

### `cut` (real Prolog: `!`)

Commits to the current rule and to *every choice already made* since
entering it — not just "don't explore any further alternatives from
here forward," but "give up every alternative already taken to get
this far, even ones that already looked like they were working." See
[TUTORIAL.md §6](TUTORIAL.md#6-cut-committing-to-a-choice) for the full
walkthrough of why that distinction matters; the short version, the
textbook example:

```elixir
db =
  Database.new()
  |> Database.add_clause({:p, c.(:and, [:cut, :fail])})
  |> Database.add_clause({:p, true})

Episteme.query(:p, db)
#=> {:ok, []}
```

The second clause (`p` holds unconditionally) never runs — the `cut` in
the first clause already ruled it out as an alternative, before `fail`
even executes. A cut also prunes any choice points from goals that
already *succeeded* earlier in the same rule body, not just the clause
selection itself:

```elixir
x = Term.new_var("X")

db =
  Database.new()
  |> Database.add_clause(
    {c.(:r, [x]), c.(:or, [c.(:and, [c.(:unify, [x, 1]), :cut]), c.(:unify, [x, 2])])}
  )
  |> Database.add_fact(c.(:r, [3]))

Episteme.query(c.(:r, [Term.new_var("X")]), db)
#=> {:ok, [%{"X" => 1}]}
```

Without the `cut`, asking for every `r(X)` would find `1`, `2`, and `3`.
With it, choosing `X = 1` inside the `or` commits to that choice —
pruning both the `X = 2` alternative in the same disjunction *and* the
`r(3)` fact from the second clause — leaving only one answer.

A cut is scoped to the one rule it appears in: it can never reach
backward into whatever *called* that rule and prune the caller's own
choices. `call/N`, `once/1`, `not/1`, `findall/3`, and `forall/2` are
all "cut-opaque" for exactly this reason — see each entry below.

### `and/2` — conjunction (real Prolog: `,`)

`and(A, B)` succeeds for every combination of a solution to `A`
followed by a solution to `B`, with `B` solved under whatever `A` just
bound. This is how a rule body sequences multiple conditions that all
have to hold at once.

```elixir
x = Term.new_var("X")
y = Term.new_var("Y")

Episteme.query(c.(:and, [c.(:unify, [x, 1]), c.(:unify, [y, 2])]), Database.new())
#=> {:ok, [%{"X" => 1, "Y" => 2}]}
```

### `or/2` — disjunction (real Prolog: `;`)

`or(A, B)` succeeds for every solution of `A`, *then* every solution of
`B` — in that order, both explored, not just "whichever comes first."

```elixir
x = Term.new_var("X")
Episteme.query(c.(:or, [c.(:unify, [x, 1]), c.(:unify, [x, 2])]), Database.new())
#=> {:ok, [%{"X" => 1}, %{"X" => 2}]}
```

### `if_then_else/3` and `if_then/2` (real Prolog: `(Cond -> Then ; Else)`)

`if_then_else(Cond, Then, Else)` commits to `Cond`'s *first* solution
only (if it has one, `Else` is never even considered) and runs `Then`
under those bindings; if `Cond` has no solution at all, runs `Else`
instead, under the *original* bindings. Exactly one of `Then`/`Else`
ever runs.

```elixir
x = Term.new_var("X")
r = Term.new_var("R")

body =
  c.(:if_then_else, [c.(:>, [x, 0]), c.(:unify, [r, :pos]), c.(:unify, [r, :non_pos])])

db = Database.add_clause(Database.new(), {c.(:classify, [x, r]), body})

Episteme.query(c.(:classify, [5, Term.new_var("R")]), db)
#=> {:ok, [%{"R" => :pos}]}

Episteme.query(c.(:classify, [-5, Term.new_var("R")]), db)
#=> {:ok, [%{"R" => :non_pos}]}
```

`if_then(Cond, Then)` — no `Else` at all — is if-then with an implicit
"otherwise fail": the whole thing fails if `Cond` has no solution,
rather than falling through to anything:

```elixir
x = Term.new_var("X")
db = Database.add_clause(Database.new(), {c.(:t, [x]), c.(:if_then, [c.(:>, [x, 0]), true])})

Episteme.query(c.(:t, [1]), db)
#=> {:ok, [%{}]}

Episteme.query(c.(:t, [-1]), db)
#=> {:ok, []}
```

### `not/1` — negation as failure (real Prolog: `\+`)

`not(Goal)` succeeds exactly when `Goal` has *no* solutions — it's a
yes/no check for the absence of a proof, not a search that could
produce bindings. It never binds anything, even a variable `Goal`
itself would have bound on its way to failing, and it's cut-opaque (a
`cut` inside `Goal` never affects whatever called `not/1`).

```elixir
x = Term.new_var("X")
db = Database.add_clause(Database.new(), {c.(:even, [x]), c.(:is, [0, c.(:mod, [x, 2])])})

Episteme.query(c.(:not, [c.(:even, [3])]), db)
#=> {:ok, [%{}]}

Episteme.query(c.(:not, [c.(:even, [4])]), db)
#=> {:ok, []}
```

### `once/1`

Commits to `Goal`'s *first* solution and discards the rest — like
wrapping `Goal` in "just give me one answer, I don't care if there
would have been more." Cut-opaque: a `cut` inside `Goal` commits within
`Goal` itself but can't reach past `once/1` to prune the caller's own
choices.

```elixir
Episteme.query(c.(:once, [c.(:member, [Term.new_var("X"), [1, 2, 3]])]), Database.new())
#=> {:ok, [%{"X" => 1}]}
```

Contrast with a plain `member(X, [1,2,3])`, which would give three
answers (`X = 1`, `X = 2`, `X = 3`) — `once/1` throws the other two away
before you ever see them.

### `call/N`

`call(Goal, Extra1, Extra2, ...)` runs `Goal` with the extra arguments
appended to it — if `Goal` is already a statement with some fields
(`foo(A, B)`), the extras get tacked onto the end (`foo(A, B, Extra1,
Extra2, ...)`); if `Goal` is a bare atom, the extras become its fields.
Cut-opaque, same as `once/1`. This is how you call a goal built or
passed around dynamically, with additional arguments decided at the
call site rather than baked into the goal itself.

```elixir
Episteme.query(c.(:call, [:writeln, :hello]), Database.new())
#=> prints "hello", then {:ok, [%{}]}
```

A more telling example — calling a *partially applied* goal, one field
short, and having `call/N` fill in the rest:

```elixir
x = Term.new_var("X")
Episteme.query(c.(:call, [c.(:unify, [x]), 5]), Database.new())
#=> {:ok, [%{"X" => 5}]}
```

`unify(X)` on its own is `unify` with only one field — not a valid goal
by itself — but `call(unify(X), 5)` appends `5`, turning it into
`unify(X, 5)`, which unifies `X` with `5`.

### `findall/3`

`findall(Template, Goal, List)` finds *every* solution of `Goal`
(cut-opaque, and doesn't leave any of `Goal`'s own bindings in place
afterward) and collects what `Template` came out to under each one,
into `List`. Zero matches gives `List = []` — a normal answer, not a
failure.

```elixir
db = Database.new() |> Database.add_fact(c.(:fruit, [:apple])) |> Database.add_fact(c.(:fruit, [:pear]))
fx = Term.new_var()

Episteme.query(c.(:findall, [fx, c.(:fruit, [fx]), Term.new_var("L")]), db)
#=> {:ok, [%{"L" => [:apple, :pear]}]}
```

(`fx` is anonymous — `Term.new_var/0` — because it's only used inside
`findall/3`'s own template/goal; see [TUTORIAL.md §11](TUTORIAL.md#11-collecting-every-solution-findall-and-forall)
for why a *named* variable used only there would come back in the
answer too, still unfilled.)

### `forall/2`

`forall(Cond, Action)` is a yes/no check, not a collector: it succeeds
iff *every* solution of `Cond` has at least one solution of `Action`.
Both are cut-opaque, and neither leaves any bindings behind — like
`not/1`, this only ever tells you whether something held, never what it
was.

```elixir
db = Database.new() |> Database.add_fact(c.(:fruit, [:apple])) |> Database.add_fact(c.(:fruit, [:pear]))
fx = Term.new_var()

Episteme.query(c.(:forall, [c.(:fruit, [fx]), c.(:atom, [fx])]), db)
#=> {:ok, [%{}]}
```

"Is every stored fruit an atom?" — yes, both `:apple` and `:pear` are.

---

## Matching and comparing values

### `unify/2` (real Prolog: `=`)

`unify(A, B)` is the core operation everything else is built from: try
to make `A` and `B` identical by filling in any unbound variables on
either side as needed, succeeding once if that's possible, failing if
it isn't (e.g. two different atoms, or two compounds with different
names/field counts).

```elixir
Episteme.query(c.(:unify, [Term.new_var("X"), c.(:foo, [1, 2])]), Database.new())
#=> {:ok, [%{"X" => %Episteme.Term.Compound{name: :foo, args: [1, 2]}}]}
```

### `not_unify/2` — cannot unify (real Prolog: `\=`)

`not_unify(A, B)` succeeds exactly when `unify(A, B)` would *fail* —
and, like `not/1`, never binds anything, even along the way. An unbound
variable unifies with anything, so `not_unify/2` involving one only
succeeds once that variable is already bound to something genuinely
incompatible.

```elixir
Episteme.query(c.(:not_unify, [1, 2]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:not_unify, [1, 1]), Database.new())
#=> {:ok, []}
```

### `equal/2` — structural equality (real Prolog: `==`)

`equal(A, B)` checks whether two *already-resolved* terms have exactly
the same shape and value — unlike `unify/2`, it never fills in any
blanks; if either side is still an unbound variable, they're only equal
if it's literally the same variable. Numbers compare by type as well as
value: an integer is never `equal` to a float with the same numeric
value.

```elixir
Episteme.query(c.(:equal, [1, 1.0]), Database.new())
#=> {:ok, []}

Episteme.query(c.(:equal, [c.(:foo, [1]), c.(:foo, [1])]), Database.new())
#=> {:ok, [%{}]}
```

### `not_equal/2` — structural inequality (real Prolog: `\==`)

The opposite of `equal/2` — succeeds exactly when `equal/2` would fail.

```elixir
Episteme.query(c.(:not_equal, [1, 1.0]), Database.new())
#=> {:ok, [%{}]}
```

### Standard order of terms: `order_less/2`, `order_greater/2`, `order_less_or_equal/2`, `order_greater_or_equal/2` (real Prolog: `@<`, `@>`, `@=<`, `@>=`), and `compare/3`

A total order over *every* term, not just numbers — `Var < Number <
Atom < Compound`. Within a class: variables order by reference identity
(consistent within one run, arbitrary across runs); numbers by value,
with a float sorting before an integer of equal value (so `1.0` and
`1`, unlike `equal/2`'s `==`, are never `order`-equal either — they
just consistently sort float-before-int instead); atoms alphabetically
by character code; compounds (a non-empty list decomposes via the same
`'.'/2` cons functor used everywhere else) by arity first, then
functor name, then arguments left to right. `compare/3` is the one
member of this family whose own name isn't ISO punctuation, so it
keeps its ISO name unchanged: `compare(Order, A, B)` unifies `Order`
with the atom `<`, `=`, or `>`.

```elixir
Episteme.query(c.(:order_less, [1.0, 1]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:compare, [Term.new_var("O"), :a, :b]), Database.new())
#=> {:ok, [%{"O" => :<}]}

Episteme.query(
  c.(:compare, [Term.new_var("O"), c.(:f, [1]), c.(:f, [1, 2])]),
  Database.new()
)
#=> {:ok, [%{"O" => :<}]}   -- arity 1 sorts before arity 2, regardless of args
```

### `copy_term/2`

`copy_term(Term, Copy)` unifies `Copy` with a version of `Term` that
has every one of `Term`'s still-unbound variables renamed apart to
brand-new ones — any *sharing* between variables in `Term` (the same
variable appearing more than once) is preserved in `Copy`, just with
fresh identities. Already-bound parts of `Term` come through unchanged.
This is the same "rename apart" operation the engine itself does every
time it uses a stored rule, exposed as a goal you can call directly.

```elixir
x = Term.new_var("X")
Episteme.query(c.(:copy_term, [c.(:f, [x, x]), Term.new_var("Y")]), Database.new())
#=> one answer: "X" is the original, still-unbound X, and "Y" is a
#   fresh f(A, A) -- a brand-new variable A, appearing in both fields
#   of Y because X appeared in both fields of the original term, but
#   a *different* variable from X itself
```

---

## Type checks

Each of these is a yes/no question about what kind of value something
currently is — none of them ever bind anything, and none of them wait
around for a variable to become bound (an unbound variable is simply
not any of these things, except `var/1` itself).

### `var/1` and `nonvar/1`

`var(X)` succeeds iff `X` is still an unbound variable; `nonvar/1` is
the opposite.

```elixir
Episteme.query(c.(:var, [Term.new_var("X")]), Database.new())
#=> one answer, with "X" bound to itself -- it's still unbound, so the
#   answer reports what it is: an unresolved variable, same as asking
#   ?- var(X). at a real Prolog toplevel

Episteme.query(c.(:var, [:foo]), Database.new())
#=> {:ok, []}

Episteme.query(c.(:nonvar, [:foo]), Database.new())
#=> {:ok, [%{}]}
```

### `atom/1`

True for a plain atom (`:foo`, `:tom`, `[]`) — false for numbers,
compounds, non-empty lists, and unbound variables.

```elixir
Episteme.query(c.(:atom, [:foo]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:atom, [1]), Database.new())
#=> {:ok, []}
```

### `atomic/1`

True for an atom *or* a number — anything with no internal structure to
speak of. False for compounds, non-empty lists, and unbound variables.

```elixir
Episteme.query(c.(:atomic, [1]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:atomic, [c.(:foo, [1])]), Database.new())
#=> {:ok, []}
```

### `number/1`, `integer/1`, `float/1`

`number/1` is true for either an integer or a float; `integer/1` and
`float/1` narrow to exactly one of those.

```elixir
Episteme.query(c.(:number, [3.14]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:integer, [3.14]), Database.new())
#=> {:ok, []}

Episteme.query(c.(:float, [3.14]), Database.new())
#=> {:ok, [%{}]}
```

### `compound/1`

True for a statement-with-fields (a `%Compound{}`) *or* a non-empty
list (a list is really a chain of two-field compounds under the hood —
see [TUTORIAL.md §2](TUTORIAL.md#2-terms-the-building-blocks-of-a-fact)).
False for `[]` — the empty list counts as an atom-like value, not a
compound, the same as real Prolog.

```elixir
Episteme.query(c.(:compound, [c.(:foo, [1])]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:compound, [[1, 2]]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:compound, [[]]), Database.new())
#=> {:ok, []}
```

### `callable/1`

True for anything that could sensibly be used as a goal on its own: an
atom, a compound, or a non-empty list. False for numbers and unbound
variables.

```elixir
Episteme.query(c.(:callable, [:foo]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:callable, [1]), Database.new())
#=> {:ok, []}
```

### `is_list/1`

True for a *proper* list — one that ends in `[]`, however deep. False
for a partial list (one ending in a variable or some other non-list
value, e.g. `[1 | X]` or `[1 | foo]`), and false for anything that
isn't a list at all.

```elixir
Episteme.query(c.(:is_list, [[1, 2, 3]]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:is_list, [:foo]), Database.new())
#=> {:ok, []}
```

---

### `ground/1`

True iff `Term` contains no unbound variable anywhere, at any depth —
resolves deeply first, so a variable that's already bound to a ground
term counts as ground too.

```elixir
Episteme.query(c.(:ground, [c.(:f, [1, [2, 3]])]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:ground, [c.(:f, [1, Term.new_var("X")])]), Database.new())
#=> {:ok, []}
```

---

## Term construction and inspection

### `functor/3`

`functor(Term, Name, Arity)` relates a term to its outermost
name/arity, and works in both directions:

- **`Term` bound** — decomposes it. A compound gives its own name and
  argument count; an atomic term (atom or number) gives itself as
  `Name` with `Arity` 0. A non-empty list decomposes via the same
  `'.'/2` cons functor `Term.compound?/1` uses everywhere else (`Name`
  = `.`, `Arity` = 2); `[]` is atomic, same as any other atom.
- **`Term` unbound** — builds a fresh term from `Name`/`Arity` instead.
  `Arity` 0 just unifies `Term` with `Name` as-is (whatever atomic
  value it is); `Arity` > 0 requires `Name` to be an atom and builds a
  compound of that many brand-new, independent variables.

```elixir
Episteme.query(
  c.(:functor, [c.(:foo, [:a, :b, :c]), Term.new_var("F"), Term.new_var("A")]),
  Database.new()
)
#=> {:ok, [%{"A" => 3, "F" => :foo}]}

Episteme.query(c.(:functor, [Term.new_var("T"), :foo, 2]), Database.new())
#=> one answer: "T" is a fresh foo(A, B), A and B independent fresh variables
```

A non-atom `Name` with `Arity` > 0 raises `type_error(atom, Name)`; an
unbound `Term` with an unbound `Name` or `Arity` raises
`instantiation_error`.

### `arg/3`

`arg(N, Term, Arg)` — `Arg` is `Term`'s `N`th argument, 1-based.
`Term` must already be bound and compound (`type_error(compound,
Term)` otherwise); `N` must be bound to an integer (`type_error(integer,
N)` otherwise). `N` out of range (less than 1, or more than `Term`'s
arity) just fails, the same as `nth0/3`/`nth1/3` do for an
out-of-range index — not an error.

```elixir
Episteme.query(c.(:arg, [2, c.(:foo, [:a, :b, :c]), Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => :b}]}
```

### `univ/2` (real Prolog: `=..`)

`univ(Term, List)` relates a term to a list of its name followed by
its arguments — the same decompose/construct duality as `functor/3`,
just carrying the whole argument list at once instead of counting it.

- **`Term` bound** — `List` unifies with `[Name | Args]` for a
  compound, or the singleton `[Term]` for an atomic term.
- **`Term` unbound** — `List` must already be a fully-instantiated,
  non-empty list. A singleton `[Name]` just unifies `Term` with `Name`
  as-is; `[Name | Args]` with a non-empty `Args` requires `Name` to be
  an atom and builds a compound (`Term.reconstruct/2` special-cases
  `Name` = `.` with exactly two `Args` into a native list here too,
  same as `functor/3`'s construct mode).

```elixir
Episteme.query(c.(:univ, [c.(:foo, [:a, :b]), Term.new_var("L")]), Database.new())
#=> {:ok, [%{"L" => [:foo, :a, :b]}]}

Episteme.query(c.(:univ, [Term.new_var("T"), [:foo, :a, :b]]), Database.new())
#=> {:ok, [%{"T" => %Episteme.Term.Compound{name: :foo, args: [:a, :b]}}]}
```

A non-atom head in a multi-element `List` raises `type_error(atom,
Head)`; an empty `List` raises `domain_error(non_empty_list, [])`; an
unbound `Term` with an unbound `List` raises `instantiation_error`.

---

## Arithmetic

### `is/2`

`X is Expr` computes the numeric value of `Expr` and unifies `X` with
the result. This is the one construct in this whole reference that
*calculates* rather than just matching or checking — `X is 2+2` and
`X = 2+2` are entirely different questions (see
[TUTORIAL.md §7](TUTORIAL.md#7-arithmetic)).

```elixir
Episteme.query(c.(:is, [Term.new_var("X"), c.(:+, [2, c.(:*, [3, 4])])]), Database.new())
#=> {:ok, [%{"X" => 14}]}
```

### Arithmetic comparisons: `numeric_equal/2`, `numeric_not_equal/2`, `</2`, `>/2`, `less_or_equal/2`, `greater_or_equal/2`

Compare the *numeric value* of two arithmetic expressions (each side is
evaluated exactly like `is/2`'s right-hand side first). `numeric_equal/2`/
`numeric_not_equal/2` (real Prolog: `=:=`/`=\=`) are numeric
equal/not-equal, so `numeric_equal(3, 3.0)` is true, unlike `equal(3, 3.0)`
(see [Matching and comparing values](#matching-and-comparing-values)
above), which cares about integer-vs-float. `<`/`>` are kept as
ordinary math symbols (they're universal notation, not Prolog-specific
punctuation); `less_or_equal/2`/`greater_or_equal/2` (real Prolog:
`=<`/`>=`) round out the ordering — `=<` in particular reads backwards
from every other language's `<=`, which is exactly the kind of thing
this reference exists to save you from having to remember.

```elixir
Episteme.query(c.(:numeric_equal, [3, 3.0]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:<, [3, 4]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:greater_or_equal, [3, 3]), Database.new())
#=> {:ok, [%{}]}
```

### `between/3`

`between(Low, High, X)` relates an integer `X` to an inclusive range.
With `X` already bound, it's just a range check; with `X` unbound, it
enumerates every integer from `Low` to `High` in order, one per
backtrack. `Low`/`High` are themselves arithmetic expressions,
evaluated once up front (like `is/2`'s right-hand side); if `Low` is
greater than `High`, there are simply no solutions.

```elixir
Episteme.query(c.(:between, [1, 5, Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}, %{"X" => 4}, %{"X" => 5}]}

Episteme.query(c.(:between, [1, 5, 3]), Database.new())
#=> {:ok, [%{}]}

Episteme.query(c.(:between, [5, 1, Term.new_var("X")]), Database.new())
#=> {:ok, []}
```

### Evaluable functors

Every one of these can appear as (part of) `is/2`'s right-hand side, or
either side of the comparisons above. `X` below stands for whatever
`is/2` binds.

| Expression | Result | Notes |
|---|---|---|
| `2 + 3` | `5` | |
| `2 - 3` | `-1` | |
| `2 * 3` | `6` | |
| `6 / 3` | `2` | Stays an integer when it divides evenly. |
| `7 / 2` | `3.5` | Falls back to a float otherwise. |
| `7 // 2` | `3` | Integer floor division; `//` always truncates toward negative infinity. |
| `-7 mod 2` | `1` | Floored modulo — the result takes the *divisor's* sign. |
| `-7 rem 2` | `-1` | Truncated remainder — the result takes the *dividend's* sign. |
| `2 ** 10` | `1024` | Integer base and non-negative integer exponent stays an integer. |
| `2 ^ 10` | `1024` | Same as `**`. |
| `abs(-5)` | `5` | |
| `sign(-5)` | `-1` | `1`, `-1`, or `0`. |
| `min(3, 7)` | `3` | |
| `max(3, 7)` | `7` | |
| `sqrt(16)` | `4.0` | Always a float, even for a perfect square. |
| `-5` (unary) | `-5` | Negation. |
| `+5` (unary) | `5` | Identity. |

```elixir
Episteme.query(c.(:is, [Term.new_var("X"), c.(:mod, [-7, 2])]), Database.new())
#=> {:ok, [%{"X" => 1}]}

Episteme.query(c.(:is, [Term.new_var("X"), c.(:rem, [-7, 2])]), Database.new())
#=> {:ok, [%{"X" => -1}]}
```

`/`, `//`, `mod`, and `rem` all raise `domain_error(non_zero, 0)` if the
divisor is `0` — see [Exceptions](#exceptions) below.

---

## Exceptions

### `throw/1`

`throw(Ball)` abandons the current computation, carrying `Ball` as the
reason. If nothing catches it (see `catch/3` below), it propagates all
the way out and `Episteme.query/2` returns `{:error, Ball}` instead of
`{:ok, solutions}` — it never crashes your Elixir process.

```elixir
Episteme.query(c.(:throw, [:my_error]), Database.new())
#=> {:error, :my_error}
```

### `catch/3`

`catch(Goal, Catcher, Recovery)` runs `Goal`; if it throws something
that unifies with `Catcher`, runs `Recovery` instead, with that
unification already in place — otherwise, `catch/3` just behaves like
`Goal` did (same solutions, no interference). If `Goal` throws
something that *doesn't* match `Catcher`, the throw keeps propagating
past this `catch/3` unchanged, exactly as if it weren't there.

```elixir
x = Term.new_var("X")
y = Term.new_var("Y")
r = Term.new_var("R")
catcher = c.(:error, [Term.new_var("_"), Term.new_var("_")])
body = c.(:catch, [c.(:is, [r, c.(:/, [x, y])]), catcher, c.(:unify, [r, :undefined])])

db = Database.add_clause(Database.new(), {c.(:safe_div, [x, y, r]), body})
Episteme.query(c.(:safe_div, [10, 0, Term.new_var("R")]), db)
#=> {:ok, [%{"R" => :undefined}]}
```

### `type_error/2`, `domain_error/2`, `instantiation_error/1`

Called as goals, these always throw — they're the standard shapes for
"wrong kind of value" / "right kind, wrong value" / "needed something
bound, got a variable," available for your own rules to raise directly
rather than reaching for a bare `throw/1`. Each wraps its formal error
in `error(Formal, _)`, matching what every automatically-raised error
below looks like too.

```elixir
Episteme.query(c.(:type_error, [:integer, :foo]), Database.new())
#=> {:error, error(type_error(integer, foo), _)}
#   (shown as Prolog-ish text here; the real value is nested
#   %Episteme.Term.Compound{}/%Episteme.Term.Var{} structs)

Episteme.query(c.(:domain_error, [:positive, -1]), Database.new())
#=> {:error, error(domain_error(positive, -1), _)}
```

`instantiation_error/1` takes one argument for symmetry with the other
two, but currently ignores it — it always throws the same
`error(instantiation_error, _)` regardless of what you pass:

```elixir
Episteme.query(c.(:instantiation_error, [Term.new_var("_")]), Database.new())
#=> {:error, error(instantiation_error, _)}
```

### What's raised automatically

You'll hit these without ever calling `throw/1` yourself:

- **`instantiation_error`** — an unbound variable anywhere a goal itself,
  or an arithmetic expression, needs to be resolved to something
  concrete.
- **`existence_error(procedure, Name/Arity)`** — calling a predicate
  that has no stored clauses *and* was never declared via `assert`/
  `retractall` either (see [Dynamic database](#dynamic-database)).
- **`type_error(evaluable, Culprit)`** — an arithmetic expression
  containing something that isn't a number and isn't a recognized
  evaluable functor.
- **`domain_error(non_zero, 0)`** — dividing by zero via `/`, `//`,
  `mod`, or `rem` (see [Evaluable functors](#evaluable-functors) above).

```elixir
Episteme.query(c.(:is, [Term.new_var("X"), Term.new_var("Y")]), Database.new())
#=> {:error, error(instantiation_error, _)}

Episteme.query(c.(:nonexistent, [1, 2]), Database.new())
#=> {:error, error(existence_error(procedure, nonexistent/2), _)}

Episteme.query(c.(:is, [Term.new_var("X"), :foo]), Database.new())
#=> {:error, error(type_error(evaluable, foo), _)}
```

---

## Dynamic database

Everything in this section mutates the `Database.t()` you pass in —
immediately, and visibly to every *later* call against that same
database, including separate `Episteme.query/2` calls, not just within
one query. None of it is undone by backtracking; an insert or delete
is a real one. See [TUTORIAL.md §10](TUTORIAL.md#10-dynamic-database-assert-and-retract)
for the underlying model.

### `assertz/1` and `assert/1`

Adds a clause at the *end* of its predicate's clause list. `assert/1`
is simply another name for `assertz/1`. The argument is either a bare
term (stored as a fact) or a `Head :- Body` compound (stored as a
rule); any variable in it that's still unbound at assert-time becomes
that stored clause's own private variable, never shared with whatever
asserted it.

```elixir
db = Database.new()
Episteme.query(c.(:assertz, [c.(:p, [1])]), db)
Episteme.query(c.(:assert, [c.(:p, [2])]), db)
Episteme.query(c.(:p, [Term.new_var("X")]), db)
#=> {:ok, [%{"X" => 1}, %{"X" => 2}]}
```

### `asserta/1`

Same as `assertz/1`, but prepends — the new clause is tried *before*
any existing ones.

```elixir
db = Database.new()
Episteme.query(c.(:assertz, [c.(:p, [1])]), db)
Episteme.query(c.(:assert, [c.(:p, [2])]), db)
Episteme.query(c.(:asserta, [c.(:p, [0])]), db)
Episteme.query(c.(:p, [Term.new_var("X")]), db)
#=> {:ok, [%{"X" => 0}, %{"X" => 1}, %{"X" => 2}]}
```

### `retract/1`

Removes the *first* stored clause (in declared/assert order) whose
head *and* body both unify with the argument, and keeps whatever got
bound along the way — so a variable in your `retract/1` argument ends
up bound to a field of the clause that got removed. Fails, without
changing anything, if no clause matches. Deterministic on success: it
doesn't backtrack into trying to remove a *second* matching clause.

```elixir
db = Database.new() |> Database.add_fact(c.(:q, [1])) |> Database.add_fact(c.(:q, [2]))
Episteme.query(c.(:retract, [c.(:q, [Term.new_var("X")])]), db)
#=> {:ok, [%{"X" => 1}]}

Episteme.query(c.(:q, [Term.new_var("X")]), db)
#=> {:ok, [%{"X" => 2}]}
```

### `retractall/1`

Removes *every* clause whose head unifies with the argument (the
body isn't considered at all). Always succeeds — even against a
predicate that was never asserted — and never binds anything, unlike
`retract/1`; each internal unification is only used to pick which
clauses to remove, then discarded. Crucially, it leaves the predicate
*defined*, with zero clauses, rather than making it look like it was
never declared — so a call afterward just fails, the way it would after
removing the last clause one `retract/1` at a time, rather than raising
`existence_error`.

```elixir
db = Database.new() |> Database.add_fact(c.(:s, [1])) |> Database.add_fact(c.(:s, [2]))
Episteme.query(c.(:retractall, [c.(:s, [Term.new_var("_")])]), db)
#=> {:ok, [%{}]}

Episteme.query(c.(:s, [Term.new_var("X")]), db)
#=> {:ok, []}
```

---

## Lists

Lists are plain Elixir lists throughout — nothing Prolog-specific about
their representation, just ordinary unification generalized to recurse
into them.

### `length/2`

Works in either direction. With the list already known, reports its
length; with the length already known (and the list unbound), builds a
list of that many independently-fresh variables — unifying that result
against anything else afterward works exactly like it would with any
other freshly-built list.

```elixir
Episteme.query(c.(:length, [[:a, :b, :c], Term.new_var("N")]), Database.new())
#=> {:ok, [%{"N" => 3}]}

l = Term.new_var("L")
Episteme.query(c.(:and, [c.(:length, [l, 3]), c.(:unify, [l, [:a, :b, :c]])]), Database.new())
#=> {:ok, [%{"L" => [:a, :b, :c]}]}
```

### `append/3`

`append(A, B, C)` relates `C` to `A ++ B`. With `A` and `B` known, it's
just concatenation; with `A` left unbound and `C` known, it enumerates
*every* way to split `C` into a front and back piece, on backtracking.

```elixir
Episteme.query(c.(:append, [[1, 2], [3, 4], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [1, 2, 3, 4]}]}

Episteme.query(c.(:append, [Term.new_var("X"), Term.new_var("Y"), [1, 2, 3]]), Database.new())
#=> {:ok, [
#     %{"X" => [], "Y" => [1, 2, 3]},
#     %{"X" => [1], "Y" => [2, 3]},
#     %{"X" => [1, 2], "Y" => [3]},
#     %{"X" => [1, 2, 3], "Y" => []}
#   ]}
```

### `member/2`

`member(X, List)` enumerates every element of `List`, one per
backtrack, unifying `X` with each in turn.

```elixir
Episteme.query(c.(:member, [Term.new_var("X"), [:a, :b, :c]]), Database.new())
#=> {:ok, [%{"X" => :a}, %{"X" => :b}, %{"X" => :c}]}
```

### `reverse/2`

Works either direction — `reverse(A, B)` succeeds if `B` is `A`
reversed, whichever side is the one already known.

```elixir
Episteme.query(c.(:reverse, [[1, 2, 3], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [3, 2, 1]}]}
```

### `nth0/3` and `nth1/3`

Relate an index to the element at that position — `nth0/3` counts from
0, `nth1/3` from 1. With the index left unbound, enumerates every
`{index, element}` pair in the list.

```elixir
Episteme.query(c.(:nth0, [1, [:a, :b, :c], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => :b}]}

Episteme.query(c.(:nth1, [1, [:a, :b, :c], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => :a}]}
```

### `last/2`

`last(List, Elem)` unifies `Elem` with the final element of `List`.
Fails on an empty list — there's no last element to report.

```elixir
Episteme.query(c.(:last, [[:a, :b, :c], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => :c}]}

Episteme.query(c.(:last, [[], Term.new_var("X")]), Database.new())
#=> {:ok, []}
```

### `msort/2` and `sort/2`

Both sort by the [standard order of terms](#matching-and-comparing-values),
not just numeric order — `msort/2` keeps duplicates, `sort/2` also
removes any term that standard-order-compares equal to its neighbor
once sorted (not plain `==` — `1` and `1.0` are equal in *value* but
never merged, since they're never `:eq` in standard order either; see
`compare/3`'s own note on this).

```elixir
Episteme.query(c.(:msort, [[3, 1, 2, 1], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [1, 1, 2, 3]}]}

Episteme.query(c.(:sort, [[3, 1, 2, 1], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [1, 2, 3]}]}
```

### `permutation/2`

`permutation(List, Perm)` enumerates every reordering of `List`, one
per backtrack (`N!` of them for a list of length `N` — inherently
expensive for anything but a small list, the same as in any Prolog).
`List` must already be bound.

```elixir
Episteme.query(c.(:permutation, [[1, 2], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [1, 2]}, %{"X" => [2, 1]}]}
```

### `sum_list/2`, `max_list/2`, `min_list/2`

Fold a list of numbers down to their sum, maximum, or minimum.
`sum_list([], Sum)` gives `Sum = 0` (the identity); `max_list/2` and
`min_list/2` both fail on an empty list instead — there's no
extremum to report.

```elixir
Episteme.query(c.(:sum_list, [[1, 2, 3], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => 6}]}

Episteme.query(c.(:max_list, [[3, 1, 2], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => 3}]}
```

### `list_to_set/2`

Removes duplicates (by standard order, same as `sort/2`), but keeps
first-occurrence order instead of sorting.

```elixir
Episteme.query(c.(:list_to_set, [[3, 1, 3, 2, 1], Term.new_var("X")]), Database.new())
#=> {:ok, [%{"X" => [3, 1, 2]}]}
```

---

## Higher-order list predicates

`include/3`, `exclude/3`, `foldl/4+`, and `maplist/2+` all take a
`Goal` as their first argument and call it — via the same mechanism
`call/N` uses — once per list element (or once per matching row,
across several lists in lockstep), each call cut-opaque, exactly like
`call/N` itself.

### `include/3` and `exclude/3`

`include(Goal, List, Included)` keeps every element for which
`call(Goal, Elem)` succeeds at least once; `exclude/3` keeps the
elements where it *doesn't*. Neither propagates any bindings `Goal`
makes back into the result — they're pure membership tests, run once
per element, first-solution-only.

```elixir
x = Term.new_var("X")
positive_db =
  Database.new() |> Database.consult_forms([{:rule, c.(:positive, [x]), c.(:>, [x, 0])}])

Episteme.query(c.(:include, [:positive, [1, -2, 3, -4], Term.new_var("L")]), positive_db)
#=> {:ok, [%{"L" => [1, 3]}]}
```

### `foldl/4`, `foldl/5`, `foldl/6` (1–3 lists)

`foldl(Goal, List, V0, V)` threads an accumulator through `Goal`,
called as `call(Goal, Elem, AccIn, AccOut)` for each element in turn —
`V0` seeds the first call's `AccIn`, `V` unifies with the last call's
`AccOut` (or with `V0` directly, for an empty list). `foldl/5`/`foldl/6`
walk two or three lists in lockstep instead of one, all of which must
already be bound to the same length.

```elixir
x = Term.new_var("X")
a0 = Term.new_var("A0")
a = Term.new_var("A")
add_db =
  Database.new() |> Database.consult_forms([{:rule, c.(:add, [x, a0, a]), c.(:is, [a, c.(:+, [a0, x])])}])

Episteme.query(c.(:foldl, [:add, [1, 2, 3, 4], 0, Term.new_var("Sum")]), add_db)
#=> {:ok, [%{"Sum" => 10}]}
```

### `maplist/2` through `maplist/N`

`maplist(Goal, List1, ..., ListN)` succeeds iff `call(Goal, E1_i, ...,
EN_i)` succeeds for every row `i` across the `N` lists in lockstep. At
least one list must already be bound (fixing the row count); any other
list left unbound is unified with a fresh list of that many
independent variables first, so a call-mode `Goal` can fill it in.

```elixir
Episteme.query(c.(:maplist, [:positive, [1, 2, 3]]), positive_db)
#=> {:ok, [%{}]}   -- every element is positive

Episteme.query(c.(:maplist, [:positive, [1, -2, 3]]), positive_db)
#=> {:ok, []}   -- -2 isn't
```

---

## I/O

Minimal, unconditional side-effecting output — each of these succeeds
exactly once, the printing aside. There's no operator-aware
pretty-printing (`1+2` prints as `+(1, 2)`, its canonical
`functor(args)` form) — that's a front-end reader's job, and Episteme
has none of its own (see [README.md](README.md#why-a-separate-package-from-aletheia)).

### `write/1` and `print/1`

Print the fully-resolved value of `Term`, canonical `functor(args)`
text, with no trailing newline. `print/1` is identical to `write/1`.

```elixir
Episteme.query(c.(:write, [c.(:foo, [1, 2])]), Database.new())
#=> prints "foo(1, 2)", then {:ok, [%{}]}
```

### `writeln/1`

Same as `write/1`, with a trailing newline.

### `nl/0`

Prints a single newline and succeeds.

```elixir
Episteme.query(:nl, Database.new())
#=> prints "\n", then {:ok, [%{}]}
```
