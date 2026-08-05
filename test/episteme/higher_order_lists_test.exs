defmodule Episteme.HigherOrderListsTest do
  use ExUnit.Case, async: true

  import Episteme.QueryHelper

  # A rule's head and body must share the *same* Var struct (same ref)
  # for each logical variable -- calling `var("X")` a second time mints
  # an unrelated fresh variable that happens to share a display name,
  # which unifies with nothing and leaves the body's own copy unbound.
  # These helpers build each fixture once, correctly, and are reused
  # across every test below instead of repeating the mistake per test.
  defp positive_db do
    x = var("X")
    db([{:rule, c(:positive, [x]), c(:>, [x, 0])}])
  end

  defp add_db do
    x = var("X")
    acc0 = var("Acc0")
    acc = var("Acc")
    db([{:rule, c(:add, [x, acc0, acc]), c(:is, [acc, c(:+, [acc0, x])])}])
  end

  defp add3_db do
    x = var("X")
    y = var("Y")
    acc0 = var("Acc0")
    acc = var("Acc")
    db([{:rule, c(:add3, [x, y, acc0, acc]), c(:is, [acc, c(:+, [acc0, c(:+, [x, y])])])}])
  end

  defp mac_db do
    x = var("X")
    y = var("Y")
    acc0 = var("Acc0")
    acc = var("Acc")
    db([{:rule, c(:mac, [x, y, acc0, acc]), c(:is, [acc, c(:+, [acc0, c(:*, [x, y])])])}])
  end

  defp double_db do
    x = var("X")
    y = var("Y")
    db([{:rule, c(:double, [x, y]), c(:is, [y, c(:*, [x, 2])])}])
  end

  describe "include/3, exclude/3" do
    test "include/3 keeps elements where Goal succeeds" do
      assert solutions(positive_db(), c(:include, [:positive, [1, -2, 3, -4], var("L")])) ==
               [%{"L" => [1, 3]}]
    end

    test "exclude/3 keeps elements where Goal fails" do
      assert solutions(positive_db(), c(:exclude, [:positive, [1, -2, 3, -4], var("L")])) ==
               [%{"L" => [-2, -4]}]
    end

    test "an empty list always succeeds with an empty result" do
      assert solutions(positive_db(), c(:include, [:positive, [], var("L")])) == [%{"L" => []}]
    end

    test "an unbound or improper list fails" do
      assert solutions(positive_db(), c(:include, [:positive, var("L"), var("R")])) == []
    end
  end

  describe "foldl/4 (one list)" do
    test "sums a list via an accumulator-threading user predicate" do
      assert solutions(add_db(), c(:foldl, [:add, [1, 2, 3, 4], 0, var("Sum")])) ==
               [%{"Sum" => 10}]
    end

    test "an empty list just unifies V with V0" do
      assert solutions(add_db(), c(:foldl, [:add, [], 99, var("Sum")])) == [%{"Sum" => 99}]
    end

    test "mismatched list lengths (in the 2-list form) fail" do
      assert solutions(add3_db(), c(:foldl, [:add3, [1, 2, 3], [1, 2], 0, var("Sum")])) == []
    end
  end

  describe "foldl/5 (two lists in lockstep)" do
    test "pairwise-multiplies then accumulates (a dot product)" do
      assert solutions(mac_db(), c(:foldl, [:mac, [1, 2, 3], [4, 5, 6], 0, var("Sum")])) ==
               [%{"Sum" => 32}]
    end
  end

  describe "maplist/2 (one list)" do
    test "succeeds iff Goal succeeds for every element" do
      assert solutions(positive_db(), c(:maplist, [:positive, [1, 2, 3]])) == [%{}]
      assert solutions(positive_db(), c(:maplist, [:positive, [1, -2, 3]])) == []
    end

    test "an empty list always succeeds" do
      assert solutions(positive_db(), c(:maplist, [:positive, []])) == [%{}]
    end
  end

  describe "maplist/3 (two lists in lockstep)" do
    test "checks a relation holds pairwise" do
      assert solutions(double_db(), c(:maplist, [:double, [1, 2, 3], [2, 4, 6]])) == [%{}]
      assert solutions(double_db(), c(:maplist, [:double, [1, 2, 3], [2, 4, 7]])) == []
    end

    test "an unbound second list is built and unified with fresh results" do
      assert solutions(double_db(), c(:maplist, [:double, [1, 2, 3], var("L")])) ==
               [%{"L" => [2, 4, 6]}]
    end

    test "both lists unbound fails -- no known length to work from" do
      assert solutions(double_db(), c(:maplist, [:double, var("A"), var("B")])) == []
    end
  end
end
