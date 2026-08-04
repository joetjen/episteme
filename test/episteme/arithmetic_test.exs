defmodule Episteme.ArithmeticTest do
  use ExUnit.Case, async: true
  alias Episteme.Term.Compound
  import Episteme.QueryHelper

  describe "is/2 over every evaluable functor" do
    test "mod/2 and rem/2 differ on sign, matching floored vs. truncated semantics" do
      assert solutions(db(), c(:is, [var("X"), c(:mod, [-7, 2])])) == [%{"X" => 1}]
      assert solutions(db(), c(:is, [var("X"), c(:rem, [-7, 2])])) == [%{"X" => -1}]
    end

    test "sign/1" do
      assert solutions(db(), c(:is, [var("X"), c(:sign, [5])])) == [%{"X" => 1}]
      assert solutions(db(), c(:is, [var("X"), c(:sign, [-5])])) == [%{"X" => -1}]
      assert solutions(db(), c(:is, [var("X"), c(:sign, [0])])) == [%{"X" => 0}]
    end

    test "min/2 and max/2" do
      assert solutions(db(), c(:is, [var("X"), c(:min, [3, 7])])) == [%{"X" => 3}]
      assert solutions(db(), c(:is, [var("X"), c(:max, [3, 7])])) == [%{"X" => 7}]
    end

    test "sqrt/1 returns a float" do
      assert solutions(db(), c(:is, [var("X"), c(:sqrt, [16])])) == [%{"X" => 4.0}]
    end

    test "sin/1, cos/1, tan/1, exp/1, and log/1, at values with exact results" do
      assert solutions(db(), c(:is, [var("X"), c(:sin, [0])])) == [%{"X" => 0.0}]
      assert solutions(db(), c(:is, [var("X"), c(:cos, [0])])) == [%{"X" => 1.0}]
      assert solutions(db(), c(:is, [var("X"), c(:tan, [0])])) == [%{"X" => 0.0}]
      assert solutions(db(), c(:is, [var("X"), c(:exp, [0])])) == [%{"X" => 1.0}]
      assert solutions(db(), c(:is, [var("X"), c(:log, [1])])) == [%{"X" => 0.0}]
    end

    test "unary +/1 and -/1" do
      assert solutions(db(), c(:is, [var("X"), c(:+, [5])])) == [%{"X" => 5}]
      assert solutions(db(), c(:is, [var("X"), c(:-, [5])])) == [%{"X" => -5}]
    end

    test "**/2 and ^/2 with a negative exponent fall back to float power" do
      assert solutions(db(), c(:is, [var("X"), c(:**, [2, -1])])) == [%{"X" => 0.5}]
      assert solutions(db(), c(:is, [var("X"), c(:^, [2, 3])])) == [%{"X" => 8}]
    end

    test "//2 stays integer when it divides evenly, else falls back to float" do
      assert solutions(db(), c(:is, [var("X"), c(:/, [6, 3])])) == [%{"X" => 2}]
      assert solutions(db(), c(:is, [var("X"), c(:/, [7, 2])])) == [%{"X" => 3.5}]
    end
  end

  describe "domain and type errors" do
    test "division by zero raises domain_error(non_zero, 0) for /, //, mod, and rem" do
      for op <- [:/, :"//", :mod, :rem] do
        assert {:error, %Compound{name: :error, args: [formal, _]}} =
                 solutions(db(), c(:is, [var("X"), c(op, [1, 0])]))

        assert %Compound{name: :domain_error, args: [:non_zero, 0]} = formal
      end
    end

    test "an unbound variable in an expression raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:is, [var("X"), var("Y")]))
    end

    test "a non-numeric, non-evaluable atom raises type_error(evaluable, _)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:is, [var("X"), :foo]))

      assert %Compound{name: :type_error, args: [:evaluable, :foo]} = formal
    end

    test "an unrecognized compound functor raises type_error(evaluable, _)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:is, [var("X"), c(:frobnicate, [1, 2])]))

      assert %Compound{name: :type_error, args: [:evaluable, %Compound{name: :frobnicate}]} =
               formal
    end
  end

  describe "arithmetic comparisons" do
    test "numeric_equal/2, numeric_not_equal/2, </2, >/2, less_or_equal/2, greater_or_equal/2" do
      assert solutions(db(), c(:numeric_equal, [4, c(:+, [2, 2])])) == [%{}]
      assert solutions(db(), c(:numeric_not_equal, [4, 5])) == [%{}]
      assert solutions(db(), c(:<, [3, 4])) == [%{}]
      assert solutions(db(), c(:>, [4, 3])) == [%{}]
      assert solutions(db(), c(:less_or_equal, [3, 3])) == [%{}]
      assert solutions(db(), c(:greater_or_equal, [3, 3])) == [%{}]
      assert solutions(db(), c(:>, [3, 4])) == []
    end
  end
end
