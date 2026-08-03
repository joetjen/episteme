defmodule Episteme.ListsTest do
  use ExUnit.Case, async: true
  import Episteme.QueryHelper

  test "length/2" do
    empty = db()
    assert solutions(empty, c(:length, [[:a, :b, :c], var("N")])) == [%{"N" => 3}]
    assert [%{"L" => list}] = solutions(empty, c(:length, [var("L"), 2]))
    assert length(list) == 2
    assert Enum.all?(list, &match?(%Episteme.Term.Var{}, &1))
    # each generated variable must be independently fresh, not the same
    # variable duplicated -- otherwise unifying the list against two
    # different values in different positions would wrongly conflict
    assert list |> Enum.map(& &1.ref) |> Enum.uniq() |> length() == 2
  end

  test "length/2 with an unbound list builds independently-fresh variables, not one shared variable" do
    l = var("L")
    goal = c(:and, [c(:length, [l, 3]), c(:unify, [l, [:a, :b, :c]])])
    assert solutions(db(), goal) == [%{"L" => [:a, :b, :c]}]
  end

  test "append/3 forwards mode" do
    empty = db()
    assert solutions(empty, c(:append, [[1, 2], [3, 4], var("X")])) == [%{"X" => [1, 2, 3, 4]}]
  end

  test "append/3 splitting mode (first argument unbound)" do
    result = solutions(db(), c(:append, [var("X"), var("Y"), [1, 2, 3]]))
    assert length(result) == 4
    assert %{"X" => [], "Y" => [1, 2, 3]} in result
    assert %{"X" => [1, 2, 3], "Y" => []} in result
  end

  test "member/2 enumerates every element in order" do
    empty = db()

    assert solutions(empty, c(:member, [var("X"), [:a, :b, :c]])) == [
             %{"X" => :a},
             %{"X" => :b},
             %{"X" => :c}
           ]

    assert solutions(empty, c(:member, [:z, [:a, :b, :c]])) == []
  end

  test "reverse/2" do
    assert solutions(db(), c(:reverse, [[1, 2, 3], var("X")])) == [%{"X" => [3, 2, 1]}]
  end

  test "nth0/3 and nth1/3" do
    empty = db()
    assert solutions(empty, c(:nth0, [1, [:a, :b, :c], var("X")])) == [%{"X" => :b}]
    assert solutions(empty, c(:nth1, [1, [:a, :b, :c], var("X")])) == [%{"X" => :a}]
  end

  test "last/2" do
    empty = db()
    assert solutions(empty, c(:last, [[:a, :b, :c], var("X")])) == [%{"X" => :c}]
    assert solutions(empty, c(:last, [[], var("X")])) == []
  end
end
