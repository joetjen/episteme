defmodule Episteme.Engine do
  @moduledoc """
  SLD-resolution over `Ichor.Backtrack.Tree` + `Ichor.Backtrack.Bindings`
  plus `Episteme.Database` -- clause selection is `disjunction/2` folded
  over a predicate's clauses in declared order, subgoal sequencing is
  `conjunction/2`, both reused unmodified from Ichor. Control constructs
  (`and`, `or`, `if_then`/`if_then_else`, `cut`, `not/1`, `call/N`,
  `once/1`) live directly here rather than in a separate builtins
  module: they turned out, once actually implemented, to be inseparable
  from the cut-barrier machinery below, not independent predicates
  dispatchable through a generic table. Every one of these is a plain
  English name, not the traditional Prolog operator (`,`/`;`/`->`/`!`/
  `\\+`) it corresponds to -- Episteme has no reader of its own (see
  `Episteme`'s moduledoc), so there's no textual syntax for any of this
  to look "conventional" against; a word you can actually remember beat
  matching ISO Prolog's punctuation.

  ## Cut

  `Ichor.Backtrack.Tree`'s `once/1` is not cut -- cut commits to every
  choice made since entering the *current clause* specifically,
  including pruning alternatives for goals that already SUCCEEDED
  earlier in the same body, which a bindings-borne "cut fired" marker
  can't express. The textbook illustration, in real Prolog's own
  textual syntax: `p :- !, fail.` with a second clause `p :- true.`
  must fail `p` outright (cut commits to clause 1 before `fail` ever
  runs), but a clause body that never produces a solution never gives a
  marker-on-solutions scheme anything to inspect.

  So `cut` succeeds once normally, but its "give me another solution"
  continuation `throw({:episteme_cut, barrier})`s instead of returning
  `:empty`. Every predicate call (and `call/N`, `once/1`, `not/1` --
  each cut-opaque per ISO) mints a fresh `barrier = make_ref()` and
  wraps its own clause-disjunction's lazy solution stream in
  `guard_cut/2`, which re-wraps every successive `rest` thunk so the
  guard is active no matter how many times -- or how much later -- a
  caller pulls another solution, catching only throws tagged with its
  *own* barrier (`catch {:episteme_cut, ^barrier} -> :empty`) and
  re-throwing (letting Elixir's own catch semantics do it for free) any
  other tag, so a cut inside a called predicate never escapes past its
  own frame to affect the caller.

  Because `Ichor.Backtrack.Tree`'s combinators are plain function calls
  with no `try` anywhere inside them, a throw passes through
  `conjunction`/`disjunction`/`once` completely untouched -- this needs
  zero changes to Ichor itself.
  """

  alias Episteme.Builtins.{Arithmetic, Exceptions, Io, Lists}
  alias Episteme.{Database, Term}
  alias Episteme.Term.{Compound, Var}
  alias Ichor.Backtrack.{Bindings, Tree}

  @type barrier :: reference()

  @doc """
  Solves `goal_term` against `db` from empty bindings -- the top-level
  query entry point. Genuinely lazy even in the very first dispatch
  step: a goal function call is itself eager (only the *rest* of a
  search tree is deferred by `Ichor.Backtrack.Tree`'s own combinators),
  so a builtin that throws immediately on its first attempt (calling an
  undefined predicate, say) would otherwise escape before a caller
  pulling solutions one at a time (`Episteme.next_solution/2`) ever gets
  a chance to guard it -- wrapping everything in one more thunk here
  defers that first dispatch until whoever holds this value actually
  calls `Ichor.Backtrack.Tree`'s `next/1` on it.
  """
  @spec solve_query(term(), Database.t()) :: Ichor.Backtrack.Tree.t()
  def solve_query(goal_term, db) do
    barrier = make_ref()
    fn -> guard_cut(goal(goal_term, db, barrier).(Bindings.new()), barrier).() end
  end

  @doc "A goal (`bindings -> solutions`) for `term`, resolved under whatever `barrier` is currently in scope."
  @spec goal(term(), Database.t(), barrier()) :: Ichor.Backtrack.goal()
  def goal(term, db, barrier) do
    fn bindings -> solve(term, bindings, db, barrier) end
  end

  # ---- cut mechanism --------------------------------------------------------

  defp cut_goal(barrier) do
    fn bindings ->
      fn -> {:solution, bindings, fn -> throw({:episteme_cut, barrier}) end} end
    end
  end

  @doc false
  @spec guard_cut(Tree.t(), barrier()) :: Tree.t()
  def guard_cut(thunk, barrier) do
    fn ->
      case safe_next(thunk, barrier) do
        :empty -> :empty
        {:solution, value, rest} -> {:solution, value, guard_cut(rest, barrier)}
      end
    end
  end

  defp safe_next(thunk, barrier) do
    thunk.()
  catch
    {:episteme_cut, ^barrier} -> :empty
  end

  # ---- dispatch --------------------------------------------------------------

  defp solve(term, bindings, db, barrier) do
    case Bindings.resolve(Term, bindings, term) do
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
      resolved -> dispatch(resolved, bindings, db, barrier)
    end
  end

  # -- control --

  defp dispatch(true, bindings, _db, _barrier), do: Tree.unit().(bindings)
  defp dispatch(:fail, bindings, _db, _barrier), do: Tree.fail().(bindings)
  defp dispatch(false, bindings, _db, _barrier), do: Tree.fail().(bindings)
  defp dispatch(:cut, bindings, _db, barrier), do: cut_goal(barrier).(bindings)

  defp dispatch(%Compound{name: :and, args: [a, b]}, bindings, db, barrier) do
    Tree.conjunction(goal(a, db, barrier), goal(b, db, barrier)).(bindings)
  end

  defp dispatch(%Compound{name: :or, args: [a, b]}, bindings, db, barrier) do
    Tree.disjunction(goal(a, db, barrier), goal(b, db, barrier)).(bindings)
  end

  defp dispatch(
         %Compound{name: :if_then_else, args: [cond_, then_, else_]},
         bindings,
         db,
         barrier
       ) do
    if_then_else(cond_, then_, else_, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :if_then, args: [cond_, then_]}, bindings, db, barrier) do
    if_then_else(cond_, then_, :fail, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :not, args: [g]}, bindings, db, _barrier) do
    negation_as_failure(g, bindings, db)
  end

  defp dispatch(%Compound{name: :once, args: [g]}, bindings, db, _barrier) do
    inner_barrier = make_ref()
    Tree.once(fn b -> guard_cut(goal(g, db, inner_barrier).(b), inner_barrier) end).(bindings)
  end

  defp dispatch(%Compound{name: :call, args: [g | extra]}, bindings, db, _barrier) do
    inner_barrier = make_ref()
    built = build_call(g, extra, bindings)
    guard_cut(goal(built, db, inner_barrier).(bindings), inner_barrier)
  end

  # -- solution aggregation --

  defp dispatch(%Compound{name: :findall, args: [template, g, result]}, bindings, db, _barrier) do
    findall_goal(template, g, result, bindings, db)
  end

  defp dispatch(%Compound{name: :forall, args: [cond_, action]}, bindings, db, _barrier) do
    forall_goal(cond_, action, bindings, db)
  end

  # -- higher-order list predicates --

  defp dispatch(%Compound{name: :include, args: [g, list, result]}, bindings, db, _barrier) do
    filter_goal(g, list, result, db, bindings, true)
  end

  defp dispatch(%Compound{name: :exclude, args: [g, list, result]}, bindings, db, _barrier) do
    filter_goal(g, list, result, db, bindings, false)
  end

  defp dispatch(%Compound{name: :foldl, args: [g | rest]}, bindings, db, _barrier)
       when length(rest) >= 3 do
    {lists, [v0, v]} = Enum.split(rest, length(rest) - 2)
    foldl_goal(g, lists, v0, v, db, bindings)
  end

  defp dispatch(%Compound{name: :maplist, args: [g | lists]}, bindings, db, _barrier)
       when lists != [] do
    maplist_goal(g, lists, db, bindings)
  end

  # -- unification / comparison --

  defp dispatch(%Compound{name: :unify, args: [a, b]}, bindings, _db, _barrier) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp dispatch(%Compound{name: :not_unify, args: [a, b]}, bindings, _db, _barrier) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, _} -> Tree.fail().(bindings)
      :fail -> Tree.unit().(bindings)
    end
  end

  defp dispatch(%Compound{name: :equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(structurally_equal?(a, b, bindings), bindings)

  defp dispatch(%Compound{name: :not_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(not structurally_equal?(a, b, bindings), bindings)

  # -- standard order of terms (real Prolog: @<, @>, @=<, @>=, compare/3) --

  defp dispatch(%Compound{name: :order_less, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(order_compare(a, b, bindings) == :lt, bindings)

  defp dispatch(%Compound{name: :order_greater, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(order_compare(a, b, bindings) == :gt, bindings)

  defp dispatch(%Compound{name: :order_less_or_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(order_compare(a, b, bindings) in [:lt, :eq], bindings)

  defp dispatch(%Compound{name: :order_greater_or_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(order_compare(a, b, bindings) in [:gt, :eq], bindings)

  defp dispatch(%Compound{name: :compare, args: [order, a, b]}, bindings, _db, _barrier) do
    unify_or_fail(bindings, order, order_atom(order_compare(a, b, bindings)))
  end

  # -- type checks --

  defp dispatch(%Compound{name: :var, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(match?(%Var{}, Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :nonvar, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(not match?(%Var{}, Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :atom, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_atom(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :atomic, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Var{} -> bool_goal(false, bindings)
      %Compound{} -> bool_goal(false, bindings)
      [_ | _] -> bool_goal(false, bindings)
      _ -> bool_goal(true, bindings)
    end
  end

  defp dispatch(%Compound{name: :number, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_number(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :integer, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_integer(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :float, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(is_float(Bindings.resolve(Term, bindings, x)), bindings)

  defp dispatch(%Compound{name: :compound, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Compound{} -> bool_goal(true, bindings)
      [_ | _] -> bool_goal(true, bindings)
      _ -> bool_goal(false, bindings)
    end
  end

  defp dispatch(%Compound{name: :callable, args: [x]}, bindings, _db, _barrier) do
    case Bindings.resolve(Term, bindings, x) do
      %Var{} -> bool_goal(false, bindings)
      %Compound{} -> bool_goal(true, bindings)
      [_ | _] -> bool_goal(true, bindings)
      atom when is_atom(atom) -> bool_goal(true, bindings)
      _ -> bool_goal(false, bindings)
    end
  end

  defp dispatch(%Compound{name: :is_list, args: [x]}, bindings, _db, _barrier),
    do: bool_goal(proper_list?(x, bindings), bindings)

  # -- arithmetic --

  defp dispatch(%Compound{name: :is, args: [result, expr]}, bindings, _db, _barrier) do
    value = Arithmetic.eval(expr, bindings)

    case Bindings.unify(Term, bindings, result, value) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp dispatch(%Compound{name: :numeric_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &==/2), bindings)

  defp dispatch(%Compound{name: :numeric_not_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &!=/2), bindings)

  defp dispatch(%Compound{name: :<, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &</2), bindings)

  defp dispatch(%Compound{name: :>, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &>/2), bindings)

  defp dispatch(%Compound{name: :less_or_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &<=/2), bindings)

  defp dispatch(%Compound{name: :greater_or_equal, args: [a, b]}, bindings, _db, _barrier),
    do: bool_goal(Arithmetic.compare(a, b, bindings, &>=/2), bindings)

  # -- exceptions --

  defp dispatch(%Compound{name: :throw, args: [t]}, bindings, _db, _barrier) do
    prolog_throw(Term.resolve_deep(t, bindings))
  end

  defp dispatch(%Compound{name: :catch, args: [g, catcher, recovery]}, bindings, db, barrier) do
    catch_goal(g, catcher, recovery, bindings, db, barrier)
  end

  defp dispatch(%Compound{name: :type_error, args: [type, culprit]}, bindings, _db, _barrier) do
    prolog_throw(
      Exceptions.type_error(
        Bindings.resolve(Term, bindings, type),
        Term.resolve_deep(culprit, bindings)
      )
    )
  end

  defp dispatch(%Compound{name: :domain_error, args: [domain, culprit]}, bindings, _db, _barrier) do
    prolog_throw(
      Exceptions.domain_error(
        Bindings.resolve(Term, bindings, domain),
        Term.resolve_deep(culprit, bindings)
      )
    )
  end

  defp dispatch(%Compound{name: :instantiation_error, args: [_]}, _bindings, _db, _barrier) do
    prolog_throw(Exceptions.instantiation_error())
  end

  # -- term inspection --

  defp dispatch(%Compound{name: :copy_term, args: [t, copy]}, bindings, _db, _barrier) do
    fresh = t |> Term.resolve_deep(bindings) |> Term.fresh_copy()
    unify_or_fail(bindings, copy, fresh)
  end

  defp dispatch(%Compound{name: :ground, args: [x]}, bindings, _db, _barrier) do
    bool_goal(x |> Term.resolve_deep(bindings) |> Term.ground?(), bindings)
  end

  defp dispatch(%Compound{name: :functor, args: [t, name, arity]}, bindings, _db, _barrier) do
    functor_goal(t, name, arity, bindings)
  end

  defp dispatch(%Compound{name: :arg, args: [n, t, a]}, bindings, _db, _barrier) do
    arg_goal(n, t, a, bindings)
  end

  defp dispatch(%Compound{name: :univ, args: [t, l]}, bindings, _db, _barrier) do
    univ_goal(t, l, bindings)
  end

  # -- dynamic database (assert/retract) --

  defp dispatch(%Compound{name: n, args: [clause_term]}, bindings, db, _barrier)
       when n in [:assert, :assertz] do
    do_assert(clause_term, bindings, db, :end)
  end

  defp dispatch(%Compound{name: :asserta, args: [clause_term]}, bindings, db, _barrier) do
    do_assert(clause_term, bindings, db, :front)
  end

  defp dispatch(%Compound{name: :retract, args: [clause_term]}, bindings, db, _barrier) do
    retract_goal(clause_term, bindings, db)
  end

  defp dispatch(%Compound{name: :retractall, args: [head_pattern]}, bindings, db, _barrier) do
    retractall_goal(head_pattern, bindings, db)
  end

  defp dispatch(%Compound{name: :abolish, args: [indicator]}, bindings, db, _barrier) do
    abolish_goal(indicator, bindings, db)
  end

  defp dispatch(%Compound{name: :dynamic, args: [spec]}, bindings, db, _barrier) do
    dynamic_goal(spec, bindings, db)
  end

  defp dispatch(%Compound{name: :clause, args: [head, body]}, bindings, db, _barrier) do
    builtin_clause_goal(head, body, db, bindings)
  end

  # -- arithmetic / lists / io, then user-defined predicates --

  defp dispatch(%Compound{name: name, args: args}, bindings, db, _barrier) do
    with :not_handled <- Arithmetic.dispatch(name, length(args), args),
         :not_handled <- Lists.dispatch(name, length(args), args),
         :not_handled <- Io.dispatch(name, length(args), args) do
      solve_user_predicate(name, args, bindings, db)
    else
      goal_fun when is_function(goal_fun, 1) -> goal_fun.(bindings)
    end
  end

  defp dispatch(atom, bindings, db, _barrier) when is_atom(atom) do
    case Io.dispatch(atom, 0, []) do
      :not_handled -> solve_user_predicate(atom, [], bindings, db)
      goal_fun -> goal_fun.(bindings)
    end
  end

  # ---- helpers ---------------------------------------------------------------

  defp bool_goal(true, bindings), do: Tree.unit().(bindings)
  defp bool_goal(false, bindings), do: Tree.fail().(bindings)

  defp unify_or_fail(bindings, a, b) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  # `functor(T, Name, Arity)`: with `T` bound, decomposes it (an atomic
  # term has itself as Name and arity 0, matching ISO -- a non-empty
  # list decomposes via Term.compound?/1's own './2' encoding, same as
  # everywhere else in this module). With `T` unbound, builds a fresh
  # term from Name/Arity instead: arity 0 just unifies T with Name
  # as-is (whatever atomic value it is), arity > 0 requires an atom
  # Name and builds a compound of that many fresh variables.
  defp functor_goal(t, name_arg, arity_arg, bindings) do
    case Bindings.resolve(Term, bindings, t) do
      %Var{} ->
        name = resolve_instantiated(name_arg, bindings)
        arity = resolve_instantiated(arity_arg, bindings)
        unify_or_fail(bindings, t, build_from_functor(name, arity))

      resolved ->
        {name, arity} = functor_of(resolved)

        with {:ok, b1} <- Bindings.unify(Term, bindings, name_arg, name),
             {:ok, b2} <- Bindings.unify(Term, b1, arity_arg, arity) do
          Tree.unit().(b2)
        else
          :fail -> Tree.fail().(bindings)
        end
    end
  end

  defp functor_of(resolved) do
    if Term.compound?(resolved) do
      {name, args} = Term.deconstruct(resolved)
      {name, length(args)}
    else
      {resolved, 0}
    end
  end

  defp resolve_instantiated(term, bindings) do
    case Bindings.resolve(Term, bindings, term) do
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
      resolved -> resolved
    end
  end

  defp build_from_functor(name, 0), do: name

  defp build_from_functor(name, arity) when is_atom(name) and is_integer(arity) and arity > 0,
    do: Term.reconstruct(name, for(_ <- 1..arity, do: Term.new_var()))

  defp build_from_functor(name, arity) when is_integer(arity) and arity > 0,
    do: prolog_throw(Exceptions.type_error(:atom, name))

  defp build_from_functor(_name, arity),
    do: prolog_throw(Exceptions.domain_error(:not_less_than_zero, arity))

  # `arg(N, Term, Arg)`: 1-based, like nth1/3. Out-of-range N (< 1 or >
  # arity) just fails, matching this project's existing nth0/nth1
  # style, rather than chasing ISO's own domain_error(not_less_than_zero, N)
  # distinction for negative N specifically.
  defp arg_goal(n_arg, t_arg, a_arg, bindings) do
    n = resolve_instantiated(n_arg, bindings)
    t = resolve_instantiated(t_arg, bindings)

    cond do
      not is_integer(n) -> prolog_throw(Exceptions.type_error(:integer, n))
      not Term.compound?(t) -> prolog_throw(Exceptions.type_error(:compound, t))
      true -> select_arg(n, t, a_arg, bindings)
    end
  end

  # Explicit `n < 1`/`n > length(args)` bounds check rather than
  # trusting `Enum.at/2`'s `nil` sentinel for "out of range": a
  # negative index counts from the *end* of the list in `Enum.at/2`
  # (so `arg(0, foo(a,b), X)` would otherwise wrongly succeed with
  # `X = b`, via `Enum.at(args, -1)`), and a stored argument can itself
  # legitimately be the atom `nil`, which is indistinguishable from
  # "not found" if `Enum.at/2`'s own return value is what gets matched.
  defp select_arg(n, t, a_arg, bindings) do
    {_name, args} = Term.deconstruct(t)

    if n >= 1 and n <= length(args) do
      unify_or_fail(bindings, a_arg, Enum.at(args, n - 1))
    else
      Tree.fail().(bindings)
    end
  end

  # `univ(Term, List)` (`=..`/2 in ISO's own punctuation): with `Term`
  # bound, decomposes it the same way functor/3 does (Name alone for an
  # atomic term, [Name | Args] for a compound). With `Term` unbound,
  # builds it back from a fully-instantiated [Name | Args] list --
  # Term.reconstruct/2 already special-cases Name = :. with two args
  # into a native list, so that shape round-trips through here for
  # free, same as functor/3.
  defp univ_goal(t_arg, l_arg, bindings) do
    case Bindings.resolve(Term, bindings, t_arg) do
      %Var{} -> univ_construct(l_arg, t_arg, bindings)
      resolved -> univ_decompose(resolved, l_arg, bindings)
    end
  end

  defp univ_decompose(resolved, l_arg, bindings) do
    list =
      if Term.compound?(resolved) do
        {name, args} = Term.deconstruct(resolved)
        [name | args]
      else
        [resolved]
      end

    unify_or_fail(bindings, l_arg, list)
  end

  defp univ_construct(l_arg, t_arg, bindings) do
    case Term.resolve_deep(l_arg, bindings) do
      %Var{} ->
        prolog_throw(Exceptions.instantiation_error())

      [name] ->
        unify_or_fail(bindings, t_arg, name)

      [name | args] when is_atom(name) ->
        unify_or_fail(bindings, t_arg, Term.reconstruct(name, args))

      [name | _args] ->
        prolog_throw(Exceptions.type_error(:atom, name))

      [] ->
        prolog_throw(Exceptions.domain_error(:non_empty_list, []))

      other ->
        prolog_throw(Exceptions.type_error(:list, other))
    end
  end

  defp structurally_equal?(a, b, bindings) do
    Term.structurally_equal?(Term.resolve_deep(a, bindings), Term.resolve_deep(b, bindings))
  end

  defp order_compare(a, b, bindings) do
    Term.compare_order(Term.resolve_deep(a, bindings), Term.resolve_deep(b, bindings))
  end

  defp order_atom(:lt), do: :<
  defp order_atom(:eq), do: :=
  defp order_atom(:gt), do: :>

  defp proper_list?(x, bindings) do
    case Bindings.resolve(Term, bindings, x) do
      [] -> true
      [_ | t] -> proper_list?(t, bindings)
      _ -> false
    end
  end

  defp if_then_else(cond_, then_, else_, bindings, db, barrier) do
    cond_barrier = make_ref()
    cond_stream = guard_cut(goal(cond_, db, cond_barrier).(bindings), cond_barrier)

    case Tree.next(cond_stream) do
      {:solution, cond_bindings, _rest} -> goal(then_, db, barrier).(cond_bindings)
      :empty -> goal(else_, db, barrier).(bindings)
    end
  end

  defp negation_as_failure(g, bindings, db) do
    inner_barrier = make_ref()
    stream = guard_cut(goal(g, db, inner_barrier).(bindings), inner_barrier)

    case Tree.next(stream) do
      {:solution, _bindings, _rest} -> Tree.fail().(bindings)
      :empty -> Tree.unit().(bindings)
    end
  end

  # `findall/3` is cut-opaque and always succeeds -- `[]` is a perfectly
  # good answer when `g` has no solutions, unlike `bagof/3`/`setof/3`
  # (not implemented here) which fail in that case instead.
  defp findall_goal(template, g, result, bindings, db) do
    inner_barrier = make_ref()
    stream = guard_cut(goal(g, db, inner_barrier).(bindings), inner_barrier)
    collected = collect_solutions(stream, template)

    case Bindings.unify(Term, bindings, result, collected) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp collect_solutions(stream, template) do
    case Tree.next(stream) do
      :empty ->
        []

      {:solution, sol_bindings, rest} ->
        [Term.resolve_deep(template, sol_bindings) | collect_solutions(rest, template)]
    end
  end

  # `forall(Cond, Action)` <-> `\+ (Cond, \+ Action)`, but walked directly
  # rather than built out of two nested negations: succeeds iff every
  # solution of `Cond` (cut-opaque) has at least one solution of `Action`
  # (also cut-opaque) under it. Never binds anything in `bindings`,
  # exactly like `\+/1`.
  defp forall_goal(cond_, action, bindings, db) do
    cond_barrier = make_ref()
    cond_stream = guard_cut(goal(cond_, db, cond_barrier).(bindings), cond_barrier)
    bool_goal(every_solution_succeeds?(cond_stream, action, db), bindings)
  end

  defp every_solution_succeeds?(cond_stream, action, db) do
    case Tree.next(cond_stream) do
      :empty ->
        true

      {:solution, cond_bindings, rest} ->
        action_barrier = make_ref()

        action_stream =
          guard_cut(goal(action, db, action_barrier).(cond_bindings), action_barrier)

        case Tree.next(action_stream) do
          {:solution, _bindings, _rest} -> every_solution_succeeds?(rest, action, db)
          :empty -> false
        end
    end
  end

  defp build_call(g, [], _bindings), do: g

  defp build_call(g, extra, bindings) do
    case Bindings.resolve(Term, bindings, g) do
      %Compound{name: name, args: args} -> %Compound{name: name, args: args ++ extra}
      atom when is_atom(atom) -> %Compound{name: atom, args: extra}
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
    end
  end

  # `include/3`/`exclude/3`: `Goal` is called once per element, cut-opaque
  # (own fresh barrier per call, same as `call/N`), as a plain
  # existence check via `Tree.next/1` -- exactly `negation_as_failure/3`'s
  # own pattern. Neither predicate propagates bindings `Goal` makes back
  # into the kept elements themselves; they only test membership.
  defp filter_goal(g, list, result, db, bindings, keep_on_success) do
    case list_elements(list, bindings) do
      {:ok, elements} ->
        kept =
          Enum.filter(elements, fn el ->
            goal_succeeds?(g, [el], db, bindings) == keep_on_success
          end)

        unify_or_fail(bindings, result, kept)

      :error ->
        Tree.fail().(bindings)
    end
  end

  defp goal_succeeds?(g, extra_args, db, bindings) do
    built = build_call(g, extra_args, bindings)
    inner_barrier = make_ref()
    stream = guard_cut(goal(built, db, inner_barrier).(bindings), inner_barrier)

    case Tree.next(stream) do
      {:solution, _bindings, _rest} -> true
      :empty -> false
    end
  end

  # A proper list's elements, as-is (not resolved) -- callers pass these
  # straight into a built `call/N` goal, so an element that's still an
  # unbound variable stays one, exactly like any other goal argument.
  defp list_elements(list, bindings) do
    case Bindings.resolve(Term, bindings, list) do
      [] ->
        {:ok, []}

      [h | t] ->
        case list_elements(t, bindings) do
          {:ok, rest} -> {:ok, [h | rest]}
          :error -> :error
        end

      _not_a_proper_list ->
        :error
    end
  end

  defp and_goal(a, b), do: %Compound{name: :and, args: [a, b]}

  # `foldl(Goal, List1, ..., ListN, V0, V)`: every list argument must
  # already be a proper, bound list (unlike `maplist/N` below, this one
  # has no "generate an unbound list" mode) -- builds one right-nested
  # `and/2` chain of `call(Goal, Elem1_i, ..., ElemN_i, AccIn_i,
  # AccOut_i)` per row, threading each row's `AccOut` into the next
  # row's `AccIn`, then dispatches the whole tree through the ordinary
  # `goal/3` machinery (real backtracking through every row's own
  # alternative solutions, for free, the same way `,`/2 always has).
  defp foldl_goal(g, lists, v0, v, db, bindings) do
    resolved = Enum.map(lists, &list_elements(&1, bindings))

    if Enum.all?(resolved, &match?({:ok, _}, &1)) do
      element_lists = Enum.map(resolved, fn {:ok, els} -> els end)
      run_foldl(g, element_lists, v0, v, db, bindings)
    else
      Tree.fail().(bindings)
    end
  end

  defp run_foldl(g, element_lists, v0, v, db, bindings) do
    case Enum.uniq(Enum.map(element_lists, &length/1)) do
      [_same_length] ->
        rows = transpose(element_lists)
        {body, final_acc} = build_foldl_conjunction(g, rows, v0)
        full_goal = and_goal(body, %Compound{name: :unify, args: [v, final_acc]})
        inner_barrier = make_ref()
        guard_cut(goal(full_goal, db, inner_barrier).(bindings), inner_barrier)

      [] ->
        unify_or_fail(bindings, v, v0)

      _mismatched_lengths ->
        Tree.fail().(bindings)
    end
  end

  defp build_foldl_conjunction(_g, [], v0), do: {true, v0}

  defp build_foldl_conjunction(g, [row | rows], v0) do
    acc_out = Term.new_var("_")
    step = %Compound{name: :call, args: [g | row ++ [v0, acc_out]]}
    {rest, final_acc} = build_foldl_conjunction(g, rows, acc_out)
    {and_goal(step, rest), final_acc}
  end

  # `maplist(Goal, List1, ..., ListN)`: at least one list must already
  # be a proper, bound list, fixing the row count -- any other list
  # argument that isn't yet bound gets unified with a fresh list of
  # that many brand-new variables first (same "generate a list of fresh
  # variables from a known length" shape `length/2` already has, in
  # Episteme.Builtins.Lists), then the same "one and/2 chain of call/N
  # per row" tree `foldl_goal/6` builds, minus the accumulator.
  defp maplist_goal(g, lists, db, bindings) do
    resolved = Enum.map(lists, &list_elements(&1, bindings))

    case known_length(resolved) do
      {:ok, n} ->
        {element_lists, prereqs} = materialize_lists(lists, resolved, n)
        rows = transpose(element_lists)
        body = Enum.reduce(prereqs, build_call_conjunction(g, rows), &and_goal/2)
        inner_barrier = make_ref()
        guard_cut(goal(body, db, inner_barrier).(bindings), inner_barrier)

      :error ->
        Tree.fail().(bindings)
    end
  end

  defp known_length(resolved) do
    lengths =
      resolved
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, els} -> length(els) end)

    case Enum.uniq(lengths) do
      [n] -> {:ok, n}
      _no_or_conflicting_lengths -> :error
    end
  end

  defp materialize_lists(lists, resolved, n) do
    Enum.zip(lists, resolved)
    |> Enum.map(fn
      {_list_term, {:ok, els}} ->
        {els, nil}

      {list_term, :error} ->
        fresh = for(_ <- 1..n, do: Term.new_var("_"))
        {fresh, %Compound{name: :unify, args: [list_term, fresh]}}
    end)
    |> Enum.unzip()
    |> then(fn {element_lists, prereqs} -> {element_lists, Enum.reject(prereqs, &is_nil/1)} end)
  end

  defp build_call_conjunction(_g, []), do: true
  defp build_call_conjunction(g, [row]), do: %Compound{name: :call, args: [g | row]}

  defp build_call_conjunction(g, [row | rows]) do
    and_goal(%Compound{name: :call, args: [g | row]}, build_call_conjunction(g, rows))
  end

  defp transpose(lists), do: lists |> Enum.zip() |> Enum.map(&Tuple.to_list/1)

  defp catch_goal(g, catcher, recovery, bindings, db, barrier) do
    inner_barrier = make_ref()

    try do
      guard_cut(goal(g, db, inner_barrier).(bindings), inner_barrier)
    catch
      {:episteme_throw, ball} ->
        case Bindings.unify(Term, bindings, catcher, ball) do
          {:ok, extended} -> goal(recovery, db, barrier).(extended)
          :fail -> prolog_throw(ball)
        end
    end
  end

  # `Database.defined?/3` (not "clause list is empty"), because
  # `retractall/1` can leave a predicate with zero clauses while still
  # having declared it dynamic -- calling it afterward must fail
  # silently, the same as it would after removing the last clause one
  # `retract/1` at a time, not raise `existence_error` as if it had
  # never been asserted at all.
  defp solve_user_predicate(name, args, bindings, db) do
    arity = length(args)

    if Database.defined?(db, name, arity) do
      call_term = if arity == 0, do: name, else: %Compound{name: name, args: args}
      try_clauses(Database.clauses_for(db, name, arity), call_term, bindings, db)
    else
      indicator = %Compound{name: :/, args: [name, arity]}
      prolog_throw(Exceptions.existence_error(:procedure, indicator))
    end
  end

  defp try_clauses(clauses, call_term, bindings, db) do
    barrier = make_ref()

    stream =
      Enum.reduce(clauses, Tree.fail(), fn clause, acc ->
        Tree.disjunction(acc, clause_goal(clause, call_term, db, barrier))
      end)

    guard_cut(stream.(bindings), barrier)
  end

  defp clause_goal({head, body}, call_term, db, barrier) do
    fn bindings ->
      %Compound{args: [fresh_head, fresh_body]} =
        Term.fresh_copy(%Compound{name: :"$clause", args: [head, body]})

      case Bindings.unify(Term, bindings, call_term, fresh_head) do
        {:ok, extended} -> goal(fresh_body, db, barrier).(extended)
        :fail -> Tree.fail().(bindings)
      end
    end
  end

  # ---- dynamic database (assert/retract) -------------------------------------

  # A clause is stored resolved against the caller's *current* bindings
  # and then renamed apart, exactly like a fact/rule read from source:
  # any variable still unbound at assert-time becomes that stored
  # clause's own private variable, sharing nothing with the goal that
  # asserted it.
  defp do_assert(clause_term, bindings, db, position) do
    clause_term
    |> Term.resolve_deep(bindings)
    |> Term.fresh_copy()
    |> store_clause(db, position)

    Tree.unit().(bindings)
  end

  defp store_clause(%Compound{name: :":-", args: [head, body]}, db, position),
    do: assert_clause(head, body, db, position)

  defp store_clause(%Var{}, _db, _position), do: prolog_throw(Exceptions.instantiation_error())
  defp store_clause(%Compound{} = head, db, position), do: assert_clause(head, true, db, position)

  defp store_clause(head, db, position) when is_atom(head),
    do: assert_clause(head, true, db, position)

  defp store_clause(other, _db, _position),
    do: prolog_throw(Exceptions.type_error(:callable, other))

  defp assert_clause(head, body, db, :end), do: Database.add_clause(db, {head, body})
  defp assert_clause(head, body, db, :front), do: Database.add_clause_first(db, {head, body})

  # `retract/1` takes either a bare `Head` (body defaults to `true`,
  # matching a fact) or a `Head :- Body` term, unifies against the first
  # stored clause (in declared/assert order) whose head *and* body both
  # unify, removes exactly that clause, and keeps the resulting bindings
  # (so variables in the retract argument end up bound to the removed
  # clause's own head/body, same as real Prolog). Fails, without
  # mutating anything, if no stored clause unifies; deterministic on
  # success -- unlike some implementations, backtracking into a
  # successful `retract/1` here does not try the next matching clause.
  defp retract_goal(clause_term, bindings, db) do
    case Bindings.resolve(Term, bindings, clause_term) do
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
      resolved -> do_retract(resolved, bindings, db)
    end
  end

  defp do_retract(%Compound{name: :":-", args: [head, body]}, bindings, db),
    do: find_and_remove(head, body, bindings, db)

  defp do_retract(head, bindings, db), do: find_and_remove(head, true, bindings, db)

  defp find_and_remove(pattern_head, pattern_body, bindings, db) do
    {name, arity} = Database.indicator(pattern_head)
    clauses = Database.clauses_for(db, name, arity)

    case find_matching_clause(clauses, pattern_head, pattern_body, bindings) do
      {:ok, index, extended} ->
        Database.replace_clauses(db, name, arity, List.delete_at(clauses, index))
        Tree.unit().(extended)

      :not_found ->
        Tree.fail().(bindings)
    end
  end

  defp find_matching_clause(clauses, pattern_head, pattern_body, bindings) do
    clauses
    |> Enum.with_index()
    |> Enum.find_value(:not_found, fn {{stored_head, stored_body}, index} ->
      %Compound{args: [fresh_head, fresh_body]} =
        Term.fresh_copy(%Compound{name: :"$clause", args: [stored_head, stored_body]})

      with {:ok, b1} <- Bindings.unify(Term, bindings, pattern_head, fresh_head),
           {:ok, b2} <- Bindings.unify(Term, b1, pattern_body, fresh_body) do
        {:ok, index, b2}
      else
        :fail -> nil
      end
    end)
  end

  # `retractall/1` removes every stored clause whose *head* unifies with
  # `head_pattern`, ignoring clause bodies entirely, always succeeds
  # (even against an undefined predicate, or one already empty), and --
  # unlike `retract/1` -- never binds anything: each unification is only
  # used to select clauses, then discarded.
  defp retractall_goal(head_pattern, bindings, db) do
    case Bindings.resolve(Term, bindings, head_pattern) do
      %Var{} -> prolog_throw(Exceptions.instantiation_error())
      resolved -> do_retractall(resolved, bindings, db)
    end
  end

  defp do_retractall(resolved_pattern, bindings, db) do
    {name, arity} = Database.indicator(resolved_pattern)
    clauses = Database.clauses_for(db, name, arity)

    kept =
      Enum.reject(clauses, fn {stored_head, _body} ->
        fresh_head = Term.fresh_copy(stored_head)
        match?({:ok, _extended}, Bindings.unify(Term, bindings, resolved_pattern, fresh_head))
      end)

    Database.replace_clauses(db, name, arity, kept)
    Tree.unit().(bindings)
  end

  # `abolish(Name/Arity)`: unlike `retractall/1`, leaves the predicate
  # genuinely undefined again -- a later plain call raises
  # `existence_error` rather than just failing.
  defp abolish_goal(indicator, bindings, db) do
    case predicate_indicator(indicator, bindings) do
      {:ok, name, arity} ->
        Database.abolish(db, name, arity)
        Tree.unit().(bindings)

      :error ->
        prolog_throw(Exceptions.type_error(:predicate_indicator, indicator))
    end
  end

  # `dynamic(Name/Arity)` or `dynamic([Name/Arity, ...])`: marks each
  # indicator defined without adding a clause, so a plain call fails
  # (no matching clauses) instead of raising `existence_error`, and
  # `assert`/`retract` can be used on it right away. A no-op for an
  # indicator that already has clauses -- see `Database.declare_dynamic/3`.
  defp dynamic_goal(spec, bindings, db) do
    case Bindings.resolve(Term, bindings, spec) do
      %Compound{name: :/} ->
        case predicate_indicator(spec, bindings) do
          {:ok, name, arity} ->
            Database.declare_dynamic(db, name, arity)
            Tree.unit().(bindings)

          :error ->
            prolog_throw(Exceptions.type_error(:predicate_indicator, spec))
        end

      list when is_list(list) ->
        declare_all_dynamic(list, bindings, db)
        Tree.unit().(bindings)

      _not_an_indicator_or_list ->
        prolog_throw(Exceptions.type_error(:predicate_indicator, spec))
    end
  end

  defp declare_all_dynamic([], _bindings, _db), do: :ok

  defp declare_all_dynamic([indicator | rest], bindings, db) do
    case predicate_indicator(indicator, bindings) do
      {:ok, name, arity} ->
        Database.declare_dynamic(db, name, arity)
        declare_all_dynamic(rest, bindings, db)

      :error ->
        prolog_throw(Exceptions.type_error(:predicate_indicator, indicator))
    end
  end

  defp predicate_indicator(term, bindings) do
    case Bindings.resolve(Term, bindings, term) do
      %Compound{name: :/, args: [name, arity]}
      when is_atom(name) and is_integer(arity) and arity >= 0 ->
        {:ok, name, arity}

      _other ->
        :error
    end
  end

  # `clause(Head, Body)`: enumerates every stored clause for `Head`'s
  # own `{name, arity}` whose (freshened) head unifies with `Head`, one
  # per backtrack, unifying `Body` with that clause's own (freshened)
  # body -- the same `Term.fresh_copy/1` "rename apart together, via a
  # throwaway $clause wrapper" trick `retract_goal/3`'s own
  # `find_matching_clause/4` uses, so `Head`/`Body` share renamed
  # variables correctly when a clause's head and body both reference
  # the same one.
  defp builtin_clause_goal(head, body, db, bindings) do
    case Bindings.resolve(Term, bindings, head) do
      %Var{} ->
        prolog_throw(Exceptions.instantiation_error())

      resolved_head ->
        {name, arity} = Database.indicator(resolved_head)

        Database.clauses_for(db, name, arity)
        |> Enum.reduce(Tree.fail(), fn stored, acc ->
          Tree.disjunction(acc, fn b -> unify_clause_pair(head, body, stored, b) end)
        end)
        |> then(& &1.(bindings))
    end
  end

  defp unify_clause_pair(head, body, {stored_head, stored_body}, bindings) do
    %Compound{args: [fresh_head, fresh_body]} =
      Term.fresh_copy(%Compound{name: :"$clause", args: [stored_head, stored_body]})

    with {:ok, b1} <- Bindings.unify(Term, bindings, head, fresh_head),
         {:ok, b2} <- Bindings.unify(Term, b1, body, fresh_body) do
      Tree.unit().(b2)
    else
      :fail -> Tree.fail().(bindings)
    end
  end

  @spec prolog_throw(term()) :: no_return()
  defp prolog_throw(term), do: Exceptions.prolog_throw(term)
end
