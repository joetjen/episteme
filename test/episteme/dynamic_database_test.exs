defmodule Episteme.DynamicDatabaseTest do
  @moduledoc """
  `assert`/`asserta`/`assertz`/`retract`/`retractall`/`abolish`/
  `dynamic`/`clause` exercised through `Episteme.query/2`, the same way
  a caller actually uses them.
  """

  use ExUnit.Case, async: true
  alias Episteme.Term.Compound
  import Episteme.QueryHelper

  describe "assertz/1 and assert/1" do
    test "assertz/1 adds a fact visible to subsequent queries against the same db" do
      db = db()
      assert {:error, _} = solutions(db, c(:foo, [1]))
      assert solutions(db, c(:assertz, [c(:foo, [1])])) == [%{}]
      assert solutions(db, c(:foo, [1])) == [%{}]
      assert solutions(db, c(:foo, [2])) == []
    end

    test "assert/1 is an alias for assertz/1 (appends)" do
      db = db()
      solutions(db, c(:assert, [c(:p, [1])]))
      solutions(db, c(:assert, [c(:p, [2])]))
      assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}, %{"X" => 2}]
    end

    test "asserting a Head :- Body term stores a rule" do
      db = db()
      x = var("X")
      y = var("Y")
      clause = c(:":-", [c(:double, [x, y]), c(:is, [y, c(:*, [x, 2])])])
      solutions(db, c(:assertz, [clause]))

      assert solutions(db, c(:double, [5, var("Z")])) == [%{"Z" => 10}]
    end

    test "unbound variables in the asserted clause become the stored clause's own private variables" do
      db = db()
      x = var("X")
      solutions(db, c(:assertz, [c(:p, [x])]))

      assert solutions(db, c(:p, [1])) == [%{}]
      assert solutions(db, c(:p, [2])) == [%{}]
    end

    test "already-bound variables are resolved before storage" do
      db = db()
      x = var("X")
      body = c(:and, [c(:unify, [x, 42]), c(:assertz, [c(:p, [x])])])
      solutions(db, body)

      assert solutions(db, c(:p, [42])) == [%{}]
      assert solutions(db, c(:p, [var("_")])) == [%{}]
    end
  end

  describe "asserta/1" do
    test "prepends rather than appends" do
      db = db()
      solutions(db, c(:assertz, [c(:p, [1])]))
      solutions(db, c(:asserta, [c(:p, [0])]))
      solutions(db, c(:assertz, [c(:p, [2])]))

      assert solutions(db, c(:p, [var("X")])) == [%{"X" => 0}, %{"X" => 1}, %{"X" => 2}]
    end
  end

  describe "retract/1" do
    test "removes the first matching clause and keeps its bindings" do
      db = db([{:fact, c(:p, [1])}, {:fact, c(:p, [2])}, {:fact, c(:p, [3])}])

      assert solutions(db, c(:retract, [c(:p, [var("X")])])) == [%{"X" => 1}]
      assert solutions(db, c(:p, [var("X")])) == [%{"X" => 2}, %{"X" => 3}]
    end

    test "fails without mutating anything when no clause unifies" do
      db = db([{:fact, c(:p, [1])}])

      assert solutions(db, c(:retract, [c(:p, [2])])) == []
      assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}]
    end

    test "matches head and body together, removing the right rule among several" do
      x = var("X")

      db =
        db([
          {:rule, c(:q, [x]), c(:>, [x, 0])},
          {:rule, c(:q, [x]), c(:<, [x, 0])}
        ])

      solutions(db, c(:retract, [c(:":-", [c(:q, [var("Y")]), c(:>, [var("Y"), 0])])]))

      assert solutions(db, c(:q, [5])) == []
      assert solutions(db, c(:q, [-5])) == [%{}]
    end

    test "an unbound argument raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:retract, [var("X")]))
    end
  end

  describe "retractall/1" do
    test "removes every clause whose head unifies with the pattern, regardless of body" do
      x = var("X")

      db =
        db([
          {:fact, c(:p, [1])},
          {:rule, c(:p, [x]), c(:>, [x, 10])},
          {:fact, c(:p, [3])}
        ])

      assert solutions(db, c(:retractall, [c(:p, [var("_")])])) == [%{}]
      assert solutions(db, c(:p, [var("X")])) == []
    end

    test "always succeeds, even against an undefined predicate" do
      assert solutions(db(), c(:retractall, [c(:nonexistent, [var("_")])])) == [%{}]
    end

    test "leaves the predicate defined-but-empty: later calls fail, they don't raise existence_error" do
      db = db([{:fact, c(:p, [1])}])
      solutions(db, c(:retractall, [c(:p, [var("_")])]))

      assert solutions(db, c(:p, [1])) == []
    end

    test "does not bind the pattern's own variables" do
      db = db([{:fact, c(:p, [1])}, {:fact, c(:p, [2])}])

      assert solutions(db, c(:retractall, [c(:p, [var()])])) == [%{}]
    end
  end

  describe "abolish/1" do
    test "removes clauses and undefines the predicate: a later call raises existence_error again" do
      db = db([{:fact, c(:p, [1])}])

      assert solutions(db, c(:abolish, [c(:/, [:p, 1])])) == [%{}]
      assert {:error, %Compound{name: :error, args: [formal, _]}} = solutions(db, c(:p, [1]))
      assert %Compound{name: :existence_error, args: [:procedure, _]} = formal
    end

    test "unlike retractall/1, defined?/3 goes back to false" do
      db = db([{:fact, c(:p, [1])}])
      solutions(db, c(:abolish, [c(:/, [:p, 1])]))

      refute Episteme.Database.defined?(db, :p, 1)
    end

    test "a malformed indicator raises type_error(predicate_indicator, _)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:abolish, [:not_an_indicator]))

      assert %Compound{name: :type_error, args: [:predicate_indicator, :not_an_indicator]} =
               formal
    end
  end

  describe "dynamic/1" do
    test "declares a predicate defined with zero clauses: a call fails, it doesn't raise existence_error" do
      db = db()

      assert solutions(db, c(:dynamic, [c(:/, [:counter, 1])])) == [%{}]
      assert solutions(db, c(:counter, [var("X")])) == []
    end

    test "assert/1 works immediately afterward" do
      db = db()
      solutions(db, c(:dynamic, [c(:/, [:counter, 1])]))
      solutions(db, c(:assertz, [c(:counter, [1])]))

      assert solutions(db, c(:counter, [var("X")])) == [%{"X" => 1}]
    end

    test "a no-op when the predicate already has clauses -- existing clauses survive" do
      db = db([{:fact, c(:p, [1])}])
      solutions(db, c(:dynamic, [c(:/, [:p, 1])]))

      assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}]
    end

    test "a list of indicators declares each one" do
      db = db()
      solutions(db, c(:dynamic, [[c(:/, [:a, 1]), c(:/, [:b, 2])]]))

      assert solutions(db, c(:a, [var("_")])) == []
      assert solutions(db, c(:b, [var("_"), var("_")])) == []
    end

    test "a malformed indicator raises type_error(predicate_indicator, _)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:dynamic, [:not_an_indicator]))

      assert %Compound{name: :type_error, args: [:predicate_indicator, :not_an_indicator]} =
               formal
    end
  end

  describe "clause/2" do
    test "enumerates every matching clause's head/body, one per backtrack" do
      x = var("X")

      db =
        db([
          {:fact, c(:p, [1])},
          {:rule, c(:p, [x]), c(:>, [x, 10])},
          {:fact, c(:p, [3])}
        ])

      results = solutions(db, c(:clause, [c(:p, [var("Arg")]), var("Body")]))

      assert length(results) == 3
      assert %{"Arg" => 1, "Body" => true} in results
      assert %{"Arg" => 3, "Body" => true} in results

      assert Enum.any?(results, fn
               %{"Arg" => %Episteme.Term.Var{}, "Body" => %Compound{name: :>, args: [_, 10]}} ->
                 true

               _ ->
                 false
             end)
    end

    test "Head and Body share renamed variables from the same clause" do
      x = var("X")
      y = var("Y")
      db = db([{:rule, c(:double, [x, y]), c(:is, [y, c(:*, [x, 2])])}])

      h1 = var("H1")
      h2 = var("H2")

      assert [%{"H1" => bound_h1, "H2" => bound_h2, "B" => body}] =
               solutions(db, c(:clause, [c(:double, [h1, h2]), var("B")]))

      assert %Episteme.Term.Var{} = bound_h1
      assert %Episteme.Term.Var{} = bound_h2

      assert %Compound{
               name: :is,
               args: [^bound_h2, %Compound{name: :*, args: [^bound_h1, 2]}]
             } = body
    end

    test "an unbound Head raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:clause, [var("H"), var("B")]))
    end

    test "no matching clause just fails" do
      db = db([{:fact, c(:p, [1])}])
      assert solutions(db, c(:clause, [c(:p, [2]), var("B")])) == []
    end

    test "an undefined predicate just fails, not existence_error" do
      assert solutions(db(), c(:clause, [c(:nonexistent, [1]), var("B")])) == []
    end
  end
end
