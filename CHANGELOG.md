# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
