defmodule Episteme.StringsTest do
  use ExUnit.Case, async: true
  alias Episteme.Term.Compound
  import Episteme.QueryHelper

  describe "atom_codes/2 and atom_chars/2" do
    test "atom -> list, in both directions" do
      assert solutions(db(), c(:atom_codes, [:hi, var("X")])) == [%{"X" => ~c"hi"}]
      assert solutions(db(), c(:atom_codes, [var("A"), ~c"hi"])) == [%{"A" => :hi}]

      assert solutions(db(), c(:atom_chars, [:hi, var("X")])) == [%{"X" => [:h, :i]}]
      assert solutions(db(), c(:atom_chars, [var("A"), [:h, :i]])) == [%{"A" => :hi}]
    end

    test "[] round-trips as the atom [], not an empty list of codes" do
      assert solutions(db(), c(:atom_codes, [[], var("X")])) == [%{"X" => ~c"[]"}]
    end

    test "an unbound atom and an unbound list together raise instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:atom_codes, [var("A"), var("X")]))
    end
  end

  describe "atom_length/2" do
    test "counts characters, not bytes" do
      assert solutions(db(), c(:atom_length, [:hello, var("X")])) == [%{"X" => 5}]
    end
  end

  describe "char_code/2" do
    test "both directions" do
      assert solutions(db(), c(:char_code, [:a, var("X")])) == [%{"X" => 97}]
      assert solutions(db(), c(:char_code, [var("C"), 97])) == [%{"C" => :a}]
    end
  end

  describe "number_codes/2 and number_chars/2" do
    test "number -> text and back, for both integers and floats" do
      assert solutions(db(), c(:number_codes, [123, var("X")])) == [%{"X" => ~c"123"}]
      assert solutions(db(), c(:number_codes, [var("N"), ~c"123"])) == [%{"N" => 123}]
      assert solutions(db(), c(:number_codes, [3.5, var("X")])) == [%{"X" => ~c"3.5"}]
      assert solutions(db(), c(:number_codes, [var("N"), ~c"3.5"])) == [%{"N" => 3.5}]

      assert solutions(db(), c(:number_chars, [123, var("X")])) == [
               %{"X" => [:"1", :"2", :"3"]}
             ]
    end

    test "text that isn't a valid number raises type_error(number, _)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:number_codes, [var("N"), ~c"abc"]))

      assert %Compound{name: :type_error, args: [:number, "abc"]} = formal
    end
  end

  describe "upcase_atom/2 and downcase_atom/2" do
    test "case conversion" do
      assert solutions(db(), c(:upcase_atom, [:hello, var("X")])) == [%{"X" => :HELLO}]
      assert solutions(db(), c(:downcase_atom, [:HELLO, var("X")])) == [%{"X" => :hello}]
    end
  end

  describe "atom_concat/3" do
    test "concatenates when both parts are bound" do
      assert solutions(db(), c(:atom_concat, [:foo, :bar, var("X")])) == [%{"X" => :foobar}]
    end

    test "enumerates every split when only the whole is bound" do
      assert solutions(db(), c(:atom_concat, [var("X"), var("Y"), :ab])) == [
               %{"X" => :"", "Y" => :ab},
               %{"X" => :a, "Y" => :b},
               %{"X" => :ab, "Y" => :""}
             ]
    end

    test "unification narrows the split when one part is already bound" do
      assert solutions(db(), c(:atom_concat, [:fo, var("Y"), :foobar])) == [%{"Y" => :obar}]
    end
  end

  describe "sub_atom/5" do
    test "with only Atom bound, enumerates every decomposition, Before outer then Length inner" do
      assert solutions(db(), c(:sub_atom, [:ab, var("B"), var("L"), var("A"), var("S")])) == [
               %{"B" => 0, "L" => 0, "A" => 2, "S" => :""},
               %{"B" => 0, "L" => 1, "A" => 1, "S" => :a},
               %{"B" => 0, "L" => 2, "A" => 0, "S" => :ab},
               %{"B" => 1, "L" => 0, "A" => 1, "S" => :""},
               %{"B" => 1, "L" => 1, "A" => 0, "S" => :b},
               %{"B" => 2, "L" => 0, "A" => 0, "S" => :""}
             ]
    end

    test "Before and Length bound narrows to a single, deterministic answer" do
      assert solutions(db(), c(:sub_atom, [:abc, 1, 2, var("A"), var("S")])) == [
               %{"A" => 0, "S" => :bc}
             ]
    end

    test "Sub and Length bound finds every matching occurrence" do
      assert solutions(db(), c(:sub_atom, [:abcabc, var("B"), 3, var("A"), :abc])) == [
               %{"B" => 0, "A" => 3},
               %{"B" => 3, "A" => 0}
             ]
    end

    test "Sub is always an atom, even when Atom was a string" do
      assert solutions(db(), c(:sub_atom, ["ab", 0, 1, var("A"), var("S")])) == [
               %{"A" => 1, "S" => :a}
             ]
    end
  end

  describe "atomic_list_concat/2 and /3" do
    test "/2 concatenates a bound list of atomics" do
      assert solutions(db(), c(:atomic_list_concat, [[:foo, :bar, 1], var("X")])) == [
               %{"X" => :foobar1}
             ]
    end

    test "/3 joins with a separator when the list is bound" do
      assert solutions(db(), c(:atomic_list_concat, [[:foo, :bar], :-, var("X")])) == [
               %{"X" => :"foo-bar"}
             ]
    end

    test "/3 splits on the separator when the list is unbound" do
      assert solutions(db(), c(:atomic_list_concat, [var("X"), :-, :"foo-bar-baz"])) == [
               %{"X" => [:foo, :bar, :baz]}
             ]
    end
  end

  describe "atom_string/2 and string_to_atom/2" do
    test "both directions, both predicates" do
      assert solutions(db(), c(:atom_string, [:hello, var("S")])) == [%{"S" => "hello"}]
      assert solutions(db(), c(:atom_string, [var("A"), "hello"])) == [%{"A" => :hello}]
      assert solutions(db(), c(:string_to_atom, ["hello", var("A")])) == [%{"A" => :hello}]
      assert solutions(db(), c(:string_to_atom, [var("S"), :hello])) == [%{"S" => "hello"}]
    end
  end

  describe "string_concat/3" do
    test "concatenates when both parts are bound, producing a string" do
      assert solutions(db(), c(:string_concat, ["foo", "bar", var("X")])) == [
               %{"X" => "foobar"}
             ]
    end

    test "enumerates every split when only the whole is bound" do
      assert solutions(db(), c(:string_concat, [var("X"), var("Y"), "ab"])) == [
               %{"X" => "", "Y" => "ab"},
               %{"X" => "a", "Y" => "b"},
               %{"X" => "ab", "Y" => ""}
             ]
    end
  end

  describe "string_chars/2 and string_codes/2" do
    test "single-character strings, not atoms, unlike atom_chars/2" do
      assert solutions(db(), c(:string_chars, ["hi", var("X")])) == [%{"X" => ["h", "i"]}]
      assert solutions(db(), c(:string_chars, [var("S"), ["h", "i"]])) == [%{"S" => "hi"}]
    end

    test "codes are the same plain integer lists atom_codes/2 uses" do
      assert solutions(db(), c(:string_codes, ["hi", var("X")])) == [%{"X" => ~c"hi"}]
    end
  end

  describe "string_length/2 and number_string/2" do
    test "string_length/2 counts characters" do
      assert solutions(db(), c(:string_length, ["hello", var("X")])) == [%{"X" => 5}]
    end

    test "number_string/2, both directions" do
      assert solutions(db(), c(:number_string, [var("N"), "42"])) == [%{"N" => 42}]
      assert solutions(db(), c(:number_string, [42, var("S")])) == [%{"S" => "42"}]
    end
  end

  describe "split_string/4" do
    test "splits on any separator character, no padding" do
      assert solutions(db(), c(:split_string, ["hello world foo", " ", "", var("X")])) == [
               %{"X" => ["hello", "world", "foo"]}
             ]
    end

    test "empty separator means no split, just padding stripped from both ends" do
      assert solutions(db(), c(:split_string, ["  hi  ", "", " ", var("X")])) == [
               %{"X" => ["hi"]}
             ]
    end

    test "pads/strips each field independently after splitting" do
      assert solutions(db(), c(:split_string, [" a , b ,c ", ",", " ", var("X")])) == [
               %{"X" => ["a", "b", "c"]}
             ]
    end
  end

  describe "string/1 type check" do
    test "true for a real string, false for an atom or anything else" do
      assert solutions(db(), c(:string, ["abc"])) == [%{}]
      assert solutions(db(), c(:string, [:abc])) == []
      assert solutions(db(), c(:string, [1])) == []
    end
  end

  describe "standard order of terms includes strings, between Atom and Compound" do
    test "a string always orders after every atom" do
      assert solutions(db(), c(:order_less, [:zzz, "aaa"])) == [%{}]
    end

    test "a string always orders before every compound" do
      assert solutions(db(), c(:order_less, ["zzz", c(:a, [1])])) == [%{}]
    end
  end
end
