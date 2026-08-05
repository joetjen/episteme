defmodule Episteme.TermTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Episteme.Term
  alias Episteme.Term.Compound
  alias Ichor.Backtrack.Bindings

  describe "Ichor.Backtrack.Term behaviour" do
    test "variables are identified by ref, everything else is atomic" do
      var = Term.new_var("X")
      refute Term.variable?(:atom)
      assert Term.variable?(var)
      assert Term.var_id(var) == var.ref
    end

    test "compounds deconstruct/reconstruct via functor+args" do
      c = %Compound{name: :foo, args: [1, 2]}
      assert Term.compound?(c)
      assert Term.deconstruct(c) == {:foo, [1, 2]}
      assert Term.reconstruct(:foo, [1, 2]) == c
    end

    test "a non-empty list decomposes as the '.'/2 cons functor, [] stays atomic" do
      refute Term.compound?([])
      assert Term.compound?([1, 2])
      assert Term.deconstruct([1, 2]) == {:., [1, [2]]}
      assert Term.reconstruct(:., [1, [2]]) == [1, 2]
    end
  end

  describe "unification (delegated to Ichor.Backtrack.Bindings, exercised through Episteme.Term)" do
    test "list unification binds head/tail through the cons encoding" do
      h = Term.new_var("H")
      t = Term.new_var("T")
      assert {:ok, bindings} = Bindings.unify(Term, Bindings.new(), [h | t], [1, 2, 3])
      assert Bindings.resolve(Term, bindings, h) == 1
      assert Bindings.resolve(Term, bindings, t) == [2, 3]
    end

    test "[] does not unify with a non-empty list" do
      assert Bindings.unify(Term, Bindings.new(), [], [1]) == :fail
    end

    test "compound unification requires matching functor and arity" do
      a = %Compound{name: :foo, args: [1, 2]}
      b = %Compound{name: :foo, args: [1, 2]}
      c = %Compound{name: :bar, args: [1, 2]}
      assert {:ok, _} = Bindings.unify(Term, Bindings.new(), a, b)
      assert Bindings.unify(Term, Bindings.new(), a, c) == :fail
    end
  end

  describe "resolve_deep/2" do
    test "resolves variables nested inside compounds and lists" do
      x = Term.new_var("X")
      {:ok, bindings} = Bindings.unify(Term, Bindings.new(), x, 42)
      term = %Compound{name: :f, args: [x, [x, 1]]}
      assert Term.resolve_deep(term, bindings) == %Compound{name: :f, args: [42, [42, 1]]}
    end
  end

  describe "fresh_copy/1" do
    test "renames every distinct variable apart while preserving sharing" do
      x = Term.new_var("X")
      term = %Compound{name: :f, args: [x, x]}
      %Compound{args: [a, b]} = Term.fresh_copy(term)
      assert a.ref == b.ref
      refute a.ref == x.ref
    end
  end

  describe "ground?/1" do
    test "a compound/list with no variable anywhere, at any depth, is ground" do
      assert Term.ground?(%Compound{name: :f, args: [1, [2, :a]]})
    end

    test "an unbound variable, however deeply nested, makes it non-ground" do
      x = Term.new_var("X")
      refute Term.ground?(x)
      refute Term.ground?(%Compound{name: :f, args: [1, x]})
      refute Term.ground?([1, [x]])
    end
  end

  describe "compare_order/2 (standard order of terms: Var < Number < Atom < String < Compound)" do
    test "a variable orders before any number, atom, string, or compound" do
      x = Term.new_var("X")
      assert Term.compare_order(x, 0) == :lt
      assert Term.compare_order(x, :a) == :lt
      assert Term.compare_order(x, "a") == :lt
      assert Term.compare_order(x, %Compound{name: :f, args: [1]}) == :lt
    end

    test "a number orders before any atom, string, or compound" do
      assert Term.compare_order(0, :a) == :lt
      assert Term.compare_order(0, "a") == :lt
      assert Term.compare_order(999_999, %Compound{name: :a, args: [1]}) == :lt
    end

    test "an atom orders before any string or compound, [] included" do
      assert Term.compare_order(:zzz, "aaa") == :lt
      assert Term.compare_order(:zzz, %Compound{name: :a, args: [1]}) == :lt
      assert Term.compare_order([], %Compound{name: :a, args: [1]}) == :lt
    end

    test "a string orders before any compound, but after every atom" do
      assert Term.compare_order("aaa", %Compound{name: :a, args: [1]}) == :lt
      assert Term.compare_order("aaa", :zzz) == :gt
    end

    test "strings compare alphabetically, same as atoms" do
      assert Term.compare_order("abc", "abd") == :lt
      assert Term.compare_order("b", "a") == :gt
    end

    test "a string is never == an atom with the same characters, structurally or by order" do
      refute Term.structurally_equal?("abc", :abc)
      assert Term.compare_order("abc", :abc) == :gt
    end

    test "numbers compare by value; equal value sorts float before integer" do
      assert Term.compare_order(1, 2) == :lt
      assert Term.compare_order(2, 1) == :gt
      assert Term.compare_order(1.0, 1) == :lt
      assert Term.compare_order(1, 1.0) == :gt
    end

    test "atoms compare alphabetically, [] sorting as if its name were the string \"[]\"" do
      assert Term.compare_order(:abc, :abd) == :lt
      assert Term.compare_order(:b, :a) == :gt
      assert Term.compare_order([], :zzz) == :lt
      assert Term.compare_order([], :!) == :gt
    end

    test "compounds compare by arity first, regardless of name" do
      assert Term.compare_order(%Compound{name: :z, args: [1]}, %Compound{name: :a, args: [1, 2]}) ==
               :lt
    end

    test "same arity: compounds compare by functor name next" do
      assert Term.compare_order(%Compound{name: :a, args: [1]}, %Compound{name: :b, args: [1]}) ==
               :lt
    end

    test "same arity and name: compounds compare argument-by-argument, left to right" do
      assert Term.compare_order(%Compound{name: :f, args: [1, 2]}, %Compound{
               name: :f,
               args: [1, 3]
             }) ==
               :lt

      assert Term.compare_order(%Compound{name: :f, args: [2, 1]}, %Compound{
               name: :f,
               args: [1, 3]
             }) ==
               :gt
    end

    test "a non-empty list compares via the './2' cons functor, same as a compound" do
      assert Term.compare_order([1, 2], [1, 3]) == :lt
      assert Term.compare_order([1], [1, 2]) == :lt
    end

    test "two distinct unbound variables order consistently but arbitrarily" do
      x = Term.new_var("X")
      y = Term.new_var("Y")
      assert Term.compare_order(x, y) in [:lt, :gt]
      assert Term.compare_order(x, y) == invert(Term.compare_order(y, x))
    end
  end

  describe "structurally_equal?/2" do
    test "same shape and value is equal" do
      assert Term.structurally_equal?(%Compound{name: :f, args: [1, :a]}, %Compound{
               name: :f,
               args: [1, :a]
             })
    end

    test "an integer never equals a float" do
      refute Term.structurally_equal?(1, 1.0)
    end

    test "two distinct unbound variables are not equal" do
      refute Term.structurally_equal?(Term.new_var("X"), Term.new_var("Y"))
    end

    test "lists compare element-wise" do
      assert Term.structurally_equal?([1, 2, 3], [1, 2, 3])
      refute Term.structurally_equal?([1, 2], [1, 2, 3])
    end
  end

  # Ground (variable-free) terms built from atoms/integers/strings as
  # leaves, native lists and %Compound{} as containers -- deliberately
  # no floats (an integer and a float at the same value are *not*
  # structurally_equal?/2, so a leaf generator mixing both would need
  # every property below to account for that on its own) and no
  # variables (a fresh Term.new_var/1 in every generated sample would
  # make "generate two terms and compare" properties meaningless, since
  # two freshly generated variables are never structurally equal to one
  # another no matter how the rest of the term matches).
  defp ground_term do
    leaf = one_of([integer(), atom(:alphanumeric), string(:alphanumeric)])

    StreamData.tree(leaf, fn generator ->
      one_of([
        list_of(generator, max_length: 4),
        map({atom(:alphanumeric), list_of(generator, max_length: 4)}, fn {name, args} ->
          %Compound{name: name, args: args}
        end)
      ])
    end)
  end

  defp invert(:lt), do: :gt
  defp invert(:gt), do: :lt
  defp invert(:eq), do: :eq

  describe "invariants over arbitrary ground terms (property-based, via stream_data)" do
    property "structurally_equal?/2 is reflexive" do
      check all(term <- ground_term()) do
        assert Term.structurally_equal?(term, term)
      end
    end

    property "resolve_deep/2 is a no-op on a ground term, regardless of the bindings passed" do
      check all(term <- ground_term()) do
        assert Term.resolve_deep(term, Bindings.new()) == term
      end
    end

    property "unify/4 then resolve/3 round-trips a fresh variable to whatever ground term it was unified with" do
      check all(term <- ground_term()) do
        var = Term.new_var("X")
        assert {:ok, bindings} = Bindings.unify(Term, Bindings.new(), var, term)
        assert Bindings.resolve(Term, bindings, var) == term
      end
    end

    property "fresh_copy/1 preserves shape and every ground (non-variable) leaf value" do
      check all(term <- ground_term()) do
        # `term` itself has no variables to rename, so fresh_copy/1 is
        # the identity here -- the property that actually matters
        # (renaming apart while preserving sharing) is exercised with
        # example-based tests above, since it needs *shared* variable
        # refs as input, which a ground-term generator can't produce.
        assert Term.fresh_copy(term) == term
      end
    end

    property "ground?/1 is true for every arbitrary ground term, by construction" do
      check all(term <- ground_term()) do
        assert Term.ground?(term)
      end
    end

    property "compare_order/2 is reflexive" do
      check all(term <- ground_term()) do
        assert Term.compare_order(term, term) == :eq
      end
    end

    property "compare_order/2 is antisymmetric" do
      check all(a <- ground_term(), b <- ground_term()) do
        assert Term.compare_order(a, b) == invert(Term.compare_order(b, a))
      end
    end

    property "compare_order/2 agrees with structurally_equal?/2 on when two terms are equal" do
      check all(a <- ground_term(), b <- ground_term()) do
        assert Term.compare_order(a, b) == :eq == Term.structurally_equal?(a, b)
      end
    end
  end
end
