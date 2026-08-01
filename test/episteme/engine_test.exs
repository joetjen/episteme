defmodule Episteme.EngineTest do
  use ExUnit.Case, async: true
  alias Episteme.Term.Compound
  import Episteme.QueryHelper

  describe "unification and backtracking over facts" do
    test "a query with one variable backtracks through every matching fact, in declared order" do
      db =
        db([
          {:fact, c(:parent, [:tom, :bob])},
          {:fact, c(:parent, [:tom, :liz])},
          {:fact, c(:parent, [:bob, :ann])},
          {:fact, c(:parent, [:bob, :pat])}
        ])

      assert solutions(db, c(:parent, [:tom, var("Y")])) == [%{"Y" => :bob}, %{"Y" => :liz}]
      assert solutions(db, c(:parent, [:tom, :ann])) == []
    end

    test "a rule sequences subgoals via conjunction" do
      x = var("X")
      y = var("Y")
      z = var("Z")

      db =
        db([
          {:fact, c(:parent, [:tom, :bob])},
          {:fact, c(:parent, [:bob, :ann])},
          {:fact, c(:parent, [:bob, :pat])},
          {:rule, c(:grandparent, [x, z]), c(:",", [c(:parent, [x, y]), c(:parent, [y, z])])}
        ])

      assert solutions(db, c(:grandparent, [:tom, var("W")])) == [
               %{"W" => :ann},
               %{"W" => :pat}
             ]
    end
  end

  describe "if-then-else" do
    test "commits to the first solution of the condition" do
      x = var("X")
      r = var("R")

      body =
        c(:";", [
          c(:->, [c(:>, [x, 0]), c(:=, [r, :pos])]),
          c(:";", [
            c(:->, [c(:<, [x, 0]), c(:=, [r, :neg])]),
            c(:=, [r, :zero])
          ])
        ])

      db = db([{:rule, c(:sign, [x, r]), body}])

      assert solutions(db, c(:sign, [5, var("R")])) == [%{"R" => :pos}]
      assert solutions(db, c(:sign, [-5, var("R")])) == [%{"R" => :neg}]
      assert solutions(db, c(:sign, [0, var("R")])) == [%{"R" => :zero}]
    end

    test "if-then without else fails when the condition fails" do
      x = var("X")
      db = db([{:rule, c(:t, [x]), c(:->, [c(:>, [x, 0]), true])}])

      assert solutions(db, c(:t, [-1])) == []
      assert solutions(db, c(:t, [1])) == [%{}]
    end
  end

  describe "negation as failure" do
    test "\\+ succeeds when the goal has no solution, without binding anything" do
      x1 = var("X")
      x2 = var("X")

      db =
        db([
          {:rule, c(:even, [x1]), c(:is, [0, c(:mod, [x1, 2])])},
          {:rule, c(:odd, [x2]), c(:"\\+", [c(:even, [x2])])}
        ])

      assert solutions(db, c(:odd, [3])) == [%{}]
      assert solutions(db, c(:odd, [4])) == []
    end
  end

  describe "arithmetic" do
    test "is/2 and standard precedence" do
      empty = db()

      assert solutions(empty, c(:is, [var("X"), c(:+, [2, c(:*, [3, 4])])])) == [%{"X" => 14}]
      assert solutions(empty, c(:is, [var("X"), c(:"//", [7, 2])])) == [%{"X" => 3}]
      assert solutions(empty, c(:is, [var("X"), c(:/, [7, 2])])) == [%{"X" => 3.5}]
      assert solutions(empty, c(:is, [var("X"), c(:**, [2, 10])])) == [%{"X" => 1024}]
      assert solutions(empty, c(:is, [var("X"), c(:-, [3])])) == [%{"X" => -3}]
    end

    test "arithmetic comparisons" do
      empty = db()
      assert solutions(empty, c(:"=:=", [3, 3.0])) == [%{}]
      assert solutions(empty, c(:<, [3, 4])) == [%{}]
      assert solutions(empty, c(:<, [4, 3])) == []
    end
  end

  describe "type checks and unify/compare" do
    test "var/nonvar" do
      empty = db()

      # X stays unbound, so it shows up bound to itself in the answer --
      # exactly real Prolog's own `?- var(X).` toplevel behavior (`X = _G1`),
      # not omitted.
      assert [%{"X" => %Episteme.Term.Var{}}] = solutions(empty, c(:var, [var("X")]))
      assert solutions(empty, c(:nonvar, [:foo])) == [%{}]
      assert solutions(empty, c(:var, [:foo])) == []
    end

    test "==/2 and \\==/2 respect variable identity and numeric type" do
      empty = db()
      x = var("X")
      assert solutions(empty, c(:==, [c(:foo, [x, x]), c(:foo, [1, 1])])) == []

      x2 = var("X")

      goal =
        c(:",", [c(:=, [x2, 1]), c(:==, [c(:foo, [x2, x2]), c(:foo, [1, 1])])])

      assert solutions(empty, goal) == [%{"X" => 1}]

      assert solutions(empty, c(:==, [1, 1.0])) == []
      assert solutions(empty, c(:"\\==", [1, 1.0])) == [%{}]
    end

    test "=/2 unifies, \\=/2 checks non-unifiability without binding" do
      empty = db()

      assert solutions(empty, c(:=, [var("X"), c(:foo, [1, 2])])) == [
               %{"X" => %Compound{name: :foo, args: [1, 2]}}
             ]

      assert solutions(empty, c(:"\\=", [1, 2])) == [%{}]
      # an unbound X unifies with anything, so \=/2 fails here -- it only
      # succeeds once X is already bound to something incompatible.
      assert solutions(empty, c(:"\\=", [var("X"), 1])) == []
      assert solutions(empty, c(:",", [c(:=, [var("X"), 2]), c(:"\\=", [var("X"), 1])])) == []
    end
  end

  describe "exceptions" do
    test "catch/3 catches a thrown error and unifies the catcher" do
      x = var("X")
      y = var("Y")
      r = var("R")
      catcher = c(:error, [var("_"), var("_")])
      body = c(:catch, [c(:is, [r, c(:/, [x, y])]), catcher, c(:=, [r, :undefined])])
      db = db([{:rule, c(:safe_div, [x, y, r]), body}])

      assert solutions(db, c(:safe_div, [10, 2, var("R")])) == [%{"R" => 5}]
      assert solutions(db, c(:safe_div, [10, 0, var("R")])) == [%{"R" => :undefined}]
    end

    test "an uncaught throw surfaces as an engine-level error" do
      assert {:error, _} = solutions(db(), c(:throw, [:my_error]))
    end

    test "calling an undefined predicate raises existence_error" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:nonexistent_pred, [1, 2]))

      assert %Compound{name: :existence_error, args: [:procedure, _]} = formal
    end
  end

  describe "copy_term/2" do
    test "renames unbound variables apart" do
      x = var("X")

      assert [%{"Y" => %Compound{name: :f, args: [a, b]}}] =
               solutions(db(), c(:copy_term, [c(:f, [x, x]), var("Y")]))

      assert a.ref == b.ref
    end
  end
end
