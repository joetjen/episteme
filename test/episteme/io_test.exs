defmodule Episteme.IoTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import Episteme.QueryHelper

  describe "write/1" do
    test "prints canonical functor(args) text with no trailing newline" do
      output = capture_io(fn -> solutions(db(), c(:write, [c(:foo, [1, 2])])) end)
      assert output == "foo(1, 2)"
    end

    test "resolves bound variables before printing" do
      x = var("X")

      output =
        capture_io(fn -> solutions(db(), c(:and, [c(:unify, [x, 42]), c(:write, [x])])) end)

      assert output == "42"
    end

    test "always succeeds exactly once" do
      capture_io(fn -> assert solutions(db(), c(:write, [:foo])) == [%{}] end)
    end
  end

  describe "writeln/1" do
    test "prints text followed by a newline" do
      output = capture_io(fn -> solutions(db(), c(:writeln, [:foo])) end)
      assert output == "foo\n"
    end
  end

  describe "print/1" do
    test "behaves like write/1 (no trailing newline)" do
      output = capture_io(fn -> solutions(db(), c(:print, [[1, 2, 3]])) end)
      assert output == "[1, 2, 3]"
    end
  end

  describe "nl/0" do
    test "prints a single newline and succeeds" do
      output = capture_io(fn -> assert solutions(db(), c(:nl, [])) == [%{}] end)
      assert output == "\n"
    end
  end

  describe "sequencing via conjunction" do
    test "write/1 and nl/0 compose in order, once each" do
      output =
        capture_io(fn ->
          solutions(db(), c(:and, [c(:write, [:a]), c(:and, [c(:write, [:b]), c(:nl, [])])]))
        end)

      assert output == "ab\n"
    end
  end
end
