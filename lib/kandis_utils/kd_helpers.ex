defmodule Kandis.KdHelpers do
  @moduledoc """
    generic helpers by Manfred Wuits
  """

  @doc """
  array_get helper taken from laravel
  """
  def array_get(data, keys, default \\ nil) do
    keys2 =
      case keys do
        key when is_binary(key) or is_atom(key) -> [key]
        keys when is_list(keys) -> keys
      end

    case get_in(data, keys2) do
      nil -> default
      result -> result
    end
  end

  defmacro pipe_when(left, condition, fun) do
    quote do
      left = unquote(left)

      if unquote(condition),
        do: left |> unquote(fun),
        else: left
    end
  end

  def if_empty(val, default_val) do
    if present?(val) do
      val
    else
      default_val
    end
  end

  def if_nil(val, default_val) do
    if is_nil(val) do
      default_val
    else
      val
    end
  end

  def struct_from_map(a_map, as: a_struct) do
    # Find the keys within the map
    keys =
      Map.keys(a_struct)
      |> Enum.filter(fn x -> x != :__struct__ end)

    # Process map, checking for both string / atom keys
    _processed_map =
      for key <- keys, into: %{} do
        value = Map.get(a_map, key) || Map.get(a_map, to_string(key))
        {key, value}
      end

    # a_struct = Map.merge(a_struct, processed_map)
    a_struct
  end

  def dec_to_str(nil) do
    dec_to_str("0")
  end

  def dec_to_str(string) when is_binary(string) do
    dec_to_str(Decimal.new(string))
  end

  def dec_to_str(decimal) do
    # fix_suffix = fn suf -> suf |> String.trim_trailing("0") end

    Decimal.set_context(%Decimal.Context{Decimal.get_context() | precision: 5})

    decimal
    |> Decimal.to_string(:normal)
    |> String.trim_trailing("0")
    |> (&(&1 <> "0")).()
  end

  def to_int(val) do
    case val do
      val when is_integer(val) ->
        val

      val when is_binary(val) ->
        Integer.parse(val)
        |> case do
          {val, ""} -> val
          _ -> nil
        end

      val when is_float(val) ->
        Kernel.round(val)

      %Decimal{} = val ->
        val |> Decimal.round() |> Decimal.to_integer()

      nil ->
        nil
    end
  end

  # only works with postres syntax now
  def print_sql(queryable, repo, msg \\ "print SQL: ", level \\ :warn) do
    log(
      Ecto.Adapters.SQL.to_sql(:all, repo, queryable)
      |> interpolate_sql(),
      msg,
      level
    )

    queryable
  end

  def interpolate_sql({sql, args}) do
    sql =
      Enum.map(args, fn val -> inspect(val) end)
      |> Enum.map(fn a -> String.replace(a, "\"", "'") end)
      |> Enum.with_index()
      |> Enum.reduce(sql, fn {val, idx}, sql -> String.replace(sql, "$#{idx + 1}", val) end)
      |> String.split("\n")
      |> Enum.join(" ")

    """

    #{sql};

    """
  end

  def present?(term) do
    !Blankable.blank?(term)
  end

  def empty?(term) do
    Blankable.blank?(term)
  end

  require Logger

  def log(data, msg \\ "", level \\ :debug) do
    Logger.log(
      level,
      msg <> " " <> inspect(data, printable_limit: :infinity, limit: 50, pretty: true)
    )

    data
  end

  def to_dec(""), do: nil
  def to_dec(nil), do: nil
  def to_dec(i) when is_integer(i), do: Decimal.new(i)
  def to_dec(%Decimal{} = v), do: v

  def to_dec(str) do
    case Decimal.parse(str) do
      :error -> str
      {:ok, dec} -> dec
      {dec, rest} when is_binary(rest) -> dec
      _ -> str
    end
  end

  def is_parsable_to_dec?(str) do
    case to_dec(str) do
      %Decimal{} = v -> true
      _ -> false
    end
  end

  def convert_keys(map, keys, converter_function)
      when is_list(keys) and is_map(map) and is_function(converter_function, 1) do
    Map.to_list(map)
    |> Enum.map(fn {key, val} ->
      if Enum.member?(keys, key) do
        {converter_function.(key), val}
      else
        {key, val}
      end
    end)
    |> Map.new()
  end

  def stringify_keys(map, _keys), do: map

  def drop_keys_by_type(map, type) when is_map(map) and is_atom(type) do
    map
    |> Map.drop(get_keys_by_type(map, type))
  end

  def drop_atom_keys(val, _type), do: val

  def get_keys_by_type(map, :atom), do: Map.keys(map) |> Enum.filter(&is_atom/1)
  def get_keys_by_type(map, :binary), do: Map.keys(map) |> Enum.filter(&is_binary/1)
  def get_keys_by_type(map, :integer), do: Map.keys(map) |> Enum.filter(&is_integer/1)
end
