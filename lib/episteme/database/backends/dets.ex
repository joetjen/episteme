defmodule Episteme.Database.Backends.Dets do
  @moduledoc """
  An on-disk `Episteme.Database.Backend`, for a database that should
  survive past the owning process (or the VM) -- same `{name, arity}`-keyed
  `:set` shape as `Episteme.Database.Backends.Ets`, backed by `:dets`
  instead. Requires a `:file` option (a binary or charlist path) on
  `Episteme.Database.new/1`; `:table` names the DETS table itself
  (defaults to a name derived from `:file`, so two databases opened
  against different files don't collide).

  `:dets`'s own limits apply -- single Erlang node, roughly 2 GB per
  table, and no coordination for concurrent writers beyond what `:dets`
  itself serializes internally. This is "an embedded database that
  persists across restarts," not a substitute for a real multi-writer
  datastore. Writes are only guaranteed durable after `sync/1` (`:dets`
  itself flushes periodically, but not before every single insert).
  """

  @behaviour Episteme.Database.Backend

  @impl true
  def init(opts) do
    file = opts[:file] || raise ArgumentError, "Backends.Dets requires a :file option"
    table = Keyword.get_lazy(opts, :table, fn -> table_name(file) end)
    {:ok, table} = :dets.open_file(table, file: to_charlist(file), type: :set)
    table
  end

  defp table_name(file), do: :"episteme_database_#{:erlang.phash2(file)}"

  @impl true
  def clauses_for(table, name, arity) do
    case :dets.lookup(table, {name, arity}) do
      [{_key, clauses}] -> clauses
      [] -> []
    end
  end

  @impl true
  def replace_clauses(table, name, arity, clauses) do
    :ok = :dets.insert(table, {{name, arity}, clauses})
    :ok
  end

  @impl true
  def defined?(table, name, arity), do: :dets.member(table, {name, arity})

  @impl true
  def sync(table), do: :dets.sync(table)

  @impl true
  def close(table), do: :dets.close(table)
end
