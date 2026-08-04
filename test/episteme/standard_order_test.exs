defmodule Episteme.StandardOrderTest do
  use ExUnit.Case, async: true

  import Episteme.QueryHelper

  describe "order_less/2, order_greater/2 (real Prolog: @<, @>)" do
    test "Var < Number < Atom < Compound" do
      assert [%{"X" => %Episteme.Term.Var{}}] =
               solutions(db(), c(:order_less, [var("X"), 1]))

      assert solutions(db(), c(:order_less, [1, :a])) == [%{}]
      assert solutions(db(), c(:order_less, [:a, c(:f, [1])])) == [%{}]
    end

    test "numbers compare by value; equal value sorts float before integer" do
      assert solutions(db(), c(:order_less, [1.0, 1])) == [%{}]
      assert solutions(db(), c(:order_greater, [1, 1.0])) == [%{}]
      assert solutions(db(), c(:order_less, [1, 1.0])) == []
    end

    test "atoms compare alphabetically" do
      assert solutions(db(), c(:order_less, [:abc, :abd])) == [%{}]
      assert solutions(db(), c(:order_less, [:b, :a])) == []
    end

    test "compounds compare by arity, then name, then arguments" do
      assert solutions(db(), c(:order_less, [c(:z, [1]), c(:a, [1, 2])])) == [%{}]
      assert solutions(db(), c(:order_less, [c(:f, [1, 2]), c(:f, [1, 3])])) == [%{}]
    end
  end

  describe "order_less_or_equal/2, order_greater_or_equal/2 (real Prolog: @=<, @>=)" do
    test "true on equal terms, unlike order_less/order_greater" do
      assert solutions(db(), c(:order_less_or_equal, [:a, :a])) == [%{}]
      assert solutions(db(), c(:order_greater_or_equal, [:a, :a])) == [%{}]
      assert solutions(db(), c(:order_less, [:a, :a])) == []
      assert solutions(db(), c(:order_greater, [:a, :a])) == []
    end

    test "still respects strict ordering otherwise" do
      assert solutions(db(), c(:order_less_or_equal, [1, 2])) == [%{}]
      assert solutions(db(), c(:order_less_or_equal, [2, 1])) == []
      assert solutions(db(), c(:order_greater_or_equal, [2, 1])) == [%{}]
      assert solutions(db(), c(:order_greater_or_equal, [1, 2])) == []
    end
  end

  describe "compare/3" do
    test "unifies Order with <, =, or > per the standard order of terms" do
      assert solutions(db(), c(:compare, [var("O"), 1, 2])) == [%{"O" => :<}]
      assert solutions(db(), c(:compare, [var("O"), 2, 1])) == [%{"O" => :>}]
      assert solutions(db(), c(:compare, [var("O"), :a, :a])) == [%{"O" => :=}]
    end

    test "1.0 and 1 are equal in value but not in standard order (float sorts first)" do
      assert solutions(db(), c(:compare, [var("O"), 1.0, 1])) == [%{"O" => :<}]
    end

    test "a compound and its own copy compare equal" do
      assert solutions(db(), c(:compare, [var("O"), c(:foo, [1, :a]), c(:foo, [1, :a])])) ==
               [%{"O" => :=}]
    end
  end
end
