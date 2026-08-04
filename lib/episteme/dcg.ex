defmodule Episteme.Dcg do
  @moduledoc """
  Definite Clause Grammar support: translates a DCG rule/body (`-->`,
  the "difference list" grammar-rule notation) into an ordinary
  Episteme clause/goal, threading two extra arguments -- the list
  before (`S0`) and after (`S`) whatever the rule/body consumes --
  through every nonterminal call. `phrase/2,3` and `dcg_translate/2`
  (`Episteme.Engine`), a `{:dcg, head, body}` `Episteme.Database.consult_forms/2`
  form, and DCG-rule support in `assert/1` (a `-->/2`-shaped clause
  term, same as `:-/2` is already special-cased) are all built on
  `translate_body/3` below.

  Deliberately a practical subset of real DCG translation, not all of
  it: terminals (`[t1, ..., tn]`), embedded plain goals (`{Goal}`, ISO's
  own `'{}'/1` term shape), `cut`, `and/2`, `or/2`, `if_then/2`,
  `if_then_else/3`, `not/1`, a bare nonterminal (atom or compound, any
  other name), and a variable body (translated to `phrase(Var, S0, S)`,
  letting a grammar body be decided at call time). No `call//N`
  pushback support (parameterized higher-order nonterminals) -- not
  yet needed.
  """

  alias Episteme.Term
  alias Episteme.Term.{Compound, Var}

  @doc """
  Translates a whole DCG rule (`Head --> Body`, already parsed/built
  into its own head/body terms) into an ordinary `{Head2, Body2}`
  clause pair, ready for `Episteme.Database.add_clause/2` -- `Head`'s
  own two extra arguments (`S0`, `S`) are appended, and `Body` is
  translated via `translate_body/3`, threaded between them.
  """
  @spec translate_rule(term(), term()) :: {term(), term()}
  def translate_rule(head, body) do
    s0 = Term.new_var("S0")
    s = Term.new_var("S")
    {append_args(head, [s0, s]), translate_body(body, s0, s)}
  end

  @doc "Translates one DCG body term into an ordinary goal, given the incoming (`s0`) and outgoing (`s`) difference-list variables/terms."
  @spec translate_body(term(), term(), term()) :: term()
  def translate_body(list, s0, s) when is_list(list) do
    %Compound{name: :unify, args: [s0, append_terminals(list, s)]}
  end

  def translate_body(%Compound{name: :{}, args: [goal]}, s0, s) do
    and_goal(goal, %Compound{name: :unify, args: [s, s0]})
  end

  def translate_body(:cut, s0, s) do
    and_goal(:cut, %Compound{name: :unify, args: [s, s0]})
  end

  def translate_body(%Compound{name: :and, args: [a, b]}, s0, s) do
    s1 = Term.new_var("_")
    and_goal(translate_body(a, s0, s1), translate_body(b, s1, s))
  end

  def translate_body(%Compound{name: :or, args: [a, b]}, s0, s) do
    %Compound{name: :or, args: [translate_body(a, s0, s), translate_body(b, s0, s)]}
  end

  def translate_body(%Compound{name: :if_then, args: [c, t]}, s0, s) do
    s1 = Term.new_var("_")
    %Compound{name: :if_then, args: [translate_body(c, s0, s1), translate_body(t, s1, s)]}
  end

  def translate_body(%Compound{name: :if_then_else, args: [c, t, e]}, s0, s) do
    s1 = Term.new_var("_")

    %Compound{
      name: :if_then_else,
      args: [translate_body(c, s0, s1), translate_body(t, s1, s), translate_body(e, s0, s)]
    }
  end

  def translate_body(%Compound{name: :not, args: [g]}, s0, s) do
    not_goal = %Compound{name: :not, args: [translate_body(g, s0, Term.new_var("_"))]}
    and_goal(not_goal, %Compound{name: :unify, args: [s, s0]})
  end

  def translate_body(%Var{} = v, s0, s), do: %Compound{name: :phrase, args: [v, s0, s]}
  def translate_body(nonterminal, s0, s), do: append_args(nonterminal, [s0, s])

  defp append_args(%Compound{name: name, args: args}, extra),
    do: %Compound{name: name, args: args ++ extra}

  defp append_args(atom, extra) when is_atom(atom), do: %Compound{name: atom, args: extra}

  defp append_terminals([], tail), do: tail
  defp append_terminals([h | t], tail), do: [h | append_terminals(t, tail)]

  defp and_goal(a, b), do: %Compound{name: :and, args: [a, b]}
end
