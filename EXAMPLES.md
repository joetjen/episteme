# Examples

Complete, runnable programs, each with a plain-English explanation of
what it stores, what it asks, and what the answer means — no prior
Prolog or logic-programming background assumed (see
[TUTORIAL.md](TUTORIAL.md) if any of the vocabulary here is new to
you). Every snippet below was actually executed against this version of
Episteme — the `#=>` comments are real, captured output, not
hand-derived. Paste any one of them into `iex -S mix` from a checkout
of this repository (each is self-contained after the shared
`alias`/`c` setup in [§0](#0-shared-setup)). Use
[REFERENCE.md](REFERENCE.md) to look up the full detail (and further
examples) for any predicate used here, or [CHEATSHEET.md](CHEATSHEET.md)
for a quick one-line reminder.

## 0. Shared setup

Every example below assumes this is already in scope:

```elixir
alias Episteme.{Database, Term}
alias Episteme.Term.Compound
c = fn name, args -> %Compound{name: name, args: args} end
```

`c` is just a shorthand for building a "statement with a name and some
fields" (what Episteme calls a compound term) without typing out
`%Compound{name: ..., args: ...}` every time.

## 1. Family tree (recursive rules)

We record who is whose parent, then teach the engine a general rule for
"ancestor" — someone is your ancestor if they're your parent, *or* if
they're the parent of one of your ancestors. That second half is
recursive: the rule refers to itself, the same way you'd define
"ancestor" for a real family tree by working backward one generation at
a time until you run out of known parents.

```elixir
db =
  Database.new()
  |> Database.add_fact(c.(:parent, [:tom, :bob]))
  |> Database.add_fact(c.(:parent, [:tom, :liz]))
  |> Database.add_fact(c.(:parent, [:bob, :ann]))
  |> Database.add_fact(c.(:parent, [:bob, :pat]))

ax = Term.new_var("X")
ay = Term.new_var("Y")
db = Database.add_clause(db, {c.(:ancestor, [ax, ay]), c.(:parent, [ax, ay])})

rx = Term.new_var("X")
ry = Term.new_var("Y")
rz = Term.new_var("Z")

db =
  Database.add_clause(
    db,
    {c.(:ancestor, [rx, ry]), c.(:and, [c.(:parent, [rx, rz]), c.(:ancestor, [rz, ry])])}
  )

Episteme.query(c.(:ancestor, [:tom, Term.new_var("Who")]), db)
#=> {:ok, [%{"Who" => :bob}, %{"Who" => :liz}, %{"Who" => :ann}, %{"Who" => :pat}]}
```

We store four parent facts, then two rules for `ancestor`: the first
says "X is an ancestor of Y if X is directly Y's parent"; the second
says "X is an ancestor of Y if X is some Z's parent, and Z is (in turn)
an ancestor of Y." Asking "who is tom an ancestor of?" finds bob and
liz directly (tom's own children), then keeps following the chain
downward — bob's children ann and pat count too, because bob is one of
tom's descendants and the second rule connects them. The database ends
up listing tom as an ancestor of all four other people.

Each rule above builds its own fresh set of variables (`ax`/`ay` for
the first, `rx`/`ry`/`rz` for the second) purely for readability — every
stored rule gets its own private set of blanks each time it's used
regardless, so reusing the same variable across two different rules
would still give the correct answer, just be more confusing to read.

## 2. Graph reachability

The same "direct or via one more step" shape as the family tree, but
over a graph of directed edges (arrows from one node to another) instead
of parent/child relationships — "can you get from A to B by following
arrows?" Deliberately a graph with no cycles (a path that loops back on
itself) — a graph *with* cycles needs to keep track of which nodes it's
already visited so it doesn't chase its own tail forever, which is a
worthwhile exercise once you've read [§10](TUTORIAL.md#10-dynamic-database-assert-and-retract)
of the tutorial on carrying extra information through a rule.

```elixir
db =
  Database.new()
  |> Database.add_fact(c.(:edge, [:a, :b]))
  |> Database.add_fact(c.(:edge, [:b, :c]))
  |> Database.add_fact(c.(:edge, [:b, :d]))
  |> Database.add_fact(c.(:edge, [:c, :e]))

px = Term.new_var("X")
py = Term.new_var("Y")
db = Database.add_clause(db, {c.(:path, [px, py]), c.(:edge, [px, py])})

qx = Term.new_var("X")
qy = Term.new_var("Y")
qz = Term.new_var("Z")

db =
  Database.add_clause(
    db,
    {c.(:path, [qx, qy]), c.(:and, [c.(:edge, [qx, qz]), c.(:path, [qz, qy])])}
  )

Episteme.query(c.(:path, [:a, Term.new_var("Y")]), db)
#=> {:ok, [%{"Y" => :b}, %{"Y" => :c}, %{"Y" => :d}, %{"Y" => :e}]}

Episteme.query(c.(:path, [:e, :a]), db)
#=> {:ok, []}
```

We store four arrows: a→b, b→c, b→d, c→e. `path/2` means "reachable,
possibly through several arrows" — defined the same recursive way as
`ancestor/2` above. Asking "what's reachable from a?" walks the whole
chain and finds all four other nodes; asking the reverse — "what's
reachable from e?" — finds nothing, because every arrow only points
forward and there's no way back to a.

## 3. FizzBuzz

The classic exercise: for every number 1 through 20, print `fizzbuzz`
if it's divisible by both 3 and 5, `fizz` if just 3, `buzz` if just 5,
otherwise the number itself. This shows three pieces working together:
`between/3` (generate a range of numbers), a chain of `if_then_else/3`
checks (`if_then_else(Cond, Then, Else)`, read "if Cond, then Then,
otherwise try Else"), and `forall/2` (run this check for every number
in the range).

```elixir
n = Term.new_var()

goal =
  c.(:forall, [
    c.(:between, [1, 20, n]),
    c.(:if_then_else, [
      c.(:is, [0, c.(:mod, [n, 15])]),
      c.(:writeln, [:fizzbuzz]),
      c.(:if_then_else, [
        c.(:is, [0, c.(:mod, [n, 3])]),
        c.(:writeln, [:fizz]),
        c.(:if_then_else, [
          c.(:is, [0, c.(:mod, [n, 5])]),
          c.(:writeln, [:buzz]),
          c.(:writeln, [n])
        ])
      ])
    ])
  ])

Episteme.query(goal, Database.new())
#=> prints 1, 2, fizz, 4, buzz, fizz, 7, 8, fizz, buzz, 11, fizz, 13, 14,
#   fizzbuzz, 16, 17, fizz, 19, buzz -- one per line -- then {:ok, [%{}]}
```

Read from the inside out: for each number `n` between 1 and 20, check
"does 15 divide n evenly?" — if so, print `fizzbuzz`; otherwise check
"does 3 divide n evenly?" — if so, print `fizz`; otherwise check 5 the
same way for `buzz`; otherwise just print the number. `forall/2` is
what makes this run for *every* number rather than stopping at the
first one — it's a "check this for everything" instruction, not a
question with an answer to collect, so the final result is just
"yes, that held for every number" (`{:ok, [%{}]}`), with the actual
output happening as a side effect of the printing along the way.

`n` is anonymous here (`Term.new_var/0`, no display name) for a reason
explained more in [§5](#5-filtering-and-collecting-with-findall) below:
it's only ever used *inside* the `forall/2` check, never by whoever
asked the question, so there's no need to give it a name.

## 4. A key-value store (assert/retract)

Everything so far set up its facts once, before asking any questions.
Here, we use `assertz/1` (insert a fact right now) and `retractall/1`
(delete matching facts right now) to turn a database into an actual
mutable lookup table — wrapped in two small Elixir helper functions
that should feel familiar if you've used any key-value store before.

```elixir
put = fn kv, key, value ->
  Episteme.query(c.(:retractall, [c.(:kv, [key, Term.new_var("_")])]), kv)
  Episteme.query(c.(:assertz, [c.(:kv, [key, value])]), kv)
  kv
end

get = fn kv, key ->
  case Episteme.query(c.(:kv, [key, Term.new_var("Value")]), kv) do
    {:ok, [%{"Value" => value}]} -> {:ok, value}
    {:ok, []} -> :not_found
  end
end

kv = Database.new()
kv = put.(kv, :name, "episteme")
kv = put.(kv, :version, "0.1.0")
get.(kv, :name)
#=> {:ok, "episteme"}

kv = put.(kv, :name, "episteme!")
get.(kv, :name)
#=> {:ok, "episteme!"}

get.(kv, :missing)
#=> :not_found
```

`put` stores a fact shaped "the value for this key is that" — first
deleting any existing fact for the same key, then inserting the new
one. `get` asks "what's the value stored for this key?" and translates
the answer back into an ordinary Elixir result: `{:ok, value}` if a
fact was found, `:not_found` if not. We store `:name`, then overwrite
it with a new value, and confirm each `get` call sees the *current*
value, not the original one — exactly what you'd expect from any
ordinary key-value store.

The `retractall/1` before every `assertz/1` in `put` is what makes this
an overwrite rather than an accumulating log: without it, storing
`:name` twice would leave *two* facts about `:name` around, and asking
"what's the value for `:name`?" would come back with two different
answers instead of one.

## 5. Filtering and collecting with findall

`findall/3` is how you turn "everyone who matches some condition" into
an actual Elixir list you can work with — the logic-programming
equivalent of a database `SELECT` with a `WHERE` clause.

```elixir
db =
  Database.new()
  |> Database.add_fact(c.(:employee, [:ana, :engineering, 95_000]))
  |> Database.add_fact(c.(:employee, [:ben, :sales, 61_000]))
  |> Database.add_fact(c.(:employee, [:cy, :engineering, 88_000]))
  |> Database.add_fact(c.(:employee, [:dee, :sales, 72_000]))

name = Term.new_var()
dept = Term.new_var()
salary = Term.new_var()

goal =
  c.(:findall, [
    name,
    c.(:and, [
      c.(:employee, [name, dept, salary]),
      c.(:and, [c.(:unify, [dept, :engineering]), c.(:>, [salary, 90_000])])
    ]),
    Term.new_var("Names")
  ])

Episteme.query(goal, db)
#=> {:ok, [%{"Names" => [:ana]}]}
```

We store four employees, each with a name, department, and salary.
The question is: "collect the name of every employee who's in
engineering *and* earns over 90,000, into a list called Names." Only
Ana fits both conditions (Cy is in engineering but earns less; Ben and
Dee aren't in engineering at all), so `Names` comes back `[:ana]` — a
one-element list, not a bare value, because `findall/3` always answers
with a list, even when there's only one match (or none at all).

`name`/`dept`/`salary` above are anonymous (`Term.new_var/0`, no
display name) because they're only used *inside* `findall/3`'s
condition, never by the question that asked for `Names`. A *named*
variable used only there would come back in the answer too, still
unfilled — see [TUTORIAL.md §11](TUTORIAL.md#11-collecting-every-solution-findall-and-forall)
for why.

## 6. Error handling with catch/3

`throw/1`/`catch/3` are Episteme's version of raising and rescuing an
error. Here, dividing by zero would normally abort the whole question
with an error — `catch/3` lets us recover from that one specific
failure and answer `:undefined` instead, the way a real program might
catch a division-by-zero exception and substitute a safe default.

```elixir
x = Term.new_var("X")
y = Term.new_var("Y")
r = Term.new_var("R")
catcher = c.(:error, [Term.new_var("_"), Term.new_var("_")])

db =
  Database.add_clause(
    Database.new(),
    {c.(:safe_div, [x, y, r]),
     c.(:catch, [c.(:is, [r, c.(:/, [x, y])]), catcher, c.(:unify, [r, :undefined])])}
  )

Episteme.query(c.(:safe_div, [10, 2, Term.new_var("R")]), db)
#=> {:ok, [%{"R" => 5}]}

Episteme.query(c.(:safe_div, [10, 0, Term.new_var("R")]), db)
#=> {:ok, [%{"R" => :undefined}]}
```

`safe_div(X, Y, R)` means "R is X divided by Y — unless that raises an
error, in which case R is `:undefined` instead." Dividing 10 by 2 works
normally and answers `5`. Dividing 10 by 0 would normally raise an
error term (division by zero has no numeric answer), but the `catch`
wrapped around it notices that error, matches it against `catcher`, and
substitutes `:undefined` — so the question still gets a clean answer
rather than blowing up.

`catcher` here matches *any* error at all — a real program would
usually be more specific (catch only "division by zero," say) so it
doesn't accidentally swallow a completely different kind of error and
hide a real bug.

## 7. Writing your own recursive list rule

The built-in list operations ([CHEATSHEET.md](CHEATSHEET.md#lists))
cover common cases like "is X in this list" or "reverse this list," but
ordinary rules — the same recursive shape as the family tree in §1 —
are how you write anything else. Here's a `sum_list/2` that adds up
every number in a list, built from scratch the way a built-in one would
be under the hood.

```elixir
db = Database.add_fact(Database.new(), c.(:sum_list, [[], 0]))

h = Term.new_var("H")
t = Term.new_var("T")
rest = Term.new_var("Rest")
total = Term.new_var("Total")

db =
  Database.add_clause(
    db,
    {c.(:sum_list, [[h | t], total]),
     c.(:and, [c.(:sum_list, [t, rest]), c.(:is, [total, c.(:+, [h, rest])])])}
  )

Episteme.query(c.(:sum_list, [[1, 2, 3, 4, 5], Term.new_var("Total")]), db)
#=> {:ok, [%{"Total" => 15}]}
```

Two rules, read as plain English: "the sum of an empty list is 0" (the
base case, stopping the recursion), and "the sum of a list whose first
element is H and whose remaining elements are T, is H plus the sum of
T" (the recursive case, peeling off one element at a time until the
list runs out and hits the base case). Asking for the sum of
`[1, 2, 3, 4, 5]` walks that chain — 1 + (2 + (3 + (4 + (5 + 0)))) —
and answers `15`.

## 8. A database that survives a restart

Everything else in this file stores its facts in memory, which means
they're gone the moment your program stops. This example stores a fact
to disk instead, closes it, reopens it — simulating a completely
separate run of the program — and confirms the fact is still there.

```elixir
path = "facts.dets"
db = Database.new(backend: Episteme.Database.Backends.Dets, file: path)
Episteme.query(c.(:assertz, [c.(:visited, [:home])]), db)
Database.sync(db)
Database.close(db)

# ... a fresh process, or after actually restarting the VM ...
reopened = Database.new(backend: Episteme.Database.Backends.Dets, file: path)
Episteme.query(c.(:visited, [Term.new_var("Place")]), reopened)
#=> {:ok, [%{"Place" => :home}]}
Database.close(reopened)
```

We open a disk-backed database at `facts.dets`, insert the fact
"home has been visited," force it to actually be written to disk
(`sync/1`), and close the file (`close/1`). Reopening that *same file*
— which could just as well happen after actually restarting your
computer — finds the fact still there, exactly as if nothing had
happened in between.

See [README.md § Storage backends](README.md#storage-backends) for what
this on-disk storage does and doesn't guarantee.
