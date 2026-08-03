defmodule Episteme.DatabaseTest do
  use ExUnit.Case, async: true

  alias Episteme.Database
  alias Episteme.Term.Compound

  describe "add_clause/2 and clauses_for/3" do
    test "clauses accumulate in declared order, indexed by {name, arity}" do
      db =
        Database.new()
        |> Database.add_clause({%Compound{name: :p, args: [1]}, true})
        |> Database.add_clause({%Compound{name: :p, args: [2]}, true})

      assert Database.clauses_for(db, :p, 1) == [
               {%Compound{name: :p, args: [1]}, true},
               {%Compound{name: :p, args: [2]}, true}
             ]
    end

    test "different arities of the same name are stored separately" do
      db =
        Database.new()
        |> Database.add_fact(%Compound{name: :p, args: [1]})
        |> Database.add_fact(%Compound{name: :p, args: [1, 2]})

      assert Database.clauses_for(db, :p, 1) == [{%Compound{name: :p, args: [1]}, true}]
      assert Database.clauses_for(db, :p, 2) == [{%Compound{name: :p, args: [1, 2]}, true}]
    end

    test "clauses_for/3 returns [] for a predicate that was never added" do
      assert Database.clauses_for(Database.new(), :nope, 3) == []
    end

    test "a bare atom is indexed at arity 0" do
      db = Database.add_fact(Database.new(), :flag)
      assert Database.clauses_for(db, :flag, 0) == [{:flag, true}]
    end
  end

  describe "add_clause_first/2" do
    test "prepends rather than appends" do
      db =
        Database.new()
        |> Database.add_fact(%Compound{name: :p, args: [1]})
        |> Database.add_clause_first({%Compound{name: :p, args: [0]}, true})
        |> Database.add_fact(%Compound{name: :p, args: [2]})

      assert Enum.map(Database.clauses_for(db, :p, 1), fn {%Compound{args: [n]}, true} -> n end) ==
               [0, 1, 2]
    end
  end

  describe "defined?/3" do
    test "false before any clause is added, true after" do
      db = Database.new()
      refute Database.defined?(db, :p, 1)

      db = Database.add_fact(db, %Compound{name: :p, args: [1]})
      assert Database.defined?(db, :p, 1)
    end

    test "stays true after replace_clauses/4 empties the clause list (retractall's contract)" do
      db =
        Database.new()
        |> Database.add_fact(%Compound{name: :p, args: [1]})
        |> Database.replace_clauses(:p, 1, [])

      assert Database.defined?(db, :p, 1)
      assert Database.clauses_for(db, :p, 1) == []
    end
  end

  describe "indicator/1" do
    test "a compound's indicator is {name, arg count}" do
      assert Database.indicator(%Compound{name: :foo, args: [1, 2, 3]}) == {:foo, 3}
    end

    test "a bare atom's indicator is {atom, 0}" do
      assert Database.indicator(:foo) == {:foo, 0}
    end
  end

  describe "consult_forms/2" do
    test "loads facts and rules, ignores directives" do
      db =
        Database.consult_forms(Database.new(), [
          {:fact, %Compound{name: :p, args: [1]}},
          {:rule, %Compound{name: :q, args: [1]}, %Compound{name: :p, args: [1]}},
          {:directive, %Compound{name: :op, args: [700, :xfx, :foo]}}
        ])

      assert Database.defined?(db, :p, 1)
      assert Database.defined?(db, :q, 1)
      refute Database.defined?(db, :op, 3)
    end
  end

  describe "mutation is shared, not copied" do
    test "add_clause/2 mutates the same underlying storage every holder of the value sees" do
      db = Database.new()
      _ = Database.add_fact(db, %Compound{name: :p, args: [1]})

      # `db` itself is a plain Elixir value (never reassigned above), but
      # the backend it points at was mutated in place -- the whole point
      # of a backend-based Database.t() over the old pure-Map one, and
      # what assert/1 in Episteme.Engine relies on.
      assert Database.defined?(db, :p, 1)
    end
  end

  describe "sync/1" do
    test "is a no-op on the in-memory Ets backend" do
      assert Database.sync(Database.new()) == :ok
    end
  end

  describe "close/1" do
    test "releases the default ETS-backed table" do
      db = Database.new()
      table = db.state
      assert :ets.info(table) != :undefined

      assert Database.close(db) == :ok
      assert :ets.info(table) == :undefined
    end
  end

  describe "new/1 with an explicit backend" do
    test "backend: Backends.Ets behaves identically to the default" do
      db = Database.new(backend: Episteme.Database.Backends.Ets)
      db = Database.add_fact(db, :flag)
      assert Database.defined?(db, :flag, 0)
    end
  end
end
