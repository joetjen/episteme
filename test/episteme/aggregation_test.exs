defmodule Episteme.AggregationTest do
  use ExUnit.Case, async: true
  import Episteme.QueryHelper

  describe "findall/3" do
    # `x`/`y` below are named "_" (`var/0`'s default) so they're excluded
    # from the query's own reported variables -- findall/3 never binds
    # its Goal's variables in the *caller's* bindings, so a *named*
    # query variable used only inside Goal would legitimately come back
    # unbound in the solution map too, the same documented behavior
    # `var/1` gets at the top level (see EngineTest's "var/nonvar" test).
    test "collects the template for every solution, in order" do
      db = db([{:fact, c(:num, [1])}, {:fact, c(:num, [2])}, {:fact, c(:num, [3])}])
      x = var()

      assert solutions(db, c(:findall, [x, c(:num, [x]), var("L")])) == [%{"L" => [1, 2, 3]}]
    end

    test "yields [] rather than failing when the goal has no solutions" do
      db = db([{:fact, c(:num, [1])}])
      x = var()
      goal = c(:and, [c(:num, [x]), c(:>, [x, 100])])

      assert solutions(db, c(:findall, [x, goal, var("L")])) == [%{"L" => []}]
    end

    test "the template can differ from the goal's variables" do
      db = db([{:fact, c(:parent, [:tom, :bob])}, {:fact, c(:parent, [:tom, :liz])}])
      x = var()
      y = var()

      assert solutions(db, c(:findall, [c(:pair, [x, y]), c(:parent, [x, y]), var("L")])) == [
               %{
                 "L" => [
                   %Episteme.Term.Compound{name: :pair, args: [:tom, :bob]},
                   %Episteme.Term.Compound{name: :pair, args: [:tom, :liz]}
                 ]
               }
             ]
    end

    test "is cut-opaque: a cut inside the goal doesn't escape to the caller" do
      db =
        db([
          {:rule, c(:g, [1]), :cut},
          {:fact, c(:g, [2])},
          {:fact, c(:p, [1])},
          {:fact, c(:p, [2])}
        ])

      gx = var()
      assert solutions(db, c(:findall, [gx, c(:g, [gx]), var("L")])) == [%{"L" => [1]}]

      # the outer choice points (over p/1) survive the findall/3 call
      x = var("X")

      assert solutions(db, c(:and, [c(:findall, [gx, c(:g, [gx]), var("_")]), c(:p, [x])])) == [
               %{"X" => 1},
               %{"X" => 2}
             ]
    end
  end

  describe "forall/2" do
    test "succeeds when every solution of Cond has a solution of Action" do
      db = db([{:fact, c(:num, [1])}, {:fact, c(:num, [2])}, {:fact, c(:num, [3])}])
      x = var()

      assert solutions(db, c(:forall, [c(:num, [x]), c(:>, [x, 0])])) == [%{}]
    end

    test "fails when some solution of Cond has no solution of Action" do
      db = db([{:fact, c(:num, [1])}, {:fact, c(:num, [2])}])
      x = var()

      assert solutions(db, c(:forall, [c(:num, [x]), c(:>, [x, 1])])) == []
    end

    test "vacuously succeeds when Cond has no solutions" do
      db = db()
      assert solutions(db, c(:forall, [:fail, :fail])) == [%{}]
    end

    test "does not bind Cond's or Action's variables in the caller" do
      db = db([{:fact, c(:num, [1])}])
      x = var()

      assert solutions(db, c(:forall, [c(:num, [x]), true])) == [%{}]
    end
  end

  describe "between/3" do
    test "enumerates every integer in [Low, High] in order when X is unbound" do
      assert solutions(db(), c(:between, [1, 5, var("X")])) == [
               %{"X" => 1},
               %{"X" => 2},
               %{"X" => 3},
               %{"X" => 4},
               %{"X" => 5}
             ]
    end

    test "Low == High yields exactly one solution" do
      assert solutions(db(), c(:between, [3, 3, var("X")])) == [%{"X" => 3}]
    end

    test "Low > High yields no solutions" do
      assert solutions(db(), c(:between, [5, 1, var("X")])) == []
    end

    test "checks membership when X is already bound" do
      assert solutions(db(), c(:between, [1, 5, 3])) == [%{}]
      assert solutions(db(), c(:between, [1, 5, 9])) == []
    end

    test "Low/High are evaluated as arithmetic expressions" do
      assert solutions(db(), c(:between, [c(:+, [1, 1]), c(:*, [2, 2]), var("X")])) == [
               %{"X" => 2},
               %{"X" => 3},
               %{"X" => 4}
             ]
    end

    test "a non-integer bound raises a type_error" do
      assert {:error, %Episteme.Term.Compound{name: :error, args: [formal, _]}} =
               solutions(db(), c(:between, [1.5, 5, var("X")]))

      assert %Episteme.Term.Compound{name: :type_error, args: [:integer, 1.5]} = formal
    end
  end
end
