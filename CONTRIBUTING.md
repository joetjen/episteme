# Contributing

Thanks for considering a contribution to Episteme. This document covers
the mechanics — workflow, commit style, what has to pass before a
change lands — and assumes you're already comfortable with the
Prolog/logic-programming vocabulary it uses (unify, clause, cut-opaque,
...); if any of that's new, [TUTORIAL.md](TUTORIAL.md) explains it from
scratch, [REFERENCE.md](REFERENCE.md) covers every feature in full
detail, and [CHEATSHEET.md](CHEATSHEET.md#terms-used-on-this-page) has a
compact glossary. For how the library itself is put together, start
with [README.md](README.md#how-it-fits-together) and the moduledoc on
`Episteme.Engine`.

## Before every commit

Run `mix precommit` and make sure it passes. No exceptions. It runs, in
order (fast/cheap checks first, so a broken commit fails quickly):

```sh
mix format
mix compile --warnings-as-errors
mix credo --strict
mix sobelow --skip
mix test
mix dialyzer
```

`mix dialyzer`'s first run builds a PLT and is slow; every run after
that is fast. If `mix precommit` isn't defined for some reason, it's an
alias in `mix.exs` — check it's still there rather than running the
steps ad hoc.

## Git workflow

This repository uses [git flow](https://nvie.com/posts/a-successful-git-branching-model/):
`main` (releases), `develop` (integration), `feature/*`, `release/*`,
`hotfix/*`, `support/*`.

- No direct commits to `main` or `develop`.
- Branch off `develop` (`feature/your-thing`), open a PR back into
  `develop` when it's ready.
- Only `release/*`/`hotfix/*` branches merge into `main`.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/):
`<type>[optional scope]: <description>`.

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`chore`, `build`, `ci`. Breaking changes get a `!` after the type/scope
(`feat!: ...`) or a `BREAKING CHANGE:` footer.

## Tests

- A change to what code does needs its tests updated in the *same*
  commit, not "later" — a passing suite that no longer exercises real
  current behavior is worse than a failing one.
- Add tests for new behavior as you write it.
- Where the input space is bigger than a handful of examples usefully
  covers — parsers, encoders/decoders, merge/normalization logic,
  anything with an invariant that should hold for *all* inputs, not
  just the ones you thought of — prefer a property-based test (this
  project depends on `stream_data` for exactly this; see the
  `describe "invariants over arbitrary ground terms"` block in
  `test/episteme/term_test.exs` for the pattern) over enumerating more
  example cases by hand. Ordinary example-based tests are still right
  for fixed, specific scenarios and regressions.
- If you add a predicate that mutates the database (anything in the
  `assert`/`retract` family) or that runs a sub-goal (`findall`,
  `forall`, `call`, `once`, `\+`, `catch`), write at least one test that
  checks it's cut-opaque and, separately, one that checks what it does
  or doesn't bind in the caller — those two properties are exactly what
  bites people writing Prolog-like engines, and exactly what's easy to
  get subtly wrong.
- **A trap worth knowing about**: in Elixir, `%{}` (and any partial map)
  as a *pattern* matches any map with at least those keys — `%{} = %{"X" => 1}`
  succeeds. `{:ok, [%{}]} = Episteme.query(goal, db)` does **not** assert
  the solution has no bindings; it only asserts `query/2` returned one
  solution that's some kind of map. If you want to assert "no named
  variables are bound," compare with `==` against the exact expected
  map instead of pattern-matching a subset of it.

## Documentation

- Every public module needs a `@moduledoc`. Every public function needs
  a `@doc`.
- Update `@moduledoc`/`@doc` whenever behavior changes — stale docs are
  worse than none.
- If your change is user-visible, update the relevant doc(s) in the same
  commit: [README.md](README.md) for anything about how the library
  fits together, [TUTORIAL.md](TUTORIAL.md) if it changes how someone
  learns the library, [EXAMPLES.md](EXAMPLES.md) if it changes how a
  worked example behaves, [CHEATSHEET.md](CHEATSHEET.md) for a new or
  changed predicate/function. If you add a code example to any doc,
  actually run it (`mix run` a scratch script, or `iex -S mix`) before
  committing it — a plausible-looking Prolog example that was never
  executed is exactly how a doc bug gets shipped; solution-map ordering
  and which variables end up bound are both easy to get wrong by hand.
- Update [CHANGELOG.md](CHANGELOG.md) for every user-facing change,
  following [Keep a Changelog](https://keepachangelog.com/): add entries
  under `[Unreleased]` as you work. On release, entries move under a
  version heading and the (now-empty) `[Unreleased]` section is removed.

## Static analysis findings

A new low-confidence Sobelow or Dialyzer finding isn't automatically
wrong, but isn't automatically fine either. Give it a specific
justification, not a blanket suppression:

- **Sobelow**: a `# sobelow_skip ["Check.Name"]` comment directly above
  the flagged function (no colon after `sobelow_skip` — that breaks the
  regex Sobelow matches on), plus a comment explaining why it's a false
  positive for *this* function specifically. See `Episteme.query_once/2`
  for the pattern. `mix precommit` runs `sobelow --skip` so the skip
  actually takes effect.
- **Dialyzer**: a targeted `@dialyzer {:nowarn_function, fun: arity}`
  naming the exact function, with a comment on why the warning doesn't
  apply. See the private `append_cons/5` in
  `lib/episteme/builtins/lists.ex` for the pattern (an intentionally
  improper list, which Dialyzer's `improper_list_constr` check doesn't
  expect).

## Dependency boundaries

If you touch `mix.exs` deps or `lib/`, and a dependency is scoped
`only: [:dev, :test]`/`runtime: false` specifically to keep it out of a
production build (`credo`, `dialyxir`, `sobelow`, `excoveralls`,
`ex_doc` all are), double-check that scoping still holds — e.g. that
nothing under `lib/` now references one of them — rather than assuming
it's untouched.

## Versioning

[Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.
`MAJOR` for breaking changes, `MINOR` for backward-compatible features,
`PATCH` for backward-compatible fixes. Bump the version in `mix.exs` as
part of a release, matching the changelog entry.

## Adding a new predicate

If you're adding a new builtin predicate rather than changing an
existing one, a few things to decide, roughly in order:

1. **Does it need engine internals** (the cut barrier, `Tree.next` to
   force a sub-goal early, mutating the `Database.t()` it's given)? If
   so it belongs directly in `Episteme.Engine`'s `dispatch/4` clauses —
   `findall/3`, `assert/1`, and `\+/1` are all this shape. If it's a
   self-contained goal that only needs unification (`Bindings.unify`)
   and doesn't need to look inside the engine's own search machinery, it
   belongs in a `Episteme.Builtins.*` module instead, dispatched through
   that module's `dispatch/3` and chained into `Episteme.Engine`'s
   catch-all `dispatch/4` clause (see how `Arithmetic`/`Lists`/`Io` are
   wired in).
2. **Which existing `Builtins` module does it belong to** — arithmetic,
   list-shaped, I/O, or none of the above (a new module is fine; update
   `mix.exs`'s `groups_for_modules` if so).
3. Match ISO/SWI-Prolog semantics for modes (which arguments can be
   unbound), error conditions (`type_error`/`domain_error`/
   `instantiation_error`, via `Episteme.Builtins.Exceptions`), and
   whether it's cut-opaque, unless there's a specific reason to diverge
   — and if you do diverge, say so in the `@moduledoc`/`@doc`, the way
   `Episteme.Engine`'s moduledoc explains why cut isn't `once/1`.
4. Add it to [CHEATSHEET.md](CHEATSHEET.md) and, if it's something a
   newcomer would plausibly reach for, [TUTORIAL.md](TUTORIAL.md) or
   [EXAMPLES.md](EXAMPLES.md) too.

## Generated/checked-in files

`doc/` (from `mix docs`) is generated and gitignored — never hand-edit
it or commit it.
