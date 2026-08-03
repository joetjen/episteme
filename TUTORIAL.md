# Tutorial

A step-by-step walkthrough of Episteme, written for someone who has
**never done logic programming before** — no Prolog background assumed.
Every snippet is real, runnable Elixir — paste it into `iex -S mix` from
a checkout of this repository. Once you've read this, three places to
go next depending on what you need: [REFERENCE.md](REFERENCE.md) for
full detail on any one feature (with more examples), [EXAMPLES.md](EXAMPLES.md)
for complete standalone programs, or [CHEATSHEET.md](CHEATSHEET.md) for
a quick one-page lookup once you know your way around.

## The idea, before any code

Most programming is "tell the computer the steps to compute an answer."
Logic programming is different: you tell the computer **facts** ("Tom
is Bob's parent") and **rules** for deriving new facts from old ones
("X is Y's grandparent if X is some Z's parent and Z is Y's parent"),
and then you ask it **questions** ("who is Tom the parent of?"). The
engine searches through everything it's been told, tries every
combination that could possibly answer your question, and hands back
every answer that actually works — automatically backtracking (undoing
a guess and trying a different one) whenever a particular combination
doesn't pan out.

That's the whole mental model for this tutorial: a growing pile of
facts and rules (the **database**), a question you ask against it (the
**goal** or **query**), and a list of answers, each one a set of
"here's what the blanks in your question turned out to be" (a
**solution**). Everything below is really just: what does it look like
to build that pile of facts, and what does asking a question and
reading back an answer actually look like in Elixir code.

## 1. There is no reader

Most Prolog tutorials start with `.pl` source files and a `?-` prompt.
Episteme has neither: there's no parser, no `.` clause terminator, no
operator table, and you don't need to learn Prolog's text syntax at
all. You build facts, rules, and questions directly as plain Elixir
values, the same way you'd build any other Elixir data structure — a
`%Episteme.Term.Compound{}` *is* a Prolog-style compound term, not a
representation of one that gets parsed later.

```elixir
alias Episteme.{Database, Engine, Term}
alias Episteme.Term.Compound
```

## 2. Terms: the building blocks of a fact

Everything Episteme stores or asks about is built from five kinds of
value:

```elixir
:tom                          # an atom
42                             # an integer
3.14                           # a float
[1, 2, 3]                      # a list -- a real Elixir list
Term.new_var("X")              # a logic variable, named "X" for display
%Compound{name: :likes, args: [:tom, :beer]}   # likes(tom, beer)
```

In plain terms:

- An **atom** is a fixed label — think of it the way you'd use a plain
  Elixir atom anywhere else, as a symbolic name rather than a piece of
  data to compute with (`:tom`, `:bob`, `:positive` — none of these
  "mean" anything to Episteme beyond being distinct, comparable names).
- **Integers and floats** are ordinary numbers.
- A **list** is an ordinary Elixir list — nothing special.
- A **variable** is a *placeholder for an answer the engine hasn't
  found yet* — the blank in a fill-in-the-blank question. When you ask
  a question containing a variable, the engine's job is to figure out
  every value that could fill that blank and make the question true.
- A **compound** is a labeled group of values — `%Compound{name: :likes, args: [:tom, :beer]}`
  is the statement "`likes(tom, beer)`," i.e. "tom likes beer." Think of
  it as a small, named record: the `name` says what kind of statement
  this is, and `args` are its fields.

A variable's `name` (`"X"` above) is purely cosmetic — it only affects
how the answer gets *labeled* when you read it back. What actually
makes two variables "the same blank" is Elixir identity: two separate
`Term.new_var("X")` calls create two *different* placeholders that
happen to share a display name. If you want the same blank to appear
twice in a statement — "X likes X," whatever X turns out to be — reuse
the same Elixir variable:

```elixir
x = Term.new_var("X")
%Compound{name: :likes, args: [x, x]}   # likes(X, X) -- the *same* X twice
```

## 3. A database and your first query

Let's record a few facts about who is whose parent, then ask some
questions about them.

```elixir
db =
  Database.new()
  |> Database.add_fact(%Compound{name: :parent, args: [:tom, :bob]})
  |> Database.add_fact(%Compound{name: :parent, args: [:tom, :liz]})
  |> Database.add_fact(%Compound{name: :parent, args: [:bob, :ann]})

Episteme.query(%Compound{name: :parent, args: [:tom, :bob]}, db)
#=> {:ok, [%{}]}

Episteme.query(%Compound{name: :parent, args: [:tom, Term.new_var("Who")]}, db)
#=> {:ok, [%{"Who" => :bob}, %{"Who" => :liz}]}
```

`Database.new/0` starts an empty pile of facts; each `add_fact/2` adds
one row to it — "tom is bob's parent," "tom is liz's parent," "bob is
ann's parent." That's the entire database: three plain statements, no
questions asked yet.

Then we ask two questions:

- **"Is tom bob's parent?"** — a question with no blanks in it at all
  (`:tom` and `:bob` are both fixed values, not variables). The engine
  finds a matching fact and answers yes. `{:ok, [%{}]}` means "one
  answer, and it didn't need to fill in any blanks" — an empty map is
  still a real answer here, just a boring one: it's the difference
  between "yes" and "here's what X turned out to be."
- **"Who is tom the parent of?"** — this time `Who` is a variable, a
  blank. The engine looks at every fact we stored that's named `parent`
  and has two fields, checks whether the first field matches `tom`, and
  for every fact where it does, reports what the second field was. Two
  facts match ("tom is bob's parent" and "tom is liz's parent"), so we
  get two answers: `%{"Who" => :bob}` ("one way to answer your
  question: Who = bob") and
  `%{"Who" => :liz}`.

`Episteme.query/2` always returns `{:ok, solutions}`: one map per
answer, and the map's keys are exactly the *named* variables you put
in your question (a variable named `"_"` — the default — is treated as
"I don't care about this blank" and never shows up in an answer, same
as Prolog's own anonymous-variable convention). Zero answers just means
`{:ok, []}` — "I checked everything I know, and nothing matches," not
an error.

Facts are secretly just a special case of a rule: `add_fact/2` is
shorthand for "add a rule whose body is always true" — you'll see what
that means in the next section.

## 4. Rules: deriving new facts from old ones

A **fact** is a statement you assert outright. A **rule** is a
statement that's true *whenever some other condition holds* — "X is Y's
grandparent, **if** X is some Z's parent **and** Z is Y's parent." We
never store "tom is ann's grandparent" directly; the engine works it
out on the fly, every time, by chaining `parent` facts together.

```elixir
{x, y, z} = {Term.new_var("X"), Term.new_var("Y"), Term.new_var("Z")}

db =
  db
  |> Database.add_clause(
    {%Compound{name: :grandparent, args: [x, z]},
     %Compound{name: :and, args: [
       %Compound{name: :parent, args: [x, y]},
       %Compound{name: :parent, args: [y, z]}
     ]}}
  )

Episteme.query(%Compound{name: :grandparent, args: [:tom, Term.new_var("Who")]}, db)
#=> {:ok, [%{"Who" => :ann}]}
```

`Database.add_clause/2` takes a `{head, body}` pair: the *head* is what
the rule concludes (`grandparent(X, Z)`), the *body* is what has to be
true for that conclusion to hold (`parent(X, Y)` **and** `parent(Y, Z)`
— `and/2` is Episteme's own goal for "and," spelled out as a word
rather than real Prolog's `,` operator, since there's no reader here
for `,` to be conventional syntax *in*). Reading the whole thing as a
sentence: "X is Z's grandparent if there's some Y such that X is Y's
parent and Y is Z's parent."

Asking "who is tom's grandparent?" makes the engine go looking for a Y
that makes both halves true at once: it tries `parent(tom, Y)`, finds
`Y = bob` (from the facts in §3), then checks `parent(bob, Z)` with
that same `bob`, finds `Z = ann`, and reports `Who = ann` — tom is
bob's parent, and bob is ann's parent, so tom is ann's grandparent,
exactly the way you'd work it out by hand.

One detail worth flagging early: every time a rule is used, it gets a
*brand-new* set of variables — the `x`/`y`/`z` above belong to the
*stored rule*, not to whatever question you ask it. Reusing the same
Elixir variable across a rule and a query never accidentally connects
them; two separately-created rules using the same variable names don't
interfere with each other either.

## 5. Control: if-then-else and negation

Sometimes you want a rule to check a condition and answer differently
depending on which way it goes — the logic-programming equivalent of
`if`/`else`. `if_then_else(Cond, Then, Else)` reads exactly like it
looks: "if Cond, then Then, else Else" — and it commits to whichever
branch `Cond` first succeeds with, the same way a real `if` doesn't
keep checking other branches once one matched.

(A quick note on names: real Prolog spells this `(Cond -> Then ; Else)`,
with `;`/`->` as operators. Episteme uses the plain English words
instead — `and`, `or`, `if_then`/`if_then_else`, `not`, `cut` — since
there's no text syntax here for punctuation operators to be
*conventional against* in the first place; a name you can actually
remember without looking it up won out over matching ISO Prolog
symbol-for-symbol. [CHEATSHEET.md](CHEATSHEET.md) has the full list.)

```elixir
c = fn name, args -> %Compound{name: name, args: args} end
x = Term.new_var("X")
r = Term.new_var("R")

body =
  c.(:if_then_else, [
    c.(:>, [x, 0]),
    c.(:unify, [r, :positive]),
    c.(:if_then_else, [c.(:<, [x, 0]), c.(:unify, [r, :negative]), c.(:unify, [r, :zero])])
  ])

db2 = Database.add_clause(Database.new(), {c.(:sign, [x, r]), body})

Episteme.query(c.(:sign, [5, Term.new_var("R")]), db2)
#=> {:ok, [%{"R" => :positive}]}
```

This rule reads as: "R is the sign of X — `positive` if X is greater
than 0, else `negative` if X is less than 0, else `zero`." Asking
`sign(5, R)` checks "is 5 greater than 0?" — yes — so `R` is set to
`:positive` and the engine doesn't bother checking the other two
branches at all, giving exactly one answer. (`unify/2` is Episteme's
"make these two things match" goal — real Prolog's `=` operator; see
[§2](#2-terms-the-building-blocks-of-a-fact) if "unify" itself is a new
word to you.)

`not(Goal)` is how you ask "is there **no** way to prove this?" — it
succeeds exactly when `Goal` has zero answers, and — importantly — it
never fills in any blanks, even ones `Goal` would have filled in on its
way to failing. It's a yes/no check for *absence* of a proof, not a
search for one. (Real Prolog spells this `\+ Goal`.)

```elixir
x2 = Term.new_var("X")

db3 =
  Database.new()
  |> Database.add_clause({c.(:even, [x2]), c.(:is, [0, c.(:mod, [x2, 2])])})

Episteme.query(c.(:not, [c.(:even, [3])]), db3)
#=> {:ok, [%{}]}
```

Here `even(X)` is defined as "X divided by 2 leaves remainder 0." Asking
"is it **not** the case that 3 is even?" — 3 isn't even, so `even(3)`
has no proof, so the negation succeeds. `{:ok, [%{}]}` is that yes,
with no blanks to report (the query itself had none).

## 6. Cut: committing to a choice

Normally, if a path through your facts and rules doesn't lead anywhere
useful, the engine automatically backs up and tries a different one —
a different fact, a different rule, a different branch of an
if-then-else — the way you'd back out of a dead end in a maze and try
another turn. `cut` tells the engine: **stop** — don't just avoid
exploring forward from here, actually give up every alternative choice
already made to get here, even ones that already looked like they were
working. (Real Prolog spells this `!`.)

```elixir
db4 =
  Database.new()
  |> Database.add_clause({:p, c.(:and, [:cut, :fail])})
  |> Database.add_clause({:p, true})

Episteme.query(:p, db4)
#=> {:ok, []}
```

Walking through this by hand: asking `p` first tries the *first* stored
rule, "p holds if we cut, then fail." The engine commits to that first
rule via `cut` — promising not to try the *second* rule ("p holds,
unconditionally," which would have succeeded immediately) — and only
*then* hits `fail`. Since it already gave up the alternative, there's
nothing left to try, and the whole question comes back with zero
answers, even though a rule that would have said "yes" was sitting
right there. This is the textbook example precisely because it's
counter-intuitive on first read — a plain "stop backtracking from here
on" wouldn't produce this result, but "undo the choice that got us into
this rule at all" does.

A cut is scoped to the one rule it appears in — it can never reach
backward into whatever *called* that rule and prune the caller's own
alternatives. `call/N`, `once/1`, and `not/1` all wall off cut the same
way. See the moduledoc on `Episteme.Engine` for the full mechanism if
you're curious how a real, ISO-accurate cut like this is built on top
of a search process that doesn't have cut as a primitive at all.

## 7. Arithmetic

`X is Expr` means "compute the arithmetic value of `Expr`, and set `X`
to it" — it's the odd one out among everything so far, because it
*calculates* rather than just checking whether two things can be made
to match. (`is(X, 2+2)` and `unify(X, 2+2)` are very different
questions: the first asks "what does 2+2 come out to," the second asks
"does X already look exactly like the unevaluated expression `2+2`.")

```elixir
Episteme.query(c.(:is, [Term.new_var("X"), c.(:+, [2, c.(:*, [3, 4])])]), Database.new())
#=> {:ok, [%{"X" => 14}]}
```

"What is X, if X is 2 plus (3 times 4)?" — ordinary arithmetic
precedence, evaluated to `14`.

See [CHEATSHEET.md](CHEATSHEET.md) for the full table of evaluable
functors and comparisons (`numeric_equal`, `<`, etc.), plus `between/3`
for generating integers.

## 8. Lists

Lists are plain Elixir lists. `member/2` asks "is X one of the elements
of this list — and if X is a blank, what are *all* the things it could
be?":

```elixir
Episteme.query(c.(:member, [Term.new_var("X"), [:a, :b, :c]]), Database.new())
#=> {:ok, [%{"X" => :a}, %{"X" => :b}, %{"X" => :c}]}
```

Three answers, one per element — "X could be a," "X could be b," "X
could be c." `append/3`, `length/2`, and friends
([CHEATSHEET.md](CHEATSHEET.md#lists)) generalize the same way: they
don't just check a fully-known list, they can *search* for a list that
fits, filling in blanks as needed.

## 9. Exceptions

`throw/1` and `catch/3` work like raising and rescuing an error
anywhere else: `throw(Ball)` abandons the current computation carrying
a value (`Ball`); `catch(Goal, Catcher, Recovery)` runs `Goal`, and if
it throws something matching `Catcher`, runs `Recovery` instead of
letting the exception escape further. An uncaught throw doesn't crash
your Elixir process — it comes back from `Episteme.query/2` as an
ordinary `{:error, term}` value.

```elixir
x3 = Term.new_var("X")
y3 = Term.new_var("Y")
r3 = Term.new_var("R")
catcher = c.(:error, [Term.new_var("_"), Term.new_var("_")])
body2 = c.(:catch, [c.(:is, [r3, c.(:/, [x3, y3])]), catcher, c.(:unify, [r3, :undefined])])

db5 = Database.add_clause(Database.new(), {c.(:safe_div, [x3, y3, r3]), body2})

Episteme.query(c.(:safe_div, [10, 0, Term.new_var("R")]), db5)
#=> {:ok, [%{"R" => :undefined}]}
```

`safe_div(X, Y, R)` means "R is X divided by Y — unless that division
raises an error, in which case R is `:undefined`." Dividing by zero
normally throws (division has no answer), but here it's wrapped in a
`catch` that quietly recovers instead of the whole question blowing up:
asking `safe_div(10, 0, R)` gets back `R = :undefined` rather than an
`{:error, ...}` result.

## 10. Dynamic database: assert and retract

Everything so far built the database once, up front, and only asked
questions against it. `assertz/1`/`asserta/1` (insert a fact or rule
*right now*, while a query is running) and `retract/1`/`retractall/1`
(remove one) turn the database into something closer to an actual
mutable table you can `INSERT`/`DELETE` from live, rather than a fixed
set of statements decided in advance. Crucially, these changes are
**not** undone if the question that made them goes on to fail or
backtrack later — an insert is a real insert, not a "let's try this and
see" hypothetical.

```elixir
db6 = Database.new()

Episteme.query(c.(:assertz, [c.(:seen, [:tom])]), db6)
Episteme.query(c.(:seen, [:tom]), db6)
#=> {:ok, [%{}]}

Episteme.query(c.(:retract, [c.(:seen, [:tom])]), db6)
Episteme.query(c.(:seen, [:tom]), db6)
#=> {:ok, []}
```

Reading through it: we start with an empty database, insert the fact
"tom has been seen," confirm asking `seen(tom)` now answers yes, then
delete that same fact, and confirm asking again now answers "no
matches." Both `assertz`/`retract` calls and both `seen(tom)` checks
are *separate* calls to `Episteme.query/2` — the change made by the
first call is still there when the third call runs, because `db6` is
the same database value throughout, and mutating it is exactly what
`assertz`/`retract` do.

This is what makes Episteme useful for more than "check some fixed
rules" — a long-lived process can hold a `Database.t()` and grow or
shrink its own knowledge over time: a cache, a game's world state, a
session's accumulated facts. See [EXAMPLES.md](EXAMPLES.md) for a small
key-value store built exactly this way.

## 11. Collecting every solution: findall and forall

So far, asking a question gets back a *list of answers* automatically.
`findall/3` and `forall/2` are for when a question itself — inside a
rule you're writing — needs to look at "all the answers to this
sub-question" as a single value, the way a report might need "the list
of every matching row," not just "does at least one row match."

`findall(Template, Goal, List)` reads as "find every way to make `Goal`
true, and for each one, collect what `Template` came out to — put them
all in `List`." If there are no matches at all, `List` comes back `[]`
— that's a real, valid answer, not an error:

```elixir
db7 =
  Database.new()
  |> Database.add_fact(c.(:fruit, [:apple]))
  |> Database.add_fact(c.(:fruit, [:pear]))

fx = Term.new_var()
Episteme.query(c.(:findall, [fx, c.(:fruit, [fx]), Term.new_var("L")]), db7)
#=> {:ok, [%{"L" => [:apple, :pear]}]}
```

"Collect every X such that `fruit(X)` holds, into L" — the database
knows about `:apple` and `:pear`, so `L` comes back `[:apple, :pear]`.

`fx` above is deliberately *anonymous* (`Term.new_var/0` defaults its
name to `"_"`) — a *named* variable used only inside `findall/3`'s
template/goal, and nowhere else in the top-level question, would come
back in the answer too, unbound, the same way asking "is X a variable?"
reports back what X was (see §2) rather than silently dropping it. See
`Episteme`'s moduledoc, or the `var/nonvar` test in the test suite, for
more on that convention.

`forall(Cond, Action)` is a yes/no check, not a collector: "is it true
that *every* way of satisfying `Cond` also satisfies `Action`?" — useful
for "check this holds across the board" without ever building a list of
results at all.

## 12. Choosing a storage backend

Everything above stored its facts in memory — `Database.new/1` defaults
to an in-memory table, organized by each fact or rule's name and number
of fields so looking one up is fast, that disappears once your program
stops. For a database that should still be there the *next* time you
start the program — a notebook you can put away and pick back up,
rather than scratch paper — pass the disk-backed option and a file path
instead:

```elixir
db8 = Database.new(backend: Episteme.Database.Backends.Dets, file: "facts.dets")
Episteme.query(c.(:assertz, [c.(:fact, [1])]), db8)
Database.sync(db8)
Database.close(db8)

# ... later, possibly in a different process or after a restart ...
reopened = Database.new(backend: Episteme.Database.Backends.Dets, file: "facts.dets")
Episteme.query(c.(:fact, [Term.new_var("X")]), reopened)
#=> {:ok, [%{"X" => 1}]}
```

We insert a fact, flush it to disk (`sync/1`), and close the file
(`close/1`); reopening the *same file* later — potentially a completely
separate run of the program — finds that fact still there. The
in-memory and on-disk versions behave identically from a query's point
of view; only how long the data survives differs.

Any other storage strategy is a matter of implementing
`Episteme.Database.Backend`'s five callbacks. See the moduledoc on that
module, or just read `Episteme.Database.Backends.Ets` — at ~30 lines,
it's the whole contract in miniature.

## 13. Lower-level: query_lazy/2 and next_solution/2

`Episteme.query/2` computes *every* answer before handing anything
back. That's fine when there are a handful of answers, but some
questions have unboundedly many (`member(X, List)` with `List` itself
left as an unfilled blank, say) — for those, or for a REPL that only
wants to show the first few answers and stop, ask for answers one at a
time instead:

```elixir
{stream, vars} = Episteme.query_lazy(c.(:member, [Term.new_var("X"), [:a, :b, :c]]), Database.new())
Episteme.next_solution(stream, vars)
#=> {:solution, %{"X" => :a}, rest}
```

Think of `stream` as a cursor into an open-ended list of answers:
`next_solution/2` pulls the next one — `{:solution, answer, rest}` — and
hands back a *new* cursor (`rest`) to keep going from, or `:none` once
there's nothing left. Keep pulling on the latest `rest` for as many
answers as you want, then just stop — there's no need to exhaust it.

## Where next

- [REFERENCE.md](REFERENCE.md) — every feature covered here (and a few
  that weren't) in full detail, one section per construct/predicate,
  each with its own verified example.
- [CHEATSHEET.md](CHEATSHEET.md) — every built-in goal and Elixir-side
  function, in one page.
- [EXAMPLES.md](EXAMPLES.md) — complete, runnable programs (a family
  tree, graph reachability, a key-value store, FizzBuzz, and more).
- [CONTRIBUTING.md](CONTRIBUTING.md) — if you want to change Episteme
  itself.
- The moduledoc on `Episteme.Engine` — the cut mechanism in particular
  is worth reading if you're curious how a real clause-scoped cut is
  built on top of a lazy backtracking search tree without modifying
  that search tree's own combinators at all.
