defmodule Episteme.Term do
  @moduledoc """
  Episteme's term representation: atoms and numbers are plain Elixir
  atoms/integers/floats, a real Prolog string (see `string_type_decision`,
  DESIGN.md) is a plain Elixir binary -- a genuinely new atomic term
  class, not a list of codes, but still no dedicated struct, the same
  "raw host-language value" pattern atoms/integers/floats already use --
  lists are native Elixir lists, variables and compounds get dedicated
  structs. This module is the
  `Ichor.Backtrack.Term` implementation passed explicitly to every
  `Ichor.Backtrack.Bindings` call, plus the handful of whole-term
  operations (deep resolve, rename-apart) built on
  `Ichor.Toolkit.TermWalk` that unification itself doesn't need but the
  engine does.
  """

  alias Ichor.Backtrack.Bindings
  alias Ichor.Toolkit.TermWalk

  defmodule Var do
    @moduledoc "A logic variable: `ref` is its identity, `name` is display-only."
    @enforce_keys [:ref]
    defstruct [:ref, name: "_"]
    @type t :: %__MODULE__{ref: reference(), name: String.t()}
  end

  defmodule Compound do
    @moduledoc "A compound term `name(args...)`."
    @enforce_keys [:name, :args]
    defstruct [:name, :args]
    @type t :: %__MODULE__{name: atom(), args: [term()]}
  end

  @behaviour Ichor.Backtrack.Term

  @impl true
  def variable?(%Var{}), do: true
  def variable?(_), do: false

  @impl true
  def var_id(%Var{ref: ref}), do: ref

  @impl true
  def compound?(%Compound{}), do: true
  def compound?([_ | _]), do: true
  def compound?(_), do: false

  @doc """
  A non-empty native Elixir list decomposes as ISO's own `'.'/2` cons
  functor (`[H|T]` <-> `'.'(H, T)`) -- the encoding that lets
  `Ichor.Backtrack.Bindings.unify/4` recurse into list structure at all
  (without this, `[H|T]` vs `[1,2,3]` would only ever compare via plain
  `==/2`, never binding `H`/`T`). `[]` is the atomic empty-list atom,
  same as real Prolog -- not a `'.'/2` cell, so it stays out of
  `compound?/1` above.
  """
  @impl true
  def deconstruct(%Compound{name: name, args: args}), do: {name, args}
  def deconstruct([h | t]), do: {:., [h, t]}

  @impl true
  def reconstruct(:., [h, t]), do: [h | t]
  def reconstruct(name, args), do: %Compound{name: name, args: args}

  @doc "A fresh variable, optionally named for display."
  @spec new_var(String.t()) :: Var.t()
  def new_var(name \\ "_"), do: %Var{ref: make_ref(), name: name}

  @doc """
  Fully dereferences `term` and every subterm reachable through it under
  `bindings` -- unlike `Ichor.Backtrack.Bindings.resolve/3`, which only
  chases the outermost variable one level deep, this also resolves
  inside compound-term arguments (and, since `rewrite/3` re-examines a
  freshly resolved variable's own value, transitively through however
  many bindings a chain passes through).
  """
  @spec resolve_deep(term(), Bindings.t()) :: term()
  def resolve_deep(term, bindings) do
    TermWalk.rewrite(__MODULE__, term, &Bindings.resolve(__MODULE__, bindings, &1))
  end

  @doc """
  Renames every distinct variable in `term` apart to a brand new one,
  preserving sharing (two occurrences of the same variable become two
  occurrences of the same fresh variable) -- the "discover names, build
  a fresh-ref map, rewrite" shape. Used both for `copy_term/2` and to
  instantiate a stored clause fresh on every call.
  """
  @spec fresh_copy(term()) :: term()
  def fresh_copy(term) do
    refs =
      TermWalk.fold(__MODULE__, term, %{}, fn
        %Var{ref: ref, name: name}, acc -> Map.put_new(acc, ref, new_var(name))
        _other, acc -> acc
      end)

    TermWalk.rewrite(__MODULE__, term, fn
      %Var{ref: ref} -> Map.fetch!(refs, ref)
      other -> other
    end)
  end

  @doc "Structural equality (`==/2`) on two already-resolved terms -- same shape, same variable identity, and (unlike plain Elixir `==`) an integer never equals a float."
  @spec structurally_equal?(term(), term()) :: boolean()
  def structurally_equal?(%Var{ref: a}, %Var{ref: b}), do: a == b
  def structurally_equal?(%Var{}, _), do: false
  def structurally_equal?(_, %Var{}), do: false

  def structurally_equal?(%Compound{name: n, args: a1}, %Compound{name: n, args: a2})
      when length(a1) == length(a2) do
    Enum.zip(a1, a2) |> Enum.all?(fn {x, y} -> structurally_equal?(x, y) end)
  end

  def structurally_equal?(%Compound{}, _), do: false
  def structurally_equal?(_, %Compound{}), do: false

  def structurally_equal?([], []), do: true

  def structurally_equal?([h1 | t1], [h2 | t2]),
    do: structurally_equal?(h1, h2) and structurally_equal?(t1, t2)

  def structurally_equal?([], _), do: false
  def structurally_equal?(_, []), do: false

  def structurally_equal?(a, b) when is_number(a) and is_number(b),
    do: a == b and is_float(a) == is_float(b)

  def structurally_equal?(a, b), do: a == b

  @doc """
  ISO's standard order of terms: `Var < Number < Atom < Compound`.
  Both arguments should already be resolved (see `resolve_deep/2`) --
  an unresolved variable bound to, say, a compound would otherwise
  sort as a variable instead of by what it's actually bound to.

  Within a class: variables order by reference identity (a total,
  consistent order within one run, not meaningful across runs, and not
  the same thing as *creation* order); numbers by value, with a float
  sorting before an integer of equal value (`1.0` before `1`); atoms
  alphabetically by character code (`[]`, the empty-list atom, sorts
  as if its name were the two characters `[` `]`, same as any other
  atom); strings (see `string_type_decision`, DESIGN.md) alphabetically
  by byte value, same comparator as atoms; compounds (a non-empty list
  decomposes via the same `'.'/2` cons functor `compound?/1` uses
  everywhere else) by arity first, then functor name alphabetically,
  then arguments left to right, recursively.

  Classes order `Var < Number < Atom < String < Compound` -- a real
  string is its own class, distinct from atoms, matching SWI-Prolog's
  own convention (ISO itself has no strings to place, since its own
  double-quoted syntax is just a code-list).
  """
  @spec compare_order(term(), term()) :: :lt | :eq | :gt
  def compare_order(a, b) do
    {class_a, class_b} = {term_class(a), term_class(b)}

    cond do
      class_a < class_b -> :lt
      class_a > class_b -> :gt
      true -> compare_within_class(class_a, a, b)
    end
  end

  defp term_class(%Var{}), do: 0
  defp term_class(n) when is_number(n), do: 1
  defp term_class([]), do: 2
  defp term_class(a) when is_atom(a), do: 2
  defp term_class(s) when is_binary(s), do: 3
  defp term_class(_compound_or_list), do: 4

  defp compare_within_class(0, %Var{ref: a}, %Var{ref: b}), do: compare_native(a, b)
  defp compare_within_class(1, a, b), do: compare_numbers(a, b)
  defp compare_within_class(2, a, b), do: compare_native(atom_sort_key(a), atom_sort_key(b))
  defp compare_within_class(3, a, b), do: compare_native(a, b)

  defp compare_within_class(4, a, b) do
    {name_a, args_a} = deconstruct(a)
    {name_b, args_b} = deconstruct(b)

    with :eq <- compare_native(length(args_a), length(args_b)),
         :eq <- compare_native(atom_sort_key(name_a), atom_sort_key(name_b)) do
      compare_arg_lists(args_a, args_b)
    end
  end

  defp compare_arg_lists([], []), do: :eq

  defp compare_arg_lists([h1 | t1], [h2 | t2]) do
    case compare_order(h1, h2) do
      :eq -> compare_arg_lists(t1, t2)
      other -> other
    end
  end

  defp atom_sort_key([]), do: "[]"
  defp atom_sort_key(a), do: Atom.to_string(a)

  defp compare_numbers(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      is_float(a) and is_integer(b) -> :lt
      is_integer(a) and is_float(b) -> :gt
      true -> :eq
    end
  end

  defp compare_native(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  @doc """
  Every distinct variable in `term`, in first-occurrence order (real
  Prolog's own `term_variables/2`, though not itself exposed as a
  callable goal yet) -- `Episteme.Engine`'s own building block for
  `bagof/3`/`setof/3`'s free-variable grouping: which of a `Goal`'s
  variables aren't mentioned in `Template` and aren't existentially
  quantified via `Var^Goal`.
  """
  @spec term_variables(term()) :: [Var.t()]
  def term_variables(term) do
    {vars, _seen} =
      TermWalk.fold(__MODULE__, term, {[], MapSet.new()}, fn
        %Var{ref: ref} = v, {vars, seen} ->
          if MapSet.member?(seen, ref),
            do: {vars, seen},
            else: {[v | vars], MapSet.put(seen, ref)}

        _other, acc ->
          acc
      end)

    Enum.reverse(vars)
  end

  @doc "Sorts `list` by `compare_order/2` -- the shared basis for `msort/2` and, deduped, `sort/2`/`setof/3`."
  @spec sort_by_order([term()]) :: [term()]
  def sort_by_order(list), do: Enum.sort(list, &(compare_order(&1, &2) != :gt))

  @doc """
  Like `sort_by_order/1`, but also drops every term that standard-order-
  compares `:eq` to its predecessor once sorted -- not plain Elixir
  `==`, which would wrongly conflate `1` and `1.0` (equal by `==`, but
  never `:eq` in standard order -- see `compare_order/2`'s own
  float-before-integer tie-break). Shared by `sort/2` and `setof/3`.
  """
  @spec sort_unique([term()]) :: [term()]
  def sort_unique(list), do: list |> sort_by_order() |> dedup_adjacent_by_order()

  defp dedup_adjacent_by_order([]), do: []
  defp dedup_adjacent_by_order([x]), do: [x]

  defp dedup_adjacent_by_order([a, b | rest]) do
    if compare_order(a, b) == :eq do
      dedup_adjacent_by_order([a | rest])
    else
      [a | dedup_adjacent_by_order([b | rest])]
    end
  end

  @doc "True iff `term` contains no unbound variable anywhere -- resolve deeply first (see `resolve_deep/2`) if `term` may still hold bindings."
  @spec ground?(term()) :: boolean()
  def ground?(%Var{}), do: false
  def ground?(%Compound{args: args}), do: Enum.all?(args, &ground?/1)
  def ground?([h | t]), do: ground?(h) and ground?(t)
  def ground?(_), do: true

  @doc "Canonical `functor(args)` text for an already fully-resolved term -- no operator-aware pretty-printing."
  @spec to_text(term()) :: String.t()
  def to_text(%Var{name: name}), do: name

  def to_text(%Compound{name: name, args: args}) do
    Atom.to_string(name) <> "(" <> Enum.map_join(args, ", ", &to_text/1) <> ")"
  end

  def to_text([]), do: "[]"

  def to_text(list) when is_list(list) do
    "[" <> to_text_list(list) <> "]"
  end

  def to_text(atom) when is_atom(atom), do: Atom.to_string(atom)
  def to_text(number) when is_number(number), do: to_string(number)
  def to_text(string) when is_binary(string), do: "\"" <> string <> "\""
  def to_text(other), do: inspect(other)

  defp to_text_list([h]), do: to_text(h)
  defp to_text_list([h | t]) when is_list(t), do: to_text(h) <> ", " <> to_text_list(t)
  defp to_text_list([h | t]), do: to_text(h) <> "|" <> to_text(t)
end
