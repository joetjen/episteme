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

  describe "msort/2" do
    test "sorts by standard order of terms, keeping duplicates" do
      assert solutions(db(), c(:msort, [[3, 1, 2, 1], var("X")])) == [%{"X" => [1, 1, 2, 3]}]
    end

    test "an unbound or improper list fails" do
      assert solutions(db(), c(:msort, [var("L"), var("X")])) == []
      assert solutions(db(), c(:msort, [:not_a_list, var("X")])) == []
    end
  end

  describe "sort/2" do
    test "sorts and removes duplicates by standard order" do
      assert solutions(db(), c(:sort, [[3, 1, 2, 1], var("X")])) == [%{"X" => [1, 2, 3]}]
    end

    test "1 and 1.0 are equal in value but never merged (float precedes int)" do
      assert solutions(db(), c(:sort, [[1, 1.0], var("X")])) == [%{"X" => [1.0, 1]}]
    end
  end

  test "permutation/2 enumerates every ordering" do
    result = solutions(db(), c(:permutation, [[1, 2, 3], var("X")]))
    assert length(result) == 6
    assert %{"X" => [1, 2, 3]} in result
    assert %{"X" => [3, 2, 1]} in result
    assert solutions(db(), c(:permutation, [[], var("X")])) == [%{"X" => []}]
  end

  describe "sum_list/2, max_list/2, min_list/2" do
    test "sum_list/2, including the empty-list identity" do
      assert solutions(db(), c(:sum_list, [[1, 2, 3], var("X")])) == [%{"X" => 6}]
      assert solutions(db(), c(:sum_list, [[], var("X")])) == [%{"X" => 0}]
    end

    test "max_list/2 and min_list/2" do
      assert solutions(db(), c(:max_list, [[3, 1, 2], var("X")])) == [%{"X" => 3}]
      assert solutions(db(), c(:min_list, [[3, 1, 2], var("X")])) == [%{"X" => 1}]
    end

    test "max_list/2 and min_list/2 fail on an empty list" do
      assert solutions(db(), c(:max_list, [[], var("X")])) == []
      assert solutions(db(), c(:min_list, [[], var("X")])) == []
    end
  end

  describe "list_to_set/2" do
    test "removes duplicates, preserving first-occurrence order (not sorted)" do
      assert solutions(db(), c(:list_to_set, [[3, 1, 3, 2, 1], var("X")])) ==
               [%{"X" => [3, 1, 2]}]
    end
  end
end
