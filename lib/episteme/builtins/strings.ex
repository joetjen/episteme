defmodule Episteme.Builtins.Strings do
  @moduledoc """
  The atom/number/string conversion family: `atom_codes/2 atom_chars/2
  atom_length/2 atom_concat/3 char_code/2 number_codes/2
  number_chars/2 upcase_atom/2 downcase_atom/2 atomic_list_concat/2,3`
  (classic ISO/de-facto predicates, working over atoms) plus
  `atom_string/2 string_to_atom/2 string_concat/3 string_chars/2
  string_codes/2 string_length/2 number_string/2 split_string/4`
  (SWI-style predicates producing/consuming real strings), all built
  on the shared
  `atomic_text/1`/`require_atomic_text/2` "coerce an atomic term (atom,
  number, or real string) to its text" primitive. `string/1`'s own type
  check lives in `Episteme.Engine` directly, alongside every other type
  check (`atom/1`, `var/1`, ...), not here.

  `atom_codes/2`/`number_codes/2`/`string_codes/2` produce plain Elixir
  charlists (`String.to_charlist/1`), which already *are* Episteme code
  lists -- no wrapping needed, same as everywhere else a Prolog list is
  just a native Elixir list. `atom_chars/2`/`number_chars/2` instead
  produce single-character *atoms* (classic ISO `char_list` semantics),
  while `string_chars/2` produces single-character *strings* -- the two
  are not interchangeable.
  """

  alias Episteme.Builtins.Exceptions
  alias Episteme.Term
  alias Episteme.Term.Var
  alias Ichor.Backtrack.{Bindings, Tree}

  @spec dispatch(atom(), non_neg_integer(), [term()]) :: Ichor.Backtrack.goal() | :not_handled
  def dispatch(:atom_codes, 2, [a, codes]), do: fn b -> atom_codes_goal(a, codes, b) end
  def dispatch(:atom_chars, 2, [a, chars]), do: fn b -> atom_chars_goal(a, chars, b) end
  def dispatch(:atom_length, 2, [a, len]), do: fn b -> atom_length_goal(a, len, b) end
  def dispatch(:atom_concat, 3, [a1, a2, a3]), do: fn b -> atom_concat_goal(a1, a2, a3, b) end

  def dispatch(:sub_atom, 5, [a, before, len, after_, sub]),
    do: fn b -> sub_atom_goal(a, before, len, after_, sub, b) end

  def dispatch(:char_code, 2, [ch, code]), do: fn b -> char_code_goal(ch, code, b) end
  def dispatch(:number_codes, 2, [n, codes]), do: fn b -> number_codes_goal(n, codes, b) end
  def dispatch(:number_chars, 2, [n, chars]), do: fn b -> number_chars_goal(n, chars, b) end
  def dispatch(:upcase_atom, 2, [a, u]), do: fn b -> upcase_atom_goal(a, u, b) end
  def dispatch(:downcase_atom, 2, [a, d]), do: fn b -> downcase_atom_goal(a, d, b) end

  def dispatch(:atomic_list_concat, 2, [list, a]),
    do: fn b -> atomic_list_concat2_goal(list, a, b) end

  def dispatch(:atomic_list_concat, 3, [list, sep, a]),
    do: fn b -> atomic_list_concat3_goal(list, sep, a, b) end

  def dispatch(:atom_string, 2, [a, s]), do: fn b -> atom_string_goal(a, s, b) end
  def dispatch(:string_to_atom, 2, [s, a]), do: fn b -> string_to_atom_goal(s, a, b) end
  def dispatch(:string_concat, 3, [s1, s2, s3]), do: fn b -> string_concat_goal(s1, s2, s3, b) end
  def dispatch(:string_chars, 2, [s, chars]), do: fn b -> string_chars_goal(s, chars, b) end
  def dispatch(:string_codes, 2, [s, codes]), do: fn b -> string_codes_goal(s, codes, b) end
  def dispatch(:string_length, 2, [s, len]), do: fn b -> string_length_goal(s, len, b) end
  def dispatch(:number_string, 2, [n, s]), do: fn b -> number_string_goal(n, s, b) end

  def dispatch(:split_string, 4, [s, sep, pad, result]),
    do: fn b -> split_string_goal(s, sep, pad, result, b) end

  def dispatch(_, _, _), do: :not_handled

  @doc """
  `Atomic`'s text, if it's an atom, a number, or a real string --
  `:error` for anything else (a compound, a list, or an unbound
  variable -- callers needing an `instantiation_error` specifically
  should check for `%Var{}` themselves before calling this, same as
  `require_atomic_text/2` does).
  """
  @spec atomic_text(term()) :: {:ok, String.t()} | :error
  def atomic_text([]), do: {:ok, "[]"}
  def atomic_text(a) when is_atom(a), do: {:ok, Atom.to_string(a)}
  def atomic_text(s) when is_binary(s), do: {:ok, s}
  def atomic_text(n) when is_number(n), do: {:ok, to_string(n)}
  def atomic_text(_), do: :error

  @doc "Resolves `term` and returns its text, raising `instantiation_error`/`type_error(atomic, _)` as appropriate -- the shared entry point every predicate here uses to read a bound atomic argument."
  @spec require_atomic_text(term(), Bindings.t()) :: String.t()
  def require_atomic_text(term, bindings) do
    case Bindings.resolve(Term, bindings, term) do
      %Var{} ->
        Exceptions.prolog_throw(Exceptions.instantiation_error())

      resolved ->
        case atomic_text(resolved) do
          {:ok, text} -> text
          :error -> Exceptions.prolog_throw(Exceptions.type_error(:atomic, resolved))
        end
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  # This whole module's job is building Prolog atoms out of
  # caller-supplied text (splitting/concatenating/case-converting
  # atoms, parsing codes/chars lists, ...) -- the BEAM atom table isn't
  # garbage collected, so this carries the same atom-table-exhaustion
  # risk as the reader itself (raw BEAM atoms are fine for a library
  # embedded in trusted programs, v0.1-v0.5; revisit before any
  # untrusted-input use case). Routing
  # every `String.to_atom/1` call in this module through here, instead
  # of each of the dozen call sites calling it directly, keeps that
  # justification in one place instead of a skip comment repeated a
  # dozen times over.
  @spec to_prolog_atom(String.t()) :: atom()
  defp to_prolog_atom(text), do: String.to_atom(text)

  @doc "Like `require_atomic_text/2`, but fails (instead of raising `type_error`) for an unbound variable -- callers that already have their own instantiation-error handling, or that want a plain proper-list-of-elements shape check first."
  @spec unify_goal(term(), term(), Bindings.t()) :: Ichor.Backtrack.Tree.t()
  def unify_goal(a, b, bindings) do
    case Bindings.unify(Term, bindings, a, b) do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  defp atom_codes_goal(atom_arg, codes_arg, bindings) do
    case Bindings.resolve(Term, bindings, atom_arg) do
      %Var{} ->
        text = codes_to_text(codes_arg, bindings)
        unify_goal(atom_arg, to_prolog_atom(text), bindings)

      _bound ->
        text = require_atomic_text(atom_arg, bindings)
        unify_goal(codes_arg, String.to_charlist(text), bindings)
    end
  end

  defp atom_chars_goal(atom_arg, chars_arg, bindings) do
    case Bindings.resolve(Term, bindings, atom_arg) do
      %Var{} ->
        text = chars_to_text(chars_arg, bindings)
        unify_goal(atom_arg, to_prolog_atom(text), bindings)

      _bound ->
        text = require_atomic_text(atom_arg, bindings)
        unify_goal(chars_arg, text_to_char_atoms(text), bindings)
    end
  end

  defp atom_length_goal(atom_arg, len_arg, bindings) do
    text = require_atomic_text(atom_arg, bindings)
    unify_goal(len_arg, String.length(text), bindings)
  end

  # `atom_concat(A1, A2, A3)`: with `A3` bound, enumerates every split of
  # its text into a prefix/suffix pair on backtracking (unification then
  # naturally narrows this to the one split matching whatever `A1`/`A2`
  # already are, if anything) -- the same "generate every split, let
  # unify filter it" shape `Episteme.Builtins.Lists`' own `append/3`
  # uses over lists. With `A3` unbound, `A1`/`A2` must both already be
  # bound (no infinite enumeration).
  defp atom_concat_goal(a1, a2, a3, bindings) do
    case Bindings.resolve(Term, bindings, a3) do
      %Var{} ->
        t1 = require_atomic_text(a1, bindings)
        t2 = require_atomic_text(a2, bindings)
        unify_goal(a3, to_prolog_atom(t1 <> t2), bindings)

      _bound ->
        text = require_atomic_text(a3, bindings)
        atom_concat_splits(text, a1, a2, bindings)
    end
  end

  defp atom_concat_splits(text, a1, a2, bindings) do
    0..String.length(text)
    |> Enum.map(&String.split_at(text, &1))
    |> Enum.reduce(Tree.fail(), fn {front, back}, acc ->
      Tree.disjunction(acc, fn b -> atom_concat_pair(a1, front, a2, back, b) end)
    end)
    |> then(& &1.(bindings))
  end

  defp atom_concat_pair(a1, front, a2, back, bindings) do
    unify_pairs([{a1, to_prolog_atom(front)}, {a2, to_prolog_atom(back)}], bindings)
  end

  @doc "Unifies every `{term, value}` pair against `bindings` in order, failing outright the moment one doesn't -- the shared \"generate one candidate, let unify filter it\" tail every enumerating predicate here (`atom_concat/3`, `string_concat/3`, `sub_atom/5`) ends in."
  @spec unify_pairs([{term(), term()}], Bindings.t()) :: Ichor.Backtrack.Tree.t()
  def unify_pairs(pairs, bindings) do
    Enum.reduce_while(pairs, {:ok, bindings}, fn {term, value}, {:ok, acc} ->
      case Bindings.unify(Term, acc, term, value) do
        {:ok, extended} -> {:cont, {:ok, extended}}
        :fail -> {:halt, :fail}
      end
    end)
    |> case do
      {:ok, extended} -> Tree.unit().(extended)
      :fail -> Tree.fail().(bindings)
    end
  end

  # `sub_atom(Atom, Before, Length, After, Sub)`: enumerates every
  # (`Before`, `Length`, `After`, `Sub`) decomposition of `Atom`'s text
  # on backtracking (`Before` outer, `Length` inner, both ascending) --
  # the same "generate every candidate, let unify filter it" shape
  # `atom_concat/3` above already uses, so a caller with any of the
  # four already bound gets it "for free" via unification narrowing
  # rather than a separate optimized code path. `Sub` is always an atom
  # (real ISO `sub_atom/5` semantics), even when `Atom` was a string.
  defp sub_atom_goal(atom_arg, before_arg, len_arg, after_arg, sub_arg, bindings) do
    text = require_atomic_text(atom_arg, bindings)
    graphemes = String.graphemes(text)
    total = length(graphemes)

    for(before <- 0..total, len <- 0..(total - before), do: {before, len})
    |> Enum.reduce(Tree.fail(), fn {before, len}, acc ->
      Tree.disjunction(
        acc,
        sub_atom_candidate(graphemes, total, before, len, before_arg, len_arg, after_arg, sub_arg)
      )
    end)
    |> then(& &1.(bindings))
  end

  defp sub_atom_candidate(graphemes, total, before, len, before_arg, len_arg, after_arg, sub_arg) do
    sub_text = graphemes |> Enum.slice(before, len) |> Enum.join()
    after_ = total - before - len

    fn bindings ->
      unify_pairs(
        [
          {before_arg, before},
          {len_arg, len},
          {after_arg, after_},
          {sub_arg, to_prolog_atom(sub_text)}
        ],
        bindings
      )
    end
  end

  defp char_code_goal(char_arg, code_arg, bindings) do
    case Bindings.resolve(Term, bindings, char_arg) do
      %Var{} ->
        case Bindings.resolve(Term, bindings, code_arg) do
          %Var{} -> Exceptions.prolog_throw(Exceptions.instantiation_error())
          code when is_integer(code) -> unify_goal(char_arg, code_to_char!(code), bindings)
          other -> Exceptions.prolog_throw(Exceptions.type_error(:integer, other))
        end

      atom when is_atom(atom) ->
        unify_goal(code_arg, char_to_code!(atom), bindings)

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:character, other))
    end
  end

  defp code_to_char!(code), do: <<code::utf8>> |> to_prolog_atom()

  defp char_to_code!(atom) do
    case Atom.to_string(atom) do
      <<code::utf8>> -> code
      _not_one_char -> Exceptions.prolog_throw(Exceptions.type_error(:character, atom))
    end
  end

  defp number_codes_goal(num_arg, codes_arg, bindings) do
    case Bindings.resolve(Term, bindings, num_arg) do
      %Var{} ->
        text = codes_to_text(codes_arg, bindings)
        unify_goal(num_arg, parse_number!(text), bindings)

      n when is_number(n) ->
        unify_goal(codes_arg, String.to_charlist(to_string(n)), bindings)

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:number, other))
    end
  end

  defp number_chars_goal(num_arg, chars_arg, bindings) do
    case Bindings.resolve(Term, bindings, num_arg) do
      %Var{} ->
        text = chars_to_text(chars_arg, bindings)
        unify_goal(num_arg, parse_number!(text), bindings)

      n when is_number(n) ->
        unify_goal(chars_arg, text_to_char_atoms(to_string(n)), bindings)

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:number, other))
    end
  end

  defp parse_number!(text) do
    case Integer.parse(text) do
      {n, ""} ->
        n

      _not_an_integer ->
        case Float.parse(text) do
          {n, ""} -> n
          _not_a_number -> Exceptions.prolog_throw(Exceptions.type_error(:number, text))
        end
    end
  end

  defp upcase_atom_goal(atom_arg, upper_arg, bindings) do
    text = require_atomic_text(atom_arg, bindings)
    unify_goal(upper_arg, to_prolog_atom(String.upcase(text)), bindings)
  end

  defp downcase_atom_goal(atom_arg, lower_arg, bindings) do
    text = require_atomic_text(atom_arg, bindings)
    unify_goal(lower_arg, to_prolog_atom(String.downcase(text)), bindings)
  end

  # `atomic_list_concat(List, Atom)`: concatenation only -- no splitting
  # mode without a separator to split on (that's what the /3 form is
  # for), so `List` must already be a proper, fully-bound list.
  defp atomic_list_concat2_goal(list_arg, atom_arg, bindings) do
    case proper_list_elements(list_arg, bindings) do
      {:ok, elements} ->
        text = Enum.map_join(elements, &require_atomic_text(&1, bindings))
        unify_goal(atom_arg, to_prolog_atom(text), bindings)

      :error ->
        Exceptions.prolog_throw(Exceptions.instantiation_error())
    end
  end

  # `atomic_list_concat(List, Sep, Atom)`: with `List` bound, joins its
  # elements' text with `Sep`'s text (concatenation mode, same as /2 but
  # with a separator). With `List` unbound (or not yet a proper list)
  # and `Atom` bound, splits `Atom`'s text on `Sep` instead -- unlike
  # `atom_concat/3`'s own split mode, this one is deterministic (a single
  # split point sequence, not every possible one), matching real
  # Prolog's own atomic_list_concat/3.
  defp atomic_list_concat3_goal(list_arg, sep_arg, atom_arg, bindings) do
    sep_text = require_atomic_text(sep_arg, bindings)

    case proper_list_elements(list_arg, bindings) do
      {:ok, elements} ->
        text = Enum.map_join(elements, sep_text, &require_atomic_text(&1, bindings))
        unify_goal(atom_arg, to_prolog_atom(text), bindings)

      :error ->
        atomic_list_concat3_split(list_arg, sep_text, atom_arg, bindings)
    end
  end

  defp atomic_list_concat3_split(_list_arg, "", _atom_arg, _bindings) do
    Exceptions.prolog_throw(Exceptions.domain_error(:non_empty_atom, ""))
  end

  defp atomic_list_concat3_split(list_arg, sep_text, atom_arg, bindings) do
    text = require_atomic_text(atom_arg, bindings)
    parts = String.split(text, sep_text) |> Enum.map(&to_prolog_atom/1)
    unify_goal(list_arg, parts, bindings)
  end

  defp proper_list_elements(list_arg, bindings) do
    case Bindings.resolve(Term, bindings, list_arg) do
      [] ->
        {:ok, []}

      [h | t] ->
        case proper_list_elements(t, bindings) do
          {:ok, rest} -> {:ok, [h | rest]}
          :error -> :error
        end

      _not_a_proper_list_or_var ->
        :error
    end
  end

  defp codes_to_text(codes_arg, bindings) do
    case Bindings.resolve(Term, bindings, codes_arg) do
      %Var{} -> Exceptions.prolog_throw(Exceptions.instantiation_error())
      resolved -> resolved |> Term.resolve_deep(bindings) |> codes_list_to_text!()
    end
  end

  defp codes_list_to_text!(list) when is_list(list) do
    if Enum.all?(list, &is_integer/1) do
      List.to_string(list)
    else
      Exceptions.prolog_throw(Exceptions.type_error(:integer, list))
    end
  end

  defp codes_list_to_text!(other),
    do: Exceptions.prolog_throw(Exceptions.type_error(:list, other))

  defp chars_to_text(chars_arg, bindings) do
    case Bindings.resolve(Term, bindings, chars_arg) do
      %Var{} -> Exceptions.prolog_throw(Exceptions.instantiation_error())
      resolved -> resolved |> Term.resolve_deep(bindings) |> chars_list_to_text!()
    end
  end

  defp chars_list_to_text!(list) when is_list(list) do
    if Enum.all?(list, &single_char_atom?/1) do
      Enum.map_join(list, &Atom.to_string/1)
    else
      Exceptions.prolog_throw(Exceptions.type_error(:character, list))
    end
  end

  defp chars_list_to_text!(other),
    do: Exceptions.prolog_throw(Exceptions.type_error(:list, other))

  defp single_char_atom?(a) when is_atom(a) do
    case Atom.to_string(a) do
      <<_::utf8>> -> true
      _not_one_char -> false
    end
  end

  defp single_char_atom?(_), do: false

  defp text_to_char_atoms(text), do: text |> String.graphemes() |> Enum.map(&to_prolog_atom/1)

  # ---- string_* family (real strings) -----------

  defp atom_string_goal(atom_arg, string_arg, bindings) do
    case Bindings.resolve(Term, bindings, atom_arg) do
      %Var{} ->
        text = require_atomic_text(string_arg, bindings)
        unify_goal(atom_arg, to_prolog_atom(text), bindings)

      _bound ->
        text = require_atomic_text(atom_arg, bindings)
        unify_goal(string_arg, text, bindings)
    end
  end

  defp string_to_atom_goal(string_arg, atom_arg, bindings) do
    case Bindings.resolve(Term, bindings, string_arg) do
      %Var{} ->
        text = require_atomic_text(atom_arg, bindings)
        unify_goal(string_arg, text, bindings)

      _bound ->
        text = require_atomic_text(string_arg, bindings)
        unify_goal(atom_arg, to_prolog_atom(text), bindings)
    end
  end

  # Same "enumerate every split of the bound side, let unify filter it"
  # shape as `atom_concat_goal/4` above, just producing string results
  # instead of atom ones.
  defp string_concat_goal(s1, s2, s3, bindings) do
    case Bindings.resolve(Term, bindings, s3) do
      %Var{} ->
        t1 = require_atomic_text(s1, bindings)
        t2 = require_atomic_text(s2, bindings)
        unify_goal(s3, t1 <> t2, bindings)

      _bound ->
        text = require_atomic_text(s3, bindings)
        string_concat_splits(text, s1, s2, bindings)
    end
  end

  defp string_concat_splits(text, s1, s2, bindings) do
    0..String.length(text)
    |> Enum.map(&String.split_at(text, &1))
    |> Enum.reduce(Tree.fail(), fn {front, back}, acc ->
      Tree.disjunction(acc, fn b -> string_concat_pair(s1, front, s2, back, b) end)
    end)
    |> then(& &1.(bindings))
  end

  defp string_concat_pair(s1, front, s2, back, bindings) do
    unify_pairs([{s1, front}, {s2, back}], bindings)
  end

  defp string_chars_goal(string_arg, chars_arg, bindings) do
    case Bindings.resolve(Term, bindings, string_arg) do
      %Var{} ->
        text = string_chars_to_text(chars_arg, bindings)
        unify_goal(string_arg, text, bindings)

      _bound ->
        text = require_atomic_text(string_arg, bindings)
        unify_goal(chars_arg, String.graphemes(text), bindings)
    end
  end

  defp string_chars_to_text(chars_arg, bindings) do
    case Bindings.resolve(Term, bindings, chars_arg) do
      %Var{} -> Exceptions.prolog_throw(Exceptions.instantiation_error())
      resolved -> resolved |> Term.resolve_deep(bindings) |> string_chars_list_to_text!()
    end
  end

  defp string_chars_list_to_text!(list) when is_list(list) do
    if Enum.all?(list, &single_char_string?/1) do
      Enum.join(list)
    else
      Exceptions.prolog_throw(Exceptions.type_error(:character, list))
    end
  end

  defp string_chars_list_to_text!(other),
    do: Exceptions.prolog_throw(Exceptions.type_error(:list, other))

  defp single_char_string?(s) when is_binary(s), do: String.length(s) == 1
  defp single_char_string?(_), do: false

  defp string_codes_goal(string_arg, codes_arg, bindings) do
    case Bindings.resolve(Term, bindings, string_arg) do
      %Var{} ->
        text = codes_to_text(codes_arg, bindings)
        unify_goal(string_arg, text, bindings)

      _bound ->
        text = require_atomic_text(string_arg, bindings)
        unify_goal(codes_arg, String.to_charlist(text), bindings)
    end
  end

  defp string_length_goal(string_arg, len_arg, bindings) do
    text = require_atomic_text(string_arg, bindings)
    unify_goal(len_arg, String.length(text), bindings)
  end

  defp number_string_goal(num_arg, string_arg, bindings) do
    case Bindings.resolve(Term, bindings, num_arg) do
      %Var{} ->
        text = require_atomic_text(string_arg, bindings)
        unify_goal(num_arg, parse_number!(text), bindings)

      n when is_number(n) ->
        unify_goal(string_arg, to_string(n), bindings)

      other ->
        Exceptions.prolog_throw(Exceptions.type_error(:number, other))
    end
  end

  # `split_string(String, SepChars, PadChars, SubStrings)` (SWI): splits
  # `String` on every occurrence of any character in `SepChars` (no
  # splitting at all, the whole string as one field, when `SepChars` is
  # `""`), then strips any run of characters found in `PadChars` from
  # both ends of each resulting field. Always produces real strings,
  # regardless of what `String` itself was.
  defp split_string_goal(string_arg, sep_arg, pad_arg, result_arg, bindings) do
    text = require_atomic_text(string_arg, bindings)
    sep_chars = require_atomic_text(sep_arg, bindings) |> String.graphemes() |> MapSet.new()
    pad_chars = require_atomic_text(pad_arg, bindings) |> String.graphemes() |> MapSet.new()

    fields = if MapSet.size(sep_chars) == 0, do: [text], else: split_on_any(text, sep_chars)
    trimmed = Enum.map(fields, &trim_chars(&1, pad_chars))
    unify_goal(result_arg, trimmed, bindings)
  end

  defp split_on_any(text, sep_chars) do
    text
    |> String.graphemes()
    |> Enum.chunk_while(
      [],
      fn ch, acc ->
        if MapSet.member?(sep_chars, ch),
          do: {:cont, chunk_to_text(acc), []},
          else: {:cont, [ch | acc]}
      end,
      fn acc -> {:cont, chunk_to_text(acc), []} end
    )
  end

  defp chunk_to_text(reversed_chars), do: reversed_chars |> Enum.reverse() |> Enum.join()

  defp trim_chars(text, pad_chars) do
    text
    |> String.graphemes()
    |> Enum.drop_while(&MapSet.member?(pad_chars, &1))
    |> Enum.reverse()
    |> Enum.drop_while(&MapSet.member?(pad_chars, &1))
    |> Enum.reverse()
    |> Enum.join()
  end
end
