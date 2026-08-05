defmodule Episteme.Builtins.Io do
  @moduledoc """
  Minimal I/O: `write/1 writeln/1 print/1 nl/0` -- canonical
  `functor(args)` text via `Episteme.Term.to_text/1` (no operator-aware
  pretty-printing yet) -- plus `format/1,2`, a directive-based
  formatter over the same `to_text/1` rendering. Each succeeds exactly
  once, side effect aside.

  `format/2`'s own directive set is deliberately a practical subset,
  not ISO/SWI's full one -- no column/radix directives (`~t`, `~|`,
  `~Nr`, ...), no numeric-prefixed `~Nd` (SWI's "insert a decimal point
  N digits from the right"). `~w`/`~p`/`~q` are all the same thing here
  (`to_text/1`), since there's no operator-aware or quoted writer to
  tell them apart with yet -- see `write/1`'s own note above.
  """

  alias Episteme.Builtins.{Exceptions, Strings}
  alias Episteme.Term
  alias Episteme.Term.Var
  alias Ichor.Backtrack.{Bindings, Tree}

  @spec dispatch(atom(), non_neg_integer(), [term()]) :: Ichor.Backtrack.goal() | :not_handled
  def dispatch(:write, 1, [t]), do: fn b -> print_term(t, b, "") end
  def dispatch(:writeln, 1, [t]), do: fn b -> print_term(t, b, "\n") end
  def dispatch(:print, 1, [t]), do: fn b -> print_term(t, b, "") end
  def dispatch(:format, 1, [fmt]), do: fn b -> format_goal(fmt, [], b) end
  def dispatch(:format, 2, [fmt, args]), do: fn b -> format_goal(fmt, args, b) end

  def dispatch(:nl, 0, []),
    do: fn b ->
      IO.write("\n")
      Tree.unit().(b)
    end

  def dispatch(_, _, _), do: :not_handled

  defp print_term(t, bindings, suffix) do
    IO.write(Term.to_text(Term.resolve_deep(t, bindings)) <> suffix)
    Tree.unit().(bindings)
  end

  # `format(Format, Args)`: `Args` is normally a proper list, one
  # element consumed per directive in `Format`, left to right -- a
  # single non-list `Args` is treated as the one-element list
  # `[Args]`, matching SWI's own leniency (so `format("~w", foo)`
  # works without wrapping `foo` in a list yourself).
  defp format_goal(fmt_arg, args_arg, bindings) do
    fmt_text = Strings.require_atomic_text(fmt_arg, bindings)
    args = format_args(args_arg, bindings)
    IO.write(render_format(fmt_text, args))
    Tree.unit().(bindings)
  end

  defp format_args(args_arg, bindings) do
    case Bindings.resolve(Term, bindings, args_arg) do
      %Var{} -> Exceptions.prolog_throw(Exceptions.instantiation_error())
      list when is_list(list) -> Term.resolve_deep(list, bindings)
      other -> [Term.resolve_deep(other, bindings)]
    end
  end

  defp render_format(fmt_text, args) do
    {parts, _unused_args} = render_chars(String.graphemes(fmt_text), args, [])
    parts |> Enum.reverse() |> Enum.join()
  end

  defp render_chars([], args, acc), do: {acc, args}
  defp render_chars(["~", "~" | rest], args, acc), do: render_chars(rest, args, ["~" | acc])
  defp render_chars(["~", "n" | rest], args, acc), do: render_chars(rest, args, ["\n" | acc])

  defp render_chars(["~", d | rest], args, acc) when d in ["w", "p", "q"] do
    {value, remaining} = next_format_arg!(args)
    render_chars(rest, remaining, [Term.to_text(value) | acc])
  end

  defp render_chars(["~", "a" | rest], args, acc) do
    {value, remaining} = next_format_arg!(args)
    render_chars(rest, remaining, [require_atom_text!(value) | acc])
  end

  defp render_chars(["~", "d" | rest], args, acc) do
    {value, remaining} = next_format_arg!(args)
    render_chars(rest, remaining, [require_integer_text!(value) | acc])
  end

  defp render_chars(["~", "s" | rest], args, acc) do
    {value, remaining} = next_format_arg!(args)
    render_chars(rest, remaining, [require_codes_or_string_text!(value) | acc])
  end

  defp render_chars(["~", "i" | rest], args, acc) do
    {_skipped, remaining} = next_format_arg!(args)
    render_chars(rest, remaining, acc)
  end

  defp render_chars(["~", other | _rest], _args, _acc),
    do: Exceptions.prolog_throw(Exceptions.domain_error(:format_directive, other))

  defp render_chars([ch | rest], args, acc), do: render_chars(rest, args, [ch | acc])

  defp next_format_arg!([]),
    do: Exceptions.prolog_throw(Exceptions.domain_error(:format_arguments, []))

  defp next_format_arg!([h | t]), do: {h, t}

  defp require_atom_text!([]), do: "[]"
  defp require_atom_text!(value) when is_atom(value), do: Atom.to_string(value)
  defp require_atom_text!(value), do: Exceptions.prolog_throw(Exceptions.type_error(:atom, value))

  defp require_integer_text!(value) when is_integer(value), do: Integer.to_string(value)

  defp require_integer_text!(value),
    do: Exceptions.prolog_throw(Exceptions.type_error(:integer, value))

  defp require_codes_or_string_text!(value) when is_binary(value), do: value

  defp require_codes_or_string_text!(value) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      List.to_string(value)
    else
      Exceptions.prolog_throw(Exceptions.type_error(:list, value))
    end
  end

  defp require_codes_or_string_text!(value),
    do: Exceptions.prolog_throw(Exceptions.type_error(:list, value))
end
