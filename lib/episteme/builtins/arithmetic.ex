defmodule Episteme.Builtins.Arithmetic do
  @moduledoc """
  Evaluates a Prolog arithmetic expression term to an Elixir number
  under `bindings` -- `is/2`'s own right-hand side, and both sides of
  every arithmetic comparison (`numeric_equal/2`, `</2`, ...). Raises (via
  `Episteme.Builtins.Exceptions.prolog_throw/1`) a standard `type_error`
  for anything that isn't a number, a bound variable, or a recognized
  evaluable functor.

  Also `dispatch/3`, wired into `Episteme.Engine`'s builtin-dispatch
  chain the same way `Episteme.Builtins.Lists`/`Episteme.Builtins.Io`
  are: `between/3`, the one integer-generating goal in this family
  (everything else here is a plain expression evaluator, not a
  backtracking goal).
  """

  alias Episteme.Builtins.Exceptions
  alias Episteme.Term
  alias Episteme.Term.{Compound, Var}
  alias Ichor.Backtrack.{Bindings, Tree}

  @spec eval(term(), Bindings.t()) :: number()
  def eval(expr, bindings) do
    case Bindings.resolve(Term, bindings, expr) do
      %Var{} ->
        Exceptions.prolog_throw(Exceptions.instantiation_error())

      n when is_number(n) ->
        n

      %Compound{name: name, args: args} ->
        eval_compound(name, Enum.map(args, &eval(&1, bindings)))

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:evaluable, other))
    end
  end

  defp eval_compound(:+, [a, b]), do: a + b
  defp eval_compound(:-, [a, b]), do: a - b
  defp eval_compound(:*, [a, b]), do: a * b
  defp eval_compound(:/, [a, b]), do: divide(a, b)
  defp eval_compound(:"//", [a, b]), do: int_div(a, b)
  defp eval_compound(:mod, [a, b]), do: floor_mod(a, b)
  defp eval_compound(:rem, [a, b]), do: rem_check(a, b)
  defp eval_compound(:**, [a, b]), do: pow(a, b)
  defp eval_compound(:^, [a, b]), do: pow(a, b)
  defp eval_compound(:abs, [a]), do: abs(a)
  defp eval_compound(:sign, [a]) when a > 0, do: 1
  defp eval_compound(:sign, [a]) when a < 0, do: -1
  defp eval_compound(:sign, [_]), do: 0
  defp eval_compound(:min, [a, b]), do: min(a, b)
  defp eval_compound(:max, [a, b]), do: max(a, b)
  defp eval_compound(:sqrt, [a]), do: :math.sqrt(a)
  defp eval_compound(:-, [a]), do: -a
  defp eval_compound(:+, [a]), do: a

  defp eval_compound(name, args) do
    Exceptions.prolog_throw(Exceptions.type_error(:evaluable, %Compound{name: name, args: args}))
  end

  defp divide(_a, b) when b == 0,
    do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))

  defp divide(a, b) do
    if is_integer(a) and is_integer(b) and rem(a, b) == 0, do: div(a, b), else: a / b
  end

  defp int_div(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp int_div(a, b) when is_integer(a) and is_integer(b), do: Integer.floor_div(a, b)

  defp floor_mod(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp floor_mod(a, b) when is_integer(a) and is_integer(b), do: Integer.mod(a, b)

  defp rem_check(_a, 0), do: Exceptions.prolog_throw(Exceptions.domain_error(:non_zero, 0))
  defp rem_check(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)

  defp pow(a, b) when is_integer(a) and is_integer(b) and b >= 0, do: trunc(:math.pow(a, b))
  defp pow(a, b), do: :math.pow(a, b)

  @doc "`is/2`, `numeric_equal/2`, `</2` and friends share this: evaluate both sides then apply `cmp`."
  @spec compare(term(), term(), Bindings.t(), (number(), number() -> boolean())) :: boolean()
  def compare(a, b, bindings, cmp), do: cmp.(eval(a, bindings), eval(b, bindings))

  @spec dispatch(atom(), non_neg_integer(), [term()]) :: Ichor.Backtrack.goal() | :not_handled
  def dispatch(:between, 3, [low, high, x]),
    do: fn bindings -> between_goal(low, high, x, bindings) end

  def dispatch(_, _, _), do: :not_handled

  # `between(Low, High, X)`: with `X` unbound, enumerates every integer
  # in `[Low, High]` in order on backtracking; with `X` bound, just
  # checks membership. `Low`/`High` are arithmetic expressions (like
  # `is/2`'s right-hand side), evaluated once up front.
  defp between_goal(low, high, x, bindings) do
    lo = integer_bound(low, bindings)
    hi = integer_bound(high, bindings)

    case Bindings.resolve(Term, bindings, x) do
      n when is_integer(n) -> bool_goal(n >= lo and n <= hi, bindings)
      %Var{} -> enumerate(lo, hi, x, bindings)
      other -> Exceptions.prolog_throw(Exceptions.type_error(:integer, other))
    end
  end

  defp integer_bound(expr, bindings) do
    case eval(expr, bindings) do
      n when is_integer(n) -> n
      n -> Exceptions.prolog_throw(Exceptions.type_error(:integer, n))
    end
  end

  # A bare `lo..hi` range literal auto-picks its step direction from
  # which bound is larger, so `5..1` silently counts *down* instead of
  # being empty -- between/3 must simply have no solutions when
  # `Low > High`, not enumerate backwards.
  defp enumerate(lo, hi, _x, bindings) when lo > hi, do: Tree.fail().(bindings)

  defp enumerate(lo, hi, x, bindings) do
    lo..hi
    |> Enum.reduce(Tree.fail(), fn n, acc ->
      Tree.disjunction(acc, fn b -> unify_goal(x, n, b) end)
    end)
    |> then(& &1.(bindings))
  end

  defp unify_goal(a, b, bindings) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp bool_goal(true, bindings), do: Tree.unit().(bindings)
  defp bool_goal(false, bindings), do: Tree.fail().(bindings)
end
