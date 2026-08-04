# Case study: auditing structured application logs

Every other example in [EXAMPLES.md](EXAMPLES.md) is deliberately
small — one feature, one paragraph, one screenful. This one is
deliberately not: a single, complete, real-world-shaped program that
walks through *why* you'd reach for Episteme, not just *how* to call
one predicate. It assumes you're comfortable with the vocabulary from
[TUTORIAL.md](TUTORIAL.md) and pulls in a feature from nearly every
corner of the library — a DCG grammar, the dynamic database,
aggregation with existential quantification, and `format/2` — to solve
one coherent problem rather than eight disconnected ones.

## 0. Shared setup

```elixir
alias Episteme.{Database, Term}
alias Episteme.Term.Compound
c = fn name, args -> %Compound{name: name, args: args} end
embed = fn goal -> %Compound{name: :{}, args: [goal]} end
```

`c` is the same shorthand [EXAMPLES.md §0](EXAMPLES.md#0-shared-setup)
uses. `embed` is new here: it wraps an ordinary goal as `{Goal}` —
ISO's own `'{}'/1` term shape — the way you drop a plain predicate
call into the middle of a DCG body without it being treated as
grammar.

## Intent

A lot of real services — Heroku's own routing layer, most Go and Rust
web frameworks, plenty of hand-rolled ones — emit logs in
[logfmt](https://brandur.org/logfmt): one line per event, space-separated
`key=value` pairs, no fixed schema beyond a handful of conventional
fields. A line looks like this:

```text
ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5
```

Say you want a small audit tool over a stream of these: flag any
**user with repeated failed logins** (a brute-force indicator), and
separately flag any **IP address behind failed logins for more than
one distinct user** (a credential-stuffing indicator — one attacker,
many stolen usernames, one source). Both are real heuristics real
fraud/security tooling actually uses, and both are naturally
*relational* questions — "group these facts by X, then check something
about each group" — which is exactly the shape logic programming is
for.

Three things about Episteme fit this well:

- **No parser of its own, but a DCG when you need one.** Episteme
  doesn't ship a `logfmt` reader — nothing does, out of the box — but
  [DCG support](REFERENCE.md#dcg-definite-clause-grammars) lets you
  write the grammar as a grammar, not a hand-rolled loop of string
  splits.
- **A mutable database for a line-at-a-time stream.** Log lines arrive
  one at a time, not as a batch you already have in memory; the
  [dynamic database](REFERENCE.md#dynamic-database) (`assertz/1`) is
  built for exactly that.
- **Aggregation that groups for you.** "Which users have ≥ 3 failed
  logins" and "which IPs are shared across users" are both grouping
  queries — [`setof/3`](REFERENCE.md#bagof3-and-setof3)'s
  free-variable grouping does the work a hand-written accumulator
  would otherwise need.

## Solution

### Parsing: a DCG grammar for logfmt lines

Tokenizing on whitespace is just `String.split/1` — Elixir already
does that well, so there's no reason to reinvent it inside Episteme.
What the grammar below owns is everything *after* that: recognizing
the shape of a line (four required fields in order, then a
variable-length tail of arbitrary ones) and pulling each `key=value`
token apart.

`any_field/2` consumes exactly one token and splits it around `=`:

```elixir
af_key = Term.new_var("Key")
af_value = Term.new_var("Value")
af_token = Term.new_var("Token")
af_key_str = Term.new_var("KeyStr")

any_field_head = c.(:any_field, [af_key, af_value])

any_field_body =
  c.(:and, [
    [af_token],
    embed.(
      c.(:and, [
        c.(:split_string, [af_token, "=", "", [af_key_str, af_value]]),
        c.(:atom_string, [af_key, af_key_str])
      ])
    )
  ])

db = Database.add_clause(Database.new(), Episteme.Dcg.translate_rule(any_field_head, any_field_body))
```

Read the DCG body the way `Episteme.Dcg` reads it: `[af_token]` is a
one-element *terminal* — "consume the next token from the input and
call it `af_token`" (a terminal doesn't have to be a literal; a
variable inside one just captures whatever's there). The `embed.(...)`
half is an ordinary goal, spliced in without touching the input list:
[`split_string/4`](REFERENCE.md#split_string4) breaks `"level=warn"`
into `["level", "warn"]`, and
[`atom_string/2`](REFERENCE.md#atom_string2-and-string_to_atom2) turns
`"level"` into the atom `:level` so field names can be matched and
grouped on later. `Database.add_clause/2` plus
`Episteme.Dcg.translate_rule/2` (rather than `consult_forms/2`'s
`{:dcg, ...}` shorthand) is the direct call the shorthand itself
builds on, and reads consistently with how every other rule in this
file gets stored.

`fields/1` is the variable-length tail: zero or more `any_field/2`
matches, collected into a list.

```elixir
db = Database.add_clause(db, Episteme.Dcg.translate_rule(c.(:fields, [[]]), []))

fc_k = Term.new_var("K")
fc_v = Term.new_var("V")
fc_rest = Term.new_var("Rest")

fields_cons_head = c.(:fields, [[c.(:field, [fc_k, fc_v]) | fc_rest]])
fields_cons_body = c.(:and, [c.(:any_field, [fc_k, fc_v]), c.(:fields, [fc_rest])])

db = Database.add_clause(db, Episteme.Dcg.translate_rule(fields_cons_head, fields_cons_body))
```

Same recursive shape as `sum_list/2` in
[EXAMPLES.md §7](EXAMPLES.md#7-writing-your-own-recursive-list-rule):
an empty-list base case, and a case that peels one `field(K, V)` off
the front and recurses on the rest — except here the recursion is
consuming *tokens*, not walking an already-built list.

`log_line/5` ties it together: four required fields in a fixed order,
each converted to an atom, then whatever's left goes through
`fields/1`:

```elixir
ll_ts = Term.new_var("Ts")
ll_level = Term.new_var("Level")
ll_level_str = Term.new_var("LevelStr")
ll_component = Term.new_var("Component")
ll_component_str = Term.new_var("ComponentStr")
ll_event = Term.new_var("Event")
ll_event_str = Term.new_var("EventStr")
ll_fields = Term.new_var("Fields")

log_line_head = c.(:log_line, [ll_ts, ll_level, ll_component, ll_event, ll_fields])

log_line_body =
  c.(:and, [
    c.(:any_field, [:ts, ll_ts]),
    c.(:and, [
      c.(:any_field, [:level, ll_level_str]),
      c.(:and, [
        embed.(c.(:atom_string, [ll_level, ll_level_str])),
        c.(:and, [
          c.(:any_field, [:component, ll_component_str]),
          c.(:and, [
            embed.(c.(:atom_string, [ll_component, ll_component_str])),
            c.(:and, [
              c.(:any_field, [:event, ll_event_str]),
              c.(:and, [
                embed.(c.(:atom_string, [ll_event, ll_event_str])),
                c.(:fields, [ll_fields])
              ])
            ])
          ])
        ])
      ])
    ])
  ])

db = Database.add_clause(db, Episteme.Dcg.translate_rule(log_line_head, log_line_body))
```

`any_field(:ts, Ts)` deliberately leaves the timestamp as a string
rather than converting it to an atom like the other three — ISO 8601
timestamps sort correctly as plain byte strings, so there's no need to
parse them any further for what this audit actually asks. Trying the
grammar directly with [`phrase/2`](REFERENCE.md#phrase2-and-phrase3):

```elixir
line = "ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5"

parse_goal =
  c.(:phrase, [
    c.(:log_line, [
      Term.new_var("Ts"),
      Term.new_var("Level"),
      Term.new_var("Component"),
      Term.new_var("Event"),
      Term.new_var("Fields")
    ]),
    String.split(line)
  ])

Episteme.query(parse_goal, db)
#=> {:ok, [%{
#     "Ts" => "2026-08-05T10:15:32Z",
#     "Level" => :warn,
#     "Component" => :auth,
#     "Event" => :login_failed,
#     "Fields" => [
#       %Episteme.Term.Compound{name: :field, args: [:user, "alice"]},
#       %Episteme.Term.Compound{name: :field, args: [:ip, "203.0.113.5"]}
#     ]
#   }]}
```

### Rules over the parsed facts

Every line becomes a `log_entry(Ts, Level, Component, Event, Fields)`
fact once parsed. `field_value/3` is a lookup into that trailing
`Fields` list, built directly on the [`member/2`](CHEATSHEET.md#lists)
builtin:

```elixir
fv_fields = Term.new_var("Fields")
fv_key = Term.new_var("Key")
fv_value = Term.new_var("Value")

db =
  Database.add_clause(
    db,
    {c.(:field_value, [fv_fields, fv_key, fv_value]),
     c.(:member, [c.(:field, [fv_key, fv_value]), fv_fields])}
  )
```

`failed_login/3` picks out the one event shape the rest of this cares
about:

```elixir
fl_user = Term.new_var("User")
fl_ip = Term.new_var("Ip")
fl_ts = Term.new_var("Ts")
fl_fields = Term.new_var("Fields")

db =
  Database.add_clause(
    db,
    {c.(:failed_login, [fl_user, fl_ip, fl_ts]),
     c.(:and, [
       c.(:log_entry, [fl_ts, :warn, :auth, :login_failed, fl_fields]),
       c.(:and, [
         c.(:field_value, [fl_fields, :user, fl_user]),
         c.(:field_value, [fl_fields, :ip, fl_ip])
       ])
     ])}
  )
```

Now the two heuristics, each a [`setof/3`](REFERENCE.md#bagof3-and-setof3)
grouped by exactly one of `failed_login/3`'s three fields, with the
other free variable folded away via `^`
([EXAMPLES.md](REFERENCE.md#bagof3-and-setof3) explains the `Var^Goal`
existential-quantification syntax in full). `brute_force_suspect/1`
groups by `User`, folding `Ip` away, and checks the group is big
enough:

```elixir
bf_user = Term.new_var("User")
bf_ip = Term.new_var()
bf_ts = Term.new_var()
bf_timestamps = Term.new_var("Timestamps")
bf_n = Term.new_var("N")

db =
  Database.add_clause(
    db,
    {c.(:brute_force_suspect, [bf_user]),
     c.(:and, [
       c.(:setof, [bf_ts, c.(:^, [bf_ip, c.(:failed_login, [bf_user, bf_ip, bf_ts])]), bf_timestamps]),
       c.(:and, [c.(:length, [bf_timestamps, bf_n]), c.(:greater_or_equal, [bf_n, 3])])
     ])}
  )
```

`shared_ip_suspect/1` is the mirror image — group by `Ip`, fold `Ts`
away, check more than one distinct user shows up:

```elixir
si_ip = Term.new_var("Ip")
si_user = Term.new_var("User")
si_ts = Term.new_var()
si_users = Term.new_var("Users")
si_n = Term.new_var("N")

db =
  Database.add_clause(
    db,
    {c.(:shared_ip_suspect, [si_ip]),
     c.(:and, [
       c.(:setof, [si_user, c.(:^, [si_ts, c.(:failed_login, [si_user, si_ip, si_ts])]), si_users]),
       c.(:and, [c.(:length, [si_users, si_n]), c.(:>, [si_n, 1])])
     ])}
  )
```

(`greater_or_equal/2` and `>/2` — see
[Arithmetic comparisons](REFERENCE.md#arithmetic-comparisons-numeric_equal2-numeric_not_equal2-2-2-less_or_equal2-greater_or_equal2)
— `setof/3` already deduplicates `si_users`/`bf_timestamps`, so
`length/2` here is counting *distinct* values, not raw match counts.)

### Ingesting a batch of log lines

This is the dynamic-database half: parse each raw line and `assertz`
the resulting fact, the same `assertz/1` from
[EXAMPLES.md §4](EXAMPLES.md#4-a-key-value-store-assertretract), one
line at a time — exactly the shape a real log stream arrives in.

```elixir
lines = [
  "ts=2026-08-05T10:15:32Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5",
  "ts=2026-08-05T10:15:40Z level=info component=auth event=login_success user=bob ip=198.51.100.7",
  "ts=2026-08-05T10:16:02Z level=warn component=auth event=login_failed user=alice ip=203.0.113.5",
  "ts=2026-08-05T10:16:10Z level=error component=payments event=charge_failed user=carol amount=49.99",
  "ts=2026-08-05T10:16:45Z level=warn component=auth event=login_failed user=alice ip=203.0.113.9",
  "ts=2026-08-05T10:16:51Z level=warn component=auth event=login_failed user=dave ip=203.0.113.9",
  "ts=2026-08-05T10:17:03Z level=info component=auth event=login_success user=alice ip=203.0.113.9"
]

Enum.each(lines, fn line ->
  goal =
    c.(:phrase, [
      c.(:log_line, [
        Term.new_var("Ts"),
        Term.new_var("Level"),
        Term.new_var("Component"),
        Term.new_var("Event"),
        Term.new_var("Fields")
      ]),
      String.split(line)
    ])

  {:ok, [solution]} = Episteme.query(goal, db)

  entry =
    c.(:log_entry, [
      solution["Ts"],
      solution["Level"],
      solution["Component"],
      solution["Event"],
      solution["Fields"]
    ])

  {:ok, [%{}]} = Episteme.query(c.(:assertz, [entry]), db)
end)
```

Note `carol`'s line: a `payments`/`charge_failed` event with an
`amount` field instead of `ip` at all. `log_entry/5`'s trailing
`Fields` list is exactly why that's not a problem — the grammar never
hard-codes which fields follow the first four, so entries with
completely different shapes live in the same database without any
schema migration.

### Running the audit

```elixir
report_user = Term.new_var()
report_ip = Term.new_var()
report_suspects = Term.new_var("Suspects")
report_ips = Term.new_var("SharedIps")

report_goal =
  c.(:and, [
    c.(:findall, [report_user, c.(:brute_force_suspect, [report_user]), report_suspects]),
    c.(:and, [
      c.(:findall, [report_ip, c.(:shared_ip_suspect, [report_ip]), report_ips]),
      c.(:and, [
        c.(:format, ["Brute-force suspects: ~w~n", [report_suspects]]),
        c.(:format, ["Shared-IP suspects: ~w~n", [report_ips]])
      ])
    ])
  ])

Episteme.query(report_goal, db)
```

## Result

Actually running the above (`mix run` against a checkout of this
version of Episteme) prints:

```text
Brute-force suspects: ["alice"]
Shared-IP suspects: ["203.0.113.9"]
```

and answers `{:ok, [%{"Suspects" => ["alice"], "SharedIps" => ["203.0.113.9"]}]}`.

Both are correct, and for different reasons — which is the point of
running two independent heuristics instead of one:

- **`alice`** is a brute-force suspect: three failed logins in the
  data, full stop. It doesn't matter that two of them came from one
  IP (`203.0.113.5`) and the third from another (`203.0.113.9`) —
  `brute_force_suspect/1` explicitly folds `Ip` away with `^` before
  counting, because "did this account get hammered" shouldn't depend
  on the attacker rotating source addresses.
- **`203.0.113.9`** is a shared-IP suspect: it shows up behind failed
  logins for two different users (`alice` and `dave`), which is
  exactly the "one attacker, many stolen credentials" shape —
  independent of the fact that `dave` alone only has one failed
  login and would never trip the brute-force check by himself.
- **`bob`** never appears in either report — his only log line is a
  `login_success`, which `failed_login/3` doesn't match at all.
- **`carol`** doesn't appear either, for a different reason: her line
  is a real, successfully-parsed `log_entry/5` fact (the DCG doesn't
  care that it's a payment event, not a login), it's just that
  `failed_login/3` only ever looks at `warn`/`auth`/`login_failed`
  entries, so a `charge_failed` payment event was never in scope for
  either audit to begin with.

That last distinction — *parsed but not relevant* vs. *never
matched the grammar at all* — is worth sitting with: nothing here
had to special-case `carol`'s line, reject it, or fail. It's a
perfectly ordinary fact in the database; it simply never satisfies a
goal that specifically asks about failed logins. A schema-first
approach (a fixed struct per log line, one JSON schema, etc.) would
have had to decide up front whether payment events belong in the same
table as auth events; here that question just never comes up.

## What this exercises

Every one of these is a full [REFERENCE.md](REFERENCE.md) entry if you
want the complete semantics:

- [DCG grammars](REFERENCE.md#dcg-definite-clause-grammars) —
  terminals, embedded goals (`{Goal}`), nonterminal recursion,
  `phrase/2`
- [The dynamic database](REFERENCE.md#dynamic-database) — `assertz/1`
  building up a fact base one line at a time
- [`setof/3`](REFERENCE.md#bagof3-and-setof3) — grouping by a free
  variable, existentially quantifying another away with `^`
- [`split_string/4`](REFERENCE.md#split_string4) and
  [`atom_string/2`](REFERENCE.md#atom_string2-and-string_to_atom2) —
  the string/atom conversion family, used inside the grammar itself
- [`member/2`](CHEATSHEET.md#lists), `length/2`,
  [`greater_or_equal/2`/`>/2`](REFERENCE.md#arithmetic-comparisons-numeric_equal2-numeric_not_equal2-2-2-less_or_equal2-greater_or_equal2),
  and [`findall/3`](REFERENCE.md#findall3) — the same everyday
  predicates from [EXAMPLES.md](EXAMPLES.md), doing real work here
  instead of toy work
- [`format/2`](REFERENCE.md#format1-and-format2) — turning the
  query's answer into the actual report text above
