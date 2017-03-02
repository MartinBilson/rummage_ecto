defmodule Rummage.Ecto.Hooks.Sort do
  @moduledoc """
  `Rummage.Ecto.Hooks.Sort` is the default sort hook that comes shipped
  with `Rummage`.

  Usage:
  For a regular sort:

  ```elixir
  alias Rummage.Ecto.Hooks.Sort

  # This returns a queryable which upon running will give a list of `Parent`(s)
  # sorted by ascending field_1
  sorted_queryable = Sort.run(Parent, %{"sort" => {[], "field_1.asc"}})
  ```

  For a case-insensitive sort:

  ```elixir
  alias Rummage.Ecto.Hooks.Sort

  # This returns a queryable which upon running will give a list of `Parent`(s)
  # sorted by ascending case insensitive field_1
  # Keep in mind that case insensitive can only be called for text fields
  sorted_queryable = Sort.run(Parent, %{"sort" => {[], "field_1.asc.ci"}})
  ```


  This module can be overridden with a custom module while using `Rummage.Ecto`
  in `Ecto` struct module.
  """

  import Ecto.Query

  @behaviour Rummage.Ecto.Hook

  @doc """
  Builds a sort queryable on top of the given `queryable` from the rummage parameters
  from the given `rummage` struct.

  ## Examples
  When rummage struct passed doesn't have the key "sort", it simply returns the
  queryable itself:

      iex> alias Rummage.Ecto.Hooks.Sort
      iex> import Ecto.Query
      iex> Sort.run(Parent, %{})
      Parent

  When the queryable passed is not just a struct:

      iex> alias Rummage.Ecto.Hooks.Sort
      iex> import Ecto.Query
      iex> queryable = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex>  Sort.run(queryable, %{})
      #Ecto.Query<from p in "parents">

  When rummage struct passed has the key "sort", but empty associations array
  it just orders it by the passed queryableable:

      iex> alias Rummage.Ecto.Hooks.Sort
      iex> import Ecto.Query
      iex> rummage = %{"sort" => {[], "field_1.asc"}}
      %{"sort" => {[],
        "field_1.asc"}}
      iex> queryable = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex> Sort.run(queryable, rummage)
      #Ecto.Query<from p in "parents", order_by: [asc: p.field_1]>

  When rummage struct passed has the key "sort", with "field" and "order"
  it returns a sorted version of the queryable passed in as the argument:

      iex> alias Rummage.Ecto.Hooks.Sort
      iex> import Ecto.Query
      iex> rummage = %{"sort" => {["parent", "parent"], "field_1.asc"}}
      %{"sort" => {["parent", "parent"], "field_1.asc"}}
      iex> queryable = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex> Sort.run(queryable, rummage)
      #Ecto.Query<from p0 in "parents", join: p1 in assoc(p0, :parent), join: p2 in assoc(p1, :parent), order_by: [asc: p2.field_1]>

  # When rummage struct passed has case-insensitive sort, it returns
  # a sorted version of the queryable with case_insensitive arguments:

      iex> alias Rummage.Ecto.Hooks.Sort
      iex> import Ecto.Query
      iex> rummage = %{"sort" => {["parent", "parent"], "field_1.asc.ci"}}
      %{"sort" => {["parent", "parent"], "field_1.asc.ci"}}
      iex> queryable = from u in "parents"
      #Ecto.Query<from p in "parents">
      iex> Sort.run(queryable, rummage)
      #Ecto.Query<from p0 in "parents", join: p1 in assoc(p0, :parent), join: p2 in assoc(p1, :parent), order_by: [asc: fragment("lower(?)", p2.field_1)]>
  """
  @spec run(Ecto.Query.t, map) :: {Ecto.Query.t, map}
  def run(queryable, rummage) do
    case Map.get(rummage, "sort") do
      a when a in [nil, {}, ""] -> queryable
      sort_params ->
        case Regex.match?(~r/\w.ci+$/, elem(sort_params, 1)) do
          true ->
            order_param = elem(sort_params, 1)
              |> String.split(".")
              |> Enum.drop(-1)
              |> Enum.join(".")

            sort_params = {elem(sort_params, 0), order_param}

            handle_sort(queryable, sort_params, true)
          _ -> handle_sort(queryable, sort_params)
        end
    end
  end

  defp handle_sort(queryable, sort_params, ci \\ false) do
    order_param = sort_params
      |> elem(1)

    association_names = sort_params
      |> elem(0)

    association_names
    |> Enum.reduce(queryable, &join_by_association(&1, &2))
    |> handle_ordering(order_param, ci)
  end

  defmacrop case_insensitive(field) do
    quote do
      fragment("lower(?)", unquote(field))
    end
  end

  defp handle_ordering(queryable, order_param, ci) do
    case Regex.match?(~r/\w.asc+$/, order_param)
      or Regex.match?(~r/\w.desc+$/, order_param) do
      true ->
        parsed_field = order_param
          |> String.split(".")
          |> Enum.drop(-1)
          |> Enum.join(".")

        order_type = order_param
          |> String.split(".")
          |> Enum.at(-1)

        queryable |> order_by_assoc(order_type, parsed_field, ci)
       _ -> queryable
    end
  end

  defp join_by_association(association, queryable) do
    join(queryable, :inner, [..., p1], p2 in assoc(p1, ^String.to_atom(association)))
  end

  defp order_by_assoc(queryable, order_type, parsed_field, false) do
    order_by(queryable, [p0, ..., p2], [{^String.to_atom(order_type), field(p2, ^String.to_atom(parsed_field))}])
  end

  defp order_by_assoc(queryable, order_type, parsed_field, true) do
    order_by(queryable, [p0, ..., p2], [{^String.to_atom(order_type), case_insensitive(field(p2, ^String.to_atom(parsed_field)))}])
  end
end
