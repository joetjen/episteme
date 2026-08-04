defmodule Episteme.DatabaseDetsTest do
  use ExUnit.Case, async: true

  alias Episteme.Database
  alias Episteme.Database.Backends.Dets
  alias Episteme.Term.Compound

  setup do
    file =
      Path.join(
        System.tmp_dir!(),
        "episteme_dets_test_#{System.unique_integer([:positive])}.dets"
      )

    on_exit(fn -> File.rm(file) end)
    %{path: file}
  end

  test "new/1 requires a :file option", %{path: _path} do
    assert_raise ArgumentError, ~r/requires a :file option/, fn ->
      Database.new(backend: Dets)
    end
  end

  test "clauses persist across close/reopen against the same file", %{path: file} do
    db = Database.new(backend: Dets, file: file)
    db = Database.add_fact(db, %Compound{name: :fact, args: [1]})
    Database.sync(db)
    Database.close(db)

    reopened = Database.new(backend: Dets, file: file)
    assert Database.clauses_for(reopened, :fact, 1) == [{%Compound{name: :fact, args: [1]}, true}]
    Database.close(reopened)
  end

  test "behaves like the Ets backend for ordering and defined?/3", %{path: file} do
    db =
      Database.new(backend: Dets, file: file)
      |> Database.add_fact(%Compound{name: :p, args: [1]})
      |> Database.add_clause_first({%Compound{name: :p, args: [0]}, true})

    assert Enum.map(Database.clauses_for(db, :p, 1), fn {%Compound{args: [n]}, true} -> n end) ==
             [0, 1]

    refute Database.defined?(db, :q, 1)
    Database.close(db)
  end
end
