# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- DCG (Definite Clause Grammar) support, closing out v0.5: a new
  `Episteme.Dcg` module (`translate_rule/2`, `translate_body/3`)
  translates a `Head --> Body` rule into an ordinary clause, threading
  an incoming/outgoing difference-list pair through every nonterminal
  call. A practical subset of real DCG translation -- terminals,
  `{Goal}` (ISO's own `'{}'/1` embedded-goal shape), `cut`, `and/2`,
  `or/2`, `if_then/2`, `if_then_else/3`, `not/1`, a bare nonterminal,
  and a variable body (`phrase(Var, S0, S)`) -- deliberately not all of
  it (no `call//N` pushback). `phrase/2,3` (`Episteme.Engine`) runs a
  DCG body as an ordinary goal; `dcg_translate/2` is the readable
  `-->/2` alias for introspection; a new `{:dcg, head, body}`
  `Episteme.Database.consult_forms/2` form and `-->/2`-shaped
  `assert/1` (same as `:-/2` is already special-cased) both translate
  and store. See
  [REFERENCE.md](REFERENCE.md#dcg-definite-clause-grammars).
- `format/1` and `format/2`, closing out v0.4 entirely. A practical
  subset of ISO/SWI's own directive set (`~w`/`~p`/`~q` -- all the same
  thing here, `Term.to_text/1` -- `~a`, `~d`, `~s`, `~i`, `~n`, `~~`),
  deliberately not all of it (no column/radix directives, no
  numeric-prefixed `~Nd`). `Args` is normally a proper list, one
  element consumed per directive left to right; a single non-list
  `Args` is treated as `[Args]`, matching SWI's own leniency. Lives in
  `Episteme.Builtins.Io` alongside `write/1` and friends, reusing
  `Episteme.Builtins.Strings.require_atomic_text/2` for the format
  string itself. See [REFERENCE.md](REFERENCE.md#format1-and-format2).
- A real string type -- a genuinely new atomic term class, backed by
  plain Elixir binaries with no wrapper struct (the same
  "raw host-language value" pattern atoms/integers/floats already use),
  not ISO's own code-list default (see `string_type_decision`,
  DESIGN.md). `"abc"` now unifies with `"abc"` by exact byte equality
  and never with `[97,98,99]` or `abc` -- both structurally distinct
  from a string. Standard order of terms gained a fourth class between
  atom and compound (`Var < Number < Atom < String < Compound`), and a
  new `string/1` type check joins `atom/1`/`atomic/1` (the latter now
  also true for strings). Alongside it, the v0.4 atom/number/string
  conversion family, in a new `Episteme.Builtins.Strings`:
  `atom_codes/2`, `atom_chars/2`, `atom_length/2`, `atom_concat/3`,
  `sub_atom/5`, `char_code/2`, `number_codes/2`, `number_chars/2`,
  `upcase_atom/2`, `downcase_atom/2`, `atomic_list_concat/2,3`
  (classic ISO/de-facto, working with atoms), and their SWI-style real-
  string counterparts `atom_string/2`, `string_to_atom/2`,
  `string_concat/3`, `string_chars/2`, `string_codes/2`,
  `string_length/2`, `number_string/2`, `split_string/4`. `atom_concat/3`,
  `string_concat/3`, and `sub_atom/5` all enumerate every matching
  decomposition on backtracking (the same "generate every candidate,
  let unify filter it" shape `append/3` already uses over lists) rather
  than needing separate deterministic/nondeterministic code paths. See
  [REFERENCE.md](REFERENCE.md#atom-number-and-string-conversions).
- `bagof/3` and `setof/3`, completing the v0.3 aggregation family
  alongside the existing `findall/3`. Unlike `findall/3`, both fail
  outright (not `List = []`) when the goal has no solutions, and group
  solutions by the goal's own free variables (every variable it
  mentions that isn't in `Template` and isn't existentially quantified
  via `Var^Goal`), backtracking one solution per distinct group.
  `setof/3` additionally sorts and dedups each group (and orders the
  groups themselves) by standard order of terms. Built on two new
  `Episteme.Term` functions, `term_variables/1` (real Prolog's
  `term_variables/2`, not itself exposed as a goal yet) and
  `sort_by_order/1`/`sort_unique/1` (the latter two also now shared by
  `msort/2`/`sort/2`, replacing what used to be private duplicate logic
  in `Episteme.Builtins.Lists`). See
  [REFERENCE.md](REFERENCE.md#bagof3-and-setof3).

- Rounds out the dynamic-database family: `abolish/1` (unlike
  `retractall/1`, undefines the predicate too -- a later call raises
  `existence_error` again) and `dynamic/1` (declares a predicate
  defined with zero clauses, so a call fails instead of raising
  `existence_error`, and `assert`/`retract` work on it immediately;
  accepts a single `Name/Arity` or a list of them). Both build on two
  new `Episteme.Database` functions, `abolish/3` and
  `declare_dynamic/3`, and a new `Episteme.Database.Backend` callback
  (`abolish/3`, implemented in both `Backends.Ets` and `Backends.Dets`).
  Also `clause/2`: enumerates every stored clause for `Head`'s own
  `{name, arity}` whose head unifies with it, one per backtrack. See
  [REFERENCE.md](REFERENCE.md#dynamic-database).
- The rest of the v0.2 list-predicate family: `msort/2`, `sort/2`,
  `permutation/2`, `sum_list/2`, `max_list/2`, `min_list/2`, and
  `list_to_set/2` (pure operations, in `Episteme.Builtins.Lists`, all
  built on `Term.compare_order/2`) alongside `include/3`, `exclude/3`,
  `foldl/4` (plus `/5`/`/6` for 2–3 lists in lockstep), and
  `maplist/2..N` (higher-order -- these call a `Goal` per element via
  the same mechanism as `call/N`, so they live directly in
  `Episteme.Engine`, next to `call/N` itself, not in a Builtins
  module). See
  [REFERENCE.md](REFERENCE.md#higher-order-list-predicates).
- Standard order of terms: `order_less/2`, `order_greater/2`,
  `order_less_or_equal/2`, `order_greater_or_equal/2` (real Prolog
  `@<`, `@>`, `@=<`, `@>=`), and `compare/3` (already a plain word in
  ISO, so it keeps its name). A total order over every term (`Var <
  Number < Atom < Compound`), not just numbers — see
  [REFERENCE.md](REFERENCE.md#matching-and-comparing-values) for the
  full within-class ordering rules (float-before-int on equal value,
  alphabetical atoms, arity-then-name-then-args for compounds).
  `Episteme.Term.compare_order/2` is the underlying whole-term
  operation, alongside `structurally_equal?/2` and `resolve_deep/2`.
- Term construction and inspection: `functor/3`, `arg/3`, `univ/2`
  (real Prolog `=..`), and `ground/1` (alongside the existing type
  checks). `functor/3` and `univ/2` both work in either direction —
  decomposing an already-bound term, or building a fresh one from a
  name/arity or `[Name | Args]` list. See
  [REFERENCE.md](REFERENCE.md#term-construction-and-inspection).
- Closes out the v0.2 predicate catalog: `ignore/1` (like `once/1`, but
  never fails — succeeds with bindings unchanged if the goal has no
  solution; equivalent to `(call(Goal) -> true ; true)`) and
  `unify_with_occurs_check/2` (like `unify/2`, but rejects a variable
  binding to a compound term that already contains it, instead of
  silently building an infinite term — built on
  `Ichor.Backtrack.Bindings.unify_occurs_check/4`, already present in
  `ichor_runtime` but not previously wired up as a callable goal). See
  [REFERENCE.md](REFERENCE.md#ignore1) and
  [REFERENCE.md](REFERENCE.md#unify_with_occurs_check2). Also
  `existence_error/2`, exposed as a directly-callable goal alongside
  `type_error/2`/`domain_error/2`/`instantiation_error/1` -- previously
  only ever thrown internally (on an undefined-predicate call) -- and
  the last five evaluable functors: `sin/1`, `cos/1`, `tan/1`, `exp/1`,
  `log/1` (natural log), alongside the existing `sqrt/1` in
  `Episteme.Builtins.Arithmetic`. This closes out the full v0.2
  predicate catalog.

## [0.1.0] - 2026-08-04

### Added

- Initial extraction from [Aletheia](https://hex.pm/packages/aletheia):
  term representation, clause database, SLD-resolution engine (with a
  genuine clause-scoped cut), and the arithmetic/exceptions/lists/io
  builtin predicates, split out into their own package so they're
  usable without Aletheia's reader/syntax layer.
- A dynamic database: `assert/1`, `asserta/1`, `assertz/1`, `retract/1`,
  `retractall/1`. Effects persist across separate `Episteme.query/2`
  calls against the same `Database.t()`, not just within one.
- Solution aggregation: `findall/3`, `forall/2`.
- `between/3` in `Episteme.Builtins.Arithmetic`.
- Pluggable clause storage via the new `Episteme.Database.Backend`
  behaviour: `Episteme.Database.Backends.Ets` (the default, in-memory,
  indexed by `{name, arity}`) and `Episteme.Database.Backends.Dets` (the
  same shape, persisted to disk). `Database.new/1` takes a `:backend`
  option; `Database.close/1` and `Database.sync/1` are new.
- [TUTORIAL.md](TUTORIAL.md) (a from-scratch walkthrough),
  [REFERENCE.md](REFERENCE.md) (every control construct, comparison,
  type check, arithmetic feature, and exception/database/list/I/O
  predicate, in full detail with a verified example each),
  [EXAMPLES.md](EXAMPLES.md) (complete, verified-runnable programs),
  [CHEATSHEET.md](CHEATSHEET.md) (a one-page predicate/function
  reference), and [CONTRIBUTING.md](CONTRIBUTING.md).

### Changed

- **Breaking:** control constructs and comparison operators are now
  spelled as plain English words instead of ISO Prolog's punctuation
  operators, since Episteme has no reader of its own for that
  punctuation to be conventional syntax against:
  - `,` → `and/2`, `;` → `or/2`, `!` → `cut`, `\+` → `not/1`
  - `(Cond -> Then ; Else)` → `if_then_else/3` (new, explicit 3-arity
    goal, replacing the old "`;` wrapping a `->`" nested-pattern
    special case); `(Cond -> Then)` → `if_then/2`
  - `=` → `unify/2`, `\=` → `not_unify/2`, `==` → `equal/2`,
    `\==` → `not_equal/2`
  - `=:=` → `numeric_equal/2`, `=\=` → `numeric_not_equal/2`,
    `=<` → `less_or_equal/2`, `>=` → `greater_or_equal/2`
  - `+`, `-`, `*`, `/`, `<`, `>` are unchanged — ordinary math notation,
    not Prolog-specific punctuation, and arithmetic expression functors
    (`+`, `-`, `*`, `/`, `//`, `mod`, `rem`, `**`, `^`, `abs`, `sign`,
    `min`, `max`, `sqrt`) are entirely unaffected, since those were
    never goals to begin with.
  No aliases: the old symbol-based names are gone, not deprecated.
- **Breaking:** `Database.t()` now wraps a mutable backend resource
  (an ETS table by default) rather than being a plain immutable struct
  — `assert`/`retract` need a database whose mutations are visible to
  every holder of the same value. `add_clause/2`, `add_fact/2`,
  `clauses_for/3`, `defined?/3`, `indicator/1`, and `consult_forms/2`
  keep their existing signatures and behavior; `Database.new/0` still
  works exactly as before (now sugar for `Database.new([])`).
- The `precommit` alias now runs `sobelow --skip`, honoring the
  `# sobelow_skip [...]` justification comment on `Episteme.query_once/2`
  (a documented low-confidence false positive) instead of only silencing
  it by happenstance of `sobelow`'s own default exit code.
- `ichor_runtime` requirement bumped from `~> 0.1.0` to `~> 0.2`,
  resolving to `0.2.0`. That release's breaking change (`raw_captures`
  becoming an ordered list of pairs instead of a map) is confined to
  `Ichor.Actions`/`Ichor.Capture`/the grammar runtime, none of which
  Episteme touches — it only uses `Ichor.Backtrack.*` and
  `Ichor.Toolkit.TermWalk`, both unaffected, so this is a no-op for
  Episteme's own behavior.

### Fixed

- `Episteme.query/2` (and `query_once/2`/`query_lazy/2`) no longer
  crashes with a raw `FunctionClauseError` when a partial list (one
  ending in a variable or other non-list, non-`[]` tail, e.g. `[1 | X]`)
  appears anywhere in the top-level goal — the internal walk that finds
  which variables to report in the answer used `Enum.reduce/3`, which
  only works on proper (nil-terminated) lists.
- `length/2` with an unbound list and a bound count built one fresh
  variable and duplicated the *same* one that many times instead of
  generating independent fresh variables, so e.g.
  `and(length(L, 3), unify(L, [a, b, c]))` wrongly failed (the shared
  variable couldn't unify with two different values at once).
- The package `description` in `mix.exs` exceeded Hex's 300-character
  limit, so `mix hex.build` (and thus `mix hex.publish`, and the CI
  job that runs `hex.build` to verify the package assembles) failed
  outright. Trimmed to fit while keeping the same content.
