defmodule Episteme.TermInspectionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Episteme.Term
  alias Episteme.Term.Compound

  import Episteme.QueryHelper

  describe "ground/1" do
    test "a compound with no variables anywhere is ground" do
      assert solutions(db(), c(:ground, [c(:foo, [1, [2, 3], :bar])])) == [%{}]
    end

    test "any unbound variable, however deeply nested, makes it non-ground" do
      assert solutions(db(), c(:ground, [c(:foo, [1, var("X")])])) == []
      assert solutions(db(), c(:ground, [[1, [var("X")]]])) == []
      assert solutions(db(), c(:ground, [var("X")])) == []
    end

    test "a variable already bound to a ground term counts as ground" do
      x = var("X")
      goal = c(:and, [c(:unify, [x, 42]), c(:ground, [x])])
      assert solutions(db(), goal) == [%{"X" => 42}]
    end
  end

  describe "functor/3" do
    test "decomposing a compound" do
      assert solutions(db(), c(:functor, [c(:foo, [:a, :b, :c]), var("F"), var("A")])) ==
               [%{"F" => :foo, "A" => 3}]
    end

    test "decomposing an atomic term (atom or number): itself as name, arity 0" do
      assert solutions(db(), c(:functor, [:foo, var("F"), var("A")])) == [
               %{"F" => :foo, "A" => 0}
             ]

      assert solutions(db(), c(:functor, [42, var("F"), var("A")])) == [%{"F" => 42, "A" => 0}]
    end

    test "a non-empty list decomposes via the './2' cons functor" do
      assert solutions(db(), c(:functor, [[1, 2], var("F"), var("A")])) == [
               %{"F" => :., "A" => 2}
             ]
    end

    test "[] is atomic: functor []/0" do
      assert solutions(db(), c(:functor, [[], var("F"), var("A")])) == [%{"F" => [], "A" => 0}]
    end

    test "constructing a compound from Name/Arity when Term is unbound" do
      assert [%{"T" => %Compound{name: :foo, args: [a, b]}}] =
               solutions(db(), c(:functor, [var("T"), :foo, 2]))

      refute a.ref == b.ref
    end

    test "constructing with arity 0 just unifies Term with Name" do
      assert solutions(db(), c(:functor, [var("T"), :foo, 0])) == [%{"T" => :foo}]
    end

    test "constructing with a non-atom Name and arity > 0 raises type_error(atom, Name)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:functor, [var("T"), 42, 2]))

      assert %Compound{name: :type_error, args: [:atom, 42]} = formal
    end

    test "both Term and Name unbound raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:functor, [var("T"), var("F"), 2]))
    end
  end

  describe "arg/3" do
    test "1-based positional access" do
      t = c(:foo, [:a, :b, :c])
      assert solutions(db(), c(:arg, [1, t, var("X")])) == [%{"X" => :a}]
      assert solutions(db(), c(:arg, [3, t, var("X")])) == [%{"X" => :c}]
    end

    test "out of range (too low or too high) fails, not an error" do
      t = c(:foo, [:a, :b])
      assert solutions(db(), c(:arg, [0, t, var("X")])) == []
      assert solutions(db(), c(:arg, [3, t, var("X")])) == []
    end

    test "a non-compound Term raises type_error(compound, Term)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:arg, [1, :atom, var("X")]))

      assert %Compound{name: :type_error, args: [:compound, :atom]} = formal
    end
  end

  describe "univ/2 (=../2 in ISO's own punctuation)" do
    test "decomposing a compound" do
      assert solutions(db(), c(:univ, [c(:foo, [:a, :b]), var("L")])) ==
               [%{"L" => [:foo, :a, :b]}]
    end

    test "decomposing an atomic term gives a singleton list" do
      assert solutions(db(), c(:univ, [:foo, var("L")])) == [%{"L" => [:foo]}]
      assert solutions(db(), c(:univ, [42, var("L")])) == [%{"L" => [42]}]
    end

    test "constructing a compound from [Name | Args] when Term is unbound" do
      assert solutions(db(), c(:univ, [var("T"), [:foo, :a, :b]])) ==
               [%{"T" => c(:foo, [:a, :b])}]
    end

    test "constructing with a singleton list just unifies Term with Name" do
      assert solutions(db(), c(:univ, [var("T"), [:foo]])) == [%{"T" => :foo}]
    end

    test "a non-atom head with more than one element raises type_error(atom, Head)" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:univ, [var("T"), [42, :a]]))

      assert %Compound{name: :type_error, args: [:atom, 42]} = formal
    end

    test "an empty list raises domain_error(non_empty_list, [])" do
      assert {:error, %Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:univ, [var("T"), []]))

      assert %Compound{name: :domain_error, args: [:non_empty_list, []]} = formal
    end

    test "both Term and List unbound raises instantiation_error" do
      assert {:error, %Compound{name: :error, args: [:instantiation_error, _]}} =
               solutions(db(), c(:univ, [var("T"), var("L")]))
    end
  end

  # Ground (variable-free) terms, mirroring Episteme.TermTest's own
  # generator, but with min_length: 1 on every container -- a 0-arity
  # %Compound{} is a degenerate shape the rest of this codebase never
  # actually produces (0-arity functors are always bare atoms, see
  # Term.reconstruct/2's own %Compound{args: []} vs atom distinction),
  # and would make the functor/3 round-trip property below fail for a
  # reason that has nothing to do with functor/3 itself: decomposing
  # %Compound{name: :foo, args: []} gives {:foo, 0}, but reconstructing
  # from {:foo, 0} correctly builds the bare atom :foo instead (arity 0
  # means "no compound wrapper" per functor/3's own construct-mode
  # semantics), which is a different Elixir value even though both mean
  # the same 0-arity functor in Prolog terms.
  defp ground_term do
    leaf = one_of([integer(), atom(:alphanumeric)])

    StreamData.tree(leaf, fn generator ->
      one_of([
        list_of(generator, min_length: 1, max_length: 4),
        map(
          {atom(:alphanumeric), list_of(generator, min_length: 1, max_length: 4)},
          fn {name, args} -> %Compound{name: name, args: args} end
        )
      ])
    end)
  end

  describe "round-trip invariants (property-based, via stream_data)" do
    property "functor/3 decompose then construct-from-the-same-F/A reproduces the same functor/arity" do
      check all(term <- ground_term()) do
        f = var("F")
        a = var("A")
        t2 = var("T2")
        f2 = var("F2")
        a2 = var("A2")

        goal =
          c(:and, [
            c(:functor, [term, f, a]),
            c(:and, [c(:functor, [t2, f, a]), c(:functor, [t2, f2, a2])])
          ])

        assert [%{"F" => value, "A" => arity, "F2" => value2, "A2" => arity2}] =
                 solutions(db(), goal)

        assert value2 == value
        assert arity2 == arity
      end
    end

    property "univ/2 decompose then construct from the same list reproduces the original term" do
      check all(term <- ground_term()) do
        l = var("L")
        t2 = var("T2")
        goal = c(:and, [c(:univ, [term, l]), c(:univ, [t2, l])])

        assert [%{"T2" => reconstructed}] = solutions(db(), goal)
        assert Term.structurally_equal?(reconstructed, term)
      end
    end
  end
end
