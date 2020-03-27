defmodule Kandis.Cart do
  alias Kandis.VisitorSession
  alias EvablutWeb.Shop.LocalCart

  alias Kandis.LiveUpdates

  @local_cart Application.get_env(:kandis, :local_cart)

  @moduledoc "

  this module helps to handle a shopping-cart.

  cart-items get stored in a visitor-session

  "

  def get_cart_key(), do: "cart"

  def create_cart_item(sku, item_values, amount \\ 1)

  def create_cart_item(sku, item_values, amount)
      when (is_binary(sku) or is_integer(sku)) and is_map(item_values) and is_integer(amount) do
    Map.merge(item_values, %{
      amount: amount,
      sku:
        case sku do
          sku when is_binary(sku) -> String.trim(sku)
          _ -> sku
        end
    })
  end

  def create_cart_item(promocode, item_values, :promocode) when is_binary(promocode) do
    Map.merge(item_values, %{
      promocode: promocode,
      type: "promocode",
      amount: 1
    })
  end

  def create_cart_item(_, _, _), do: nil

  def get_empty_cart_record() do
    %{
      items: [],
      promocodes: []
    }
  end

  def store_cart_record_if_needed(%{items: _items} = cart_record, cart_or_sid) do
    if(is_sid?(cart_or_sid)) do
      VisitorSession.set_value(cart_or_sid, get_cart_key(), cart_record)
    end

    cart_record
  end

  def is_sid?(cart_or_sid) do
    case cart_or_sid do
      val when is_binary(val) -> true
      val when is_integer(val) -> true
      _ -> false
    end
  end

  def get_augmented_cart_record(sid, params) do
    get_cart_record(sid)
    |> @local_cart.augment_cart(params)
  end

  def get_cart_record(sid) when is_binary(sid) do
    VisitorSession.get_value(sid, get_cart_key())
    |> case do
      nil ->
        get_empty_cart_record()

      %{items: _items} = record ->
        record
    end
  end

  def get_cart_record(sid) when is_integer(sid), do: get_cart_record(to_string(sid))

  def get_cart_record(%{items: items} = record) when is_map(record) and is_list(items), do: record

  def get_cart_record(_), do: get_empty_cart_record()

  def add_item(cart_or_sid, sku, item_values \\ %{}, amount \\ 1)
      when (is_binary(sku) or is_integer(sku)) and is_map(item_values) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)
    cart_record = get_cart_record(cart_or_sid)

    find_item(cart_record, sku)
    |> case do
      nil ->
        cart_record
        |> update_in([:items], fn items ->
          items ++
            [create_cart_item(sku, item_values, amount)]
        end)

      _item ->
        cart_record
        |> change_quantity(sku, amount)
    end
    |> store_cart_record_if_needed(cart_or_sid)
  end

  def add_items(cart_or_sid, quantities)
      when is_map(quantities) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    cart_record = get_cart_record(cart_or_sid)

    quantities
    |> Map.to_list()
    |> Enum.reduce(cart_record, fn {sku, amount}, acc ->
      add_item(acc, sku, %{}, amount)
    end)
    |> store_cart_record_if_needed(cart_or_sid)
  end

  def find_item(%{items: items} = _cart_record, sku) when is_binary(sku) or is_integer(sku) do
    items |> Enum.find(nil, fn a -> a.sku == sku end)
  end

  def remove_item(cart_or_sid, sku) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    get_cart_record(cart_or_sid)
    |> update_in([:items], fn items ->
      items |> Enum.filter(fn a -> a.sku !== sku end)
    end)
    |> store_cart_record_if_needed(cart_or_sid)
  end

  def check_amount_limits(new_amount, sku, cart_or_sid) do
    max = @local_cart.get_max_for_sku(sku)

    if(new_amount > max) do
      if is_binary(cart_or_sid) do
        LiveUpdates.notify_live_view(
          cart_or_sid,
          {:cart, :limit_reached, max}
        )
      end

      max
    else
      new_amount
    end
  end

  def change_quantity(cart_or_sid, sku, amount, mode \\ "inc") when is_integer(amount) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    cart_record = get_cart_record(cart_or_sid)

    {_old_amount, result} =
      cart_record
      |> get_and_update_in([:items, Access.filter(&(&1.sku == sku)), :amount], fn prev ->
        new_amount =
          case mode do
            "inc" -> prev + amount
            "dec" -> (prev - amount) |> max(0)
            "set" -> amount
          end
          |> check_amount_limits(sku, cart_or_sid)

        {prev, new_amount}
      end)

    result
    |> update_in([:items], fn items ->
      items |> Enum.filter(fn a -> a.amount > 0 end)
    end)
    |> store_cart_record_if_needed(cart_or_sid)
  end

  def get_cart_count(cart_or_sid) do
    cart_record = get_cart_record(cart_or_sid)

    case cart_record do
      %{items: items} when is_list(items) ->
        Enum.reduce(items, 0, fn a, acc -> a.amount + acc end)

      _ ->
        0
    end
  end

  # adds a promo-code to the cart-record, does not check if promocode valid
  def add_promocode(cart_or_sid, promocode) when is_binary(promocode) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    get_cart_record(cart_or_sid)
    |> update_in([Access.key(:promocodes, [])], fn codes ->
      Enum.find_index(codes, &(&1 == promocode))
      |> case do
        nil -> codes ++ [promocode]
        _ -> codes
      end
    end)
    |> store_cart_record_if_needed(cart_or_sid)
  end

  # removes promocode from list
  def remove_promocode(cart_or_sid, promocode) when is_binary(promocode) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    get_cart_record(cart_or_sid)
    |> update_in([:promocodes], fn codes ->
      Enum.reject(codes, &(&1 == promocode))
    end)
    |> store_cart_record_if_needed(cart_or_sid)
  end

  def get_promocodes(cart_or_sid) do
    cart_or_sid = sanitize_cart_or_sid(cart_or_sid)

    get_cart_record(cart_or_sid)
    |> Map.get(:promocodes)
  end

  def sanitize_cart_or_sid(number) when is_integer(number), do: to_string(number)
  def sanitize_cart_or_sid(val), do: val
end
