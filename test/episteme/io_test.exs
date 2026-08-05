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

  describe "format/2" do
    test "~w, ~a, ~d, and ~n consume one argument each, in order" do
      output =
        capture_io(fn ->
          solutions(db(), c(:format, ["Hello, ~w! You are ~d years old.~n", [:world, 30]]))
        end)

      assert output == "Hello, world! You are 30 years old.\n"
    end

    test "~s renders a code list as text" do
      output = capture_io(fn -> solutions(db(), c(:format, ["codes: ~s", [[104, 105]]])) end)
      assert output == "codes: hi"
    end

    test "~~ is a literal tilde" do
      output = capture_io(fn -> solutions(db(), c(:format, ["100~~ done", []])) end)
      assert output == "100~ done"
    end

    test "~i skips the next argument without printing it" do
      output = capture_io(fn -> solutions(db(), c(:format, ["~i~w", [:skipped, :kept]])) end)
      assert output == "kept"
    end

    test "a single non-list Args is treated as a one-element list" do
      output = capture_io(fn -> solutions(db(), c(:format, ["val=~w", :foo])) end)
      assert output == "val=foo"
    end

    test "format/1 is format/2 with no arguments" do
      output = capture_io(fn -> solutions(db(), c(:format, ["just text"])) end)
      assert output == "just text"
    end

    test "always succeeds exactly once" do
      capture_io(fn -> assert solutions(db(), c(:format, ["~w", [:foo]])) == [%{}] end)
    end

    test "too few arguments raises domain_error(format_arguments, _)" do
      {result, _output} =
        with_io(fn -> solutions(db(), c(:format, ["~w ~w", [:only_one]])) end)

      assert {:error, %Episteme.Term.Compound{name: :error, args: [formal, _]}} = result
      assert %Episteme.Term.Compound{name: :domain_error, args: [:format_arguments, []]} = formal
    end

    test "~d on a non-integer raises type_error(integer, _)" do
      {result, _output} = with_io(fn -> solutions(db(), c(:format, ["~d", [:foo]])) end)

      assert {:error, %Episteme.Term.Compound{name: :error, args: [formal, _]}} = result
      assert %Episteme.Term.Compound{name: :type_error, args: [:integer, :foo]} = formal
    end

    test "an unrecognized directive raises domain_error(format_directive, _)" do
      {result, _output} = with_io(fn -> solutions(db(), c(:format, ["~z", []])) end)

      assert {:error, %Episteme.Term.Compound{name: :error, args: [formal, _]}} = result
      assert %Episteme.Term.Compound{name: :domain_error, args: [:format_directive, "z"]} = formal
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
