defmodule Episteme.DcgTest do
  use ExUnit.Case, async: true
  alias Episteme.Dcg
  alias Episteme.Term.Compound
  import Episteme.QueryHelper

  describe "Episteme.Dcg.translate_body/3 -- unit tests over term shapes" do
    test "a terminal list unifies S0 with the list appended onto S" do
      s0 = var("S0")
      s = var("S")
      assert Dcg.translate_body([:a, :b], s0, s) == c(:unify, [s0, [:a, :b | s]])
    end

    test "an empty terminal list unifies S0 with S directly" do
      s0 = var("S0")
      s = var("S")
      assert Dcg.translate_body([], s0, s) == c(:unify, [s0, s])
    end

    test "{}/1 runs the embedded goal without consuming input" do
      s0 = var("S0")
      s = var("S")
      embedded = %Compound{name: :{}, args: [c(:integer, [1])]}

      assert Dcg.translate_body(embedded, s0, s) ==
               c(:and, [c(:integer, [1]), c(:unify, [s, s0])])
    end

    test "cut doesn't consume input either" do
      s0 = var("S0")
      s = var("S")
      assert Dcg.translate_body(:cut, s0, s) == c(:and, [:cut, c(:unify, [s, s0])])
    end

    test "and/2 threads a fresh intermediate difference-list variable" do
      s0 = var("S0")
      s = var("S")
      translated = Dcg.translate_body(c(:and, [[:a], [:b]]), s0, s)
      assert %Compound{name: :and, args: [left, right]} = translated
      assert %Compound{name: :unify, args: [^s0, [:a | s1]]} = left
      assert %Compound{name: :unify, args: [^s1, [:b | ^s]]} = right
    end

    test "or/2 offers both branches the same S0/S" do
      s0 = var("S0")
      s = var("S")

      assert Dcg.translate_body(c(:or, [[:a], [:b]]), s0, s) ==
               c(:or, [c(:unify, [s0, [:a | s]]), c(:unify, [s0, [:b | s]])])
    end

    test "not/1 discards its own consumption, leaving S = S0" do
      s0 = var("S0")
      s = var("S")
      translated = Dcg.translate_body(c(:not, [[:a]]), s0, s)

      assert %Compound{name: :and, args: [not_goal, unify_goal]} = translated

      assert %Compound{name: :not, args: [%Compound{name: :unify, args: [^s0, [:a | _]]}]} =
               not_goal

      assert unify_goal == c(:unify, [s, s0])
    end

    test "a bare atom nonterminal gets S0/S appended" do
      s0 = var("S0")
      s = var("S")
      assert Dcg.translate_body(:greeting, s0, s) == c(:greeting, [s0, s])
    end

    test "a compound nonterminal gets S0/S appended after its own arguments" do
      s0 = var("S0")
      s = var("S")
      assert Dcg.translate_body(c(:digit, [5]), s0, s) == c(:digit, [5, s0, s])
    end

    test "a variable body translates to phrase(Var, S0, S)" do
      s0 = var("S0")
      s = var("S")
      v = var("V")
      assert Dcg.translate_body(v, s0, s) == c(:phrase, [v, s0, s])
    end
  end

  describe "Episteme.Dcg.translate_rule/2" do
    test "appends S0/S to the head, threaded through the translated body" do
      {head, body} = Dcg.translate_rule(:greeting, [:hello])

      assert %Compound{name: :greeting, args: [s0, s]} = head
      assert body == c(:unify, [s0, [:hello | s]])
    end
  end

  describe "consulting {:dcg, head, body} forms" do
    test "a simple terminal-only rule" do
      db = db([{:dcg, c(:greeting, []), c(:and, [[:hello], [:world]])}])

      assert solutions(db, c(:phrase, [:greeting, [:hello, :world]])) == [%{}]
      assert solutions(db, c(:phrase, [:greeting, [:bye]])) == []
    end

    test "phrase/3 leaves whatever wasn't consumed in Rest" do
      db = db([{:dcg, c(:greeting, []), c(:and, [[:hello], [:world]])}])

      assert solutions(db, c(:phrase, [:greeting, [:hello, :world, :extra], var("Rest")])) == [
               %{"Rest" => [:extra]}
             ]
    end

    test "multiple clauses for the same nonterminal behave like ordinary disjunction" do
      db = db([{:dcg, c(:yes, []), [:y]}, {:dcg, c(:yes, []), [:yes]}])

      assert solutions(db, c(:phrase, [:yes, [:y]])) == [%{}]
      assert solutions(db, c(:phrase, [:yes, [:yes]])) == [%{}]
      assert solutions(db, c(:phrase, [:yes, [:no]])) == []
    end

    test "a nonterminal with arguments and an embedded {}/1 goal" do
      d = var("D")

      db =
        db([
          {:dcg, c(:digit, [d]), c(:and, [[d], %Compound{name: :{}, args: [c(:integer, [d])]}])}
        ])

      assert solutions(db, c(:phrase, [c(:digit, [var("X")]), [5]])) == [%{"X" => 5}]
      assert solutions(db, c(:phrase, [c(:digit, [var("X")]), [:not_a_digit]])) == []
    end

    test "not/1 inside a DCG body consumes nothing" do
      db = db([{:dcg, c(:not_a, []), c(:not, [[:a]])}])

      assert solutions(db, c(:phrase, [:not_a, [:b], var("Rest")])) == [%{"Rest" => [:b]}]
      assert solutions(db, c(:phrase, [:not_a, [:a], var("Rest")])) == []
    end

    test "a nonterminal calling another nonterminal, recursively" do
      x = var("X")
      xs = var("Xs")

      db =
        db([
          {:dcg, c(:digits, [[x]]),
           c(:and, [[x], %Compound{name: :{}, args: [c(:integer, [x])]}])},
          {:dcg, c(:digits, [[x | xs]]),
           c(:and, [
             c(:and, [[x], %Compound{name: :{}, args: [c(:integer, [x])]}]),
             c(:digits, [xs])
           ])}
        ])

      assert solutions(db, c(:phrase, [c(:digits, [var("Ds")]), [1, 2, 3]])) == [
               %{"Ds" => [1, 2, 3]}
             ]
    end
  end

  describe "DCG rules via assert/1, same as a plain -->/2 clause term" do
    test "assert((Head --> Body)), then phrase/2 finds it" do
      db2 = db()
      rule = c(:"-->", [c(:ab, []), c(:and, [[:a], [:b]])])

      assert solutions(db2, c(:assert, [rule])) == [%{}]
      assert solutions(db2, c(:phrase, [:ab, [:a, :b]])) == [%{}]
    end
  end

  describe "dcg_translate/2" do
    test "unifies Clause with the translated ordinary clause, without storing it" do
      rule = c(:"-->", [:greeting, [:hello]])
      assert [%{"Clause" => clause}] = solutions(db(), c(:dcg_translate, [rule, var("Clause")]))

      assert %Compound{name: :":-", args: [head, body]} = clause
      assert %Compound{name: :greeting, args: [s0, s]} = head
      assert body == c(:unify, [s0, [:hello | s]])
    end

    test "an unbound Rule raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:dcg_translate, [var("Rule"), var("Clause")]))
    end
  end

  describe "phrase/2,3 with an unbound Body" do
    test "raises instantiation_error instead of looping" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:phrase, [var("Body"), []]))

      assert formal == :instantiation_error
    end
  end
end
