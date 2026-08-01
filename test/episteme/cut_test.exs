defmodule Episteme.CutTest do
  @moduledoc """
  The two scenarios cut needs to get right ("cut inside disjunction
  inside a clause"; "cut inside a called predicate must NOT affect the
  caller"), plus the classic distinguishing test that rules out a thin
  `Ichor.Backtrack.Tree.once/1` wrapper: cut has an effect even along a
  path that ultimately fails.
  """

  use ExUnit.Case, async: true
  import Episteme.QueryHelper

  test "cut is not once/1: p :- !, fail. with a second clause p :- true. fails outright" do
    db =
      db([
        {:rule, :p, c(:",", [:!, :fail])},
        {:rule, :p, true}
      ])

    assert solutions(db, :p) == []
  end

  test "cut inside a disjunction prunes both the disjunction's remaining alternative and the clause's remaining choice points" do
    x = var("X")

    db =
      db([
        {:rule, c(:r, [x]), c(:";", [c(:",", [c(:=, [x, 1]), :!]), c(:=, [x, 2])])},
        {:fact, c(:r, [3])}
      ])

    assert solutions(db, c(:r, [var("X")])) == [%{"X" => 1}]
  end

  test "cut inside a called predicate does not affect the caller's own choice points" do
    x = var("X")
    y = var("Y")

    db =
      db([
        {:rule, c(:inner, [1]), :!},
        {:fact, c(:inner, [2])},
        {:rule, c(:outer, [x, y]), c(:",", [c(:inner, [x]), c(:q, [y])])},
        {:fact, c(:q, [1])},
        {:fact, c(:q, [2])}
      ])

    assert solutions(db, c(:outer, [var("X"), var("Y")])) == [
             %{"X" => 1, "Y" => 1},
             %{"X" => 1, "Y" => 2}
           ]
  end

  test "once/1 is not cut: it only limits solution count, an unrelated sibling clause still runs" do
    x = var("X")
    db = db([{:rule, c(:p, [x]), c(:once, [c(:member, [x, [1, 2, 3]])])}])

    assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}]
  end

  test "! inside once/1 does not escape to prune the caller's own alternatives" do
    db =
      db([
        {:rule, c(:p, [1]), c(:once, [c(:",", [:!, :fail])])},
        {:fact, c(:p, [2])}
      ])

    assert solutions(db, c(:p, [var("X")])) == [%{"X" => 2}]
  end

  test "! inside \\+ does not escape either" do
    db =
      db([
        {:rule, c(:p, [1]), c(:"\\+", [c(:",", [:!, :fail])])},
        {:fact, c(:p, [2])}
      ])

    assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}, %{"X" => 2}]
  end

  test "! inside call/1 does not escape" do
    db =
      db([
        {:rule, c(:p, [1]), c(:call, [c(:",", [:!, :fail])])},
        {:fact, c(:p, [2])}
      ])

    assert solutions(db, c(:p, [var("X")])) == [%{"X" => 2}]
  end

  test "cut commits to the clause even when goals after it still backtrack normally" do
    x = var("X")

    db =
      db([
        {:rule, c(:p, [x]), c(:",", [:!, c(:member, [x, [1, 2, 3]])])},
        {:rule, c(:p, [var("_")]), true}
      ])

    assert solutions(db, c(:p, [var("X")])) == [%{"X" => 1}, %{"X" => 2}, %{"X" => 3}]
  end
end
