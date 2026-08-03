defmodule Episteme.DynamicDatabaseTest do
  @moduledoc """
  `assert`/`asserta`/`assertz`/`retract`/`retractall` exercised through
  `Episteme.query/2`, the same way a caller actually uses them.
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
end
