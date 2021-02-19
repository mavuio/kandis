defmodule Kandis.Order do
  alias Kandis.Checkout
  alias Kandis.Pdfgenerator
  import Kandis.KdHelpers
  require Ecto.Query

  @invoice_nr_prefix Application.get_env(:kandis, :invoice_nr_prefix)
  @invoice_nr_testprefix Application.get_env(:kandis, :invoice_nr_testprefix)

  @local_order Application.get_env(:kandis, :local_order)
  @order_record Application.get_env(:kandis, :order_record)

  @server_view Application.get_env(:kandis, :server_view)
  @repo Application.get_env(:kandis, :repo)
  @translation_function Application.get_env(:kandis, :translation_function)

  @callback create_lineitem_from_cart_item(map(), map()) :: map()
  @callback apply_delivery_cost(map(), map()) :: map()

  def t(lang_or_context, translation_key, variables \\ []),
    do: @translation_function.(lang_or_context, translation_key, variables)

  def create_orderhtml(orderdata, orderinfo, order_record \\ nil, mode \\ "order")
      when is_map(orderdata) and is_map(orderinfo) do
    if function_exported?(@local_order, :create_orderhtml, 4) do
      @local_order.create_orderhtml(orderdata, orderinfo, order_record, mode)
    else
      Phoenix.View.render(@server_view, "orderhtml.html", %{
        orderdata: orderdata,
        orderinfo: orderinfo,
        order: order_record,
        lang: orderdata.lang,
        mode: mode,
        invoicemode: mode == "invoice"
      })
    end
  end

  def create_orderdata(ordercart, orderinfo) when is_map(ordercart) and is_map(orderinfo) do
    %{
      lineitems: [],
      stats: %{},
      lang: ordercart.lang,
      cart_id: ordercart.cart_id
    }
    |> add_lineitems_from_cart(ordercart, orderinfo)
    |> update_stats(orderinfo)
    |> add_product_subtotal(t(ordercart.lang, "order.subtotal"))
    |> @local_order.apply_delivery_cost(orderinfo)
    |> update_stats(orderinfo)
    # |> pipe_when(
    #   present?(@local_order.prepare_orderdata),
    |> @local_order.prepare_orderdata(ordercart, orderinfo)
    |> update_stats(orderinfo)
    # )
    |> add_total(t(ordercart.lang, "order.total"))
    |> add_total_taxes(orderinfo)
  end

  def add_total_taxes(%{stats: stats} = orderdata, _orderinfo) do
    orderdata
    |> update_in([:lineitems], fn lineitems ->
      new_lineitems =
        stats.taxrates
        |> Map.to_list()
        |> Enum.map(fn {taxrate, tax_stats} ->
          %{
            title: t(orderdata.lang, "order.incl_tax", taxrate: taxrate),
            type: "total_tax",
            total_price: tax_stats.tax
          }
        end)

      lineitems ++ new_lineitems
    end)
  end

  def add_product_subtotal(%{stats: stats} = orderdata, title) when is_binary(title) do
    orderdata
    |> update_in([:lineitems], fn lineitems ->
      new_lineitem = %{
        title: title,
        type: "subtotal",
        total_price: stats.total_price
      }

      lineitems ++ [new_lineitem]
    end)
  end

  def add_total(%{stats: stats} = orderdata, title) when is_binary(title) do
    orderdata
    |> update_in([:lineitems], fn lineitems ->
      new_lineitem = %{
        title: title,
        type: "total",
        total_price: stats.total_price
      }

      lineitems = lineitems |> remove_subtotal_if_lastitem()

      lineitems ++ [new_lineitem]
    end)
  end

  def remove_subtotal_if_lastitem(lineitems) do
    last_item = List.last(lineitems)

    case last_item.type do
      "subtotal" -> List.delete_at(lineitems, length(lineitems) - 1)
      _ -> lineitems
    end
  end

  def add_lineitems_from_cart(orderdata, %{items: cartitems} = _ordercart, orderinfo)
      when is_map(orderinfo) do
    orderdata
    |> update_in([:lineitems], fn lineitems ->
      new_lineitems =
        cartitems
        |> Enum.map(&@local_order.create_lineitem_from_cart_item(&1, orderinfo))
        |> Enum.filter(&Kandis.KdHelpers.present?/1)

      lineitems ++ new_lineitems
    end)
  end

  def update_stats(orderdata, _orderinfo) do
    orderdata
    |> update_in([:stats], fn stats ->
      stats
      |> Map.merge(get_stats_for_lineitems(orderdata.lineitems))
    end)
  end

  def get_stats_for_lineitems(lineitems) do
    lineitems
    # skip totals:
    |> Enum.filter(fn a -> not String.contains?(a.type, "total") end)
    |> Enum.reduce(
      %{total_amount: 0, total_price: "0", total_product_price: "0", taxrates: %{}},
      fn item, acc ->
        acc
        |> update_in(
          [:total_amount],
          &(&1 + (item[:amount] || 0))
        )
        |> update_in([:total_price], &Decimal.add(&1, item.total_price))
        |> pipe_when(
          item.type == "product",
          update_in([:total_product_price], &Decimal.add(&1, item.total_price))
        )
        |> pipe_when(
          item[:taxrate],
          update_in([:taxrates], &update_taxrate_stats(&1, item))
        )
      end
    )
  end

  def update_taxrate_stats(taxrates = %{}, %{taxrate: taxrate} = item) do
    taxkey = "#{taxrate}"

    taxrate_item =
      taxrates[taxkey]
      |> if_empty(%{tax: "0", net: "0", gross: "0"})
      |> taxrate_item_append(create_taxrate_stats_entry_for_item(item))

    taxrates
    |> Map.put(taxkey, taxrate_item)
  end

  def update_taxrate_stats(taxes, _, _), do: taxes

  def taxrate_item_append(map, new_item) when is_map(map) and is_map(new_item) do
    new_item
    |> Map.to_list()
    |> Enum.reduce(map, fn {key, val}, acc ->
      acc
      |> update_in([key], &Decimal.add(&1, val))
    end)
    |> Map.new()
  end

  def create_taxrate_stats_entry_for_item(item) do
    taxfactor = Decimal.div(item.taxrate, 100)
    gross = item.total_price
    net = Decimal.div(item.total_price, Decimal.add(taxfactor, 1))
    tax = Decimal.sub(gross, net)
    %{tax: tax, net: net, gross: gross}
  end

  def extract_shipping_address_fields(orderinfo) when is_map(orderinfo) do
    orderinfo
    |> Map.to_list()
    |> Enum.filter(&String.starts_with?(to_string(elem(&1, 0)), "shipping_"))
    |> Enum.map(fn {key, val} ->
      {String.trim_leading(to_string(key), "shipping_") |> String.to_existing_atom(), val}
    end)
    |> Map.new()
  end

  def atomize_maps(rec) when is_map(rec) do
    rec
    |> update_in([:orderdata], &AtomicMap.convert(&1, safe: true, ignore: true))
    |> update_in([:orderinfo], &AtomicMap.convert(&1, safe: true, ignore: true))
  end

  def atomize_maps(val), do: val

  def get_by_id(id) when is_integer(id) do
    @repo.get(@order_record, id)
    |> atomize_maps()
  end

  def get_by_cart_id(cart_id) when is_binary(cart_id) do
    @order_record
    |> Ecto.Query.where([o], o.cart_id == ^cart_id)
    |> Ecto.Query.where([o], o.state != "cancelled")
    |> @repo.one()
    |> atomize_maps()
  end

  def get_by_order_nr(order_nr) when is_binary(order_nr) do
    @repo.get_by(@order_record, order_nr: order_nr)
    |> atomize_maps()
  end

  def get_by_order_nr(nil), do: nil

  def get_by_invoice_nr(invoice_nr) when is_binary(invoice_nr) do
    @repo.get_by(@order_record, invoice_nr: invoice_nr)
    |> atomize_maps()
  end

  def get_by_any_id(any_id) when is_binary(any_id) do
    cond do
      String.starts_with?(any_id, @invoice_nr_prefix) -> get_by_invoice_nr(any_id)
      String.starts_with?(any_id, @invoice_nr_testprefix) -> get_by_invoice_nr(any_id)
      true -> get_by_order_nr(any_id)
    end
  end

  def get_by_any_id(any_id) when is_integer(any_id) do
    get_by_id(any_id)
  end

  def get_by_any_id(%_{} = order) when is_struct(order) do
    order
  end

  def create_new_order(orderdata, orderinfo) do
    @repo.transaction(fn ->
      data = create_order_record_from_checkout(orderdata, orderinfo)

      struct(@order_record)
      |> @order_record.changeset(data)
      |> @repo.insert()
    end)
    |> case do
      {:ok, {:ok, %_{} = order}} ->
        order

      _ ->
        nil
    end
  end

  def set_state(any_id, new_status) do
    {any_id, new_status} |> Kandis.KdHelpers.log("attempt to set status of order ", :info)

    get_by_any_id(any_id)
    |> @order_record.changeset(%{state: new_status})
    |> @repo.update()
    |> case do
      {:ok, order} ->
        case new_status do
          "cancelled" -> Task.start(fn -> update_stock(order) end)
          _ -> nil
        end

        order

      {:error, _err} ->
        raise "cannot set state on #{any_id}"
    end
  end

  def decrement_stock_for_order(%_{} = order) do
    order.orderdata.lineitems
    |> Enum.filter(&(&1.type == "product"))
    |> Enum.map(&decrement_stock_for_sku(&1.sku, &1.amount, order))

    update_stock(order)
    order
  end

  def decrement_stock_for_sku(sku, amount, order) do
    @local_order.decrement_stock_for_sku(sku, amount, order)
  end

  def update_stock(order) do
    @local_order.update_stock(order)
  end

  def create_order_record_from_checkout(orderdata, orderinfo)
      when is_map(orderdata) and is_map(orderinfo) do
    %{
      orderinfo: orderinfo,
      orderdata: orderdata,
      cart_id: orderdata.cart_id,
      order_nr: create_new_order_nr(is_testorder?(orderdata, orderinfo)),
      state: "created",
      user_id: orderinfo[:user_id],
      email: orderinfo[:email],
      payment_type: orderinfo[:payment_type],
      delivery_type: orderinfo[:delivery_type],
      shipping_country: Checkout.get_shipping_country(orderinfo),
      total_price: array_get(orderdata, [:stats, :total_price])
    }
  end

  def is_testorder?(orderdata, _orderinfo) do
    Decimal.lt?(array_get(orderdata, [:stats, :total_price], 100), 5)
  end

  def create_new_order_nr(is_testmode \\ false) do
    nr =
      if is_testmode do
        get_order_nr_prefix() <> "-TEST-" <> get_random_code(4)
      else
        get_order_nr_prefix() <> "-" <> get_random_code(4)
      end

    if order_nr_taken?(nr) do
      create_new_order_nr(is_testmode)
    else
      nr
    end
  end

  def order_nr_taken?(order_nr) when is_binary(order_nr) do
    case get_by_order_nr(order_nr) do
      nil -> false
      _ -> true
    end
  end

  def get_random_code(length) do
    Enum.shuffle(~w( A B C D E G H J K L M N P R S T U V X))
    |> Enum.join("")
    |> String.slice(1..length)
  end

  def get_order_nr_prefix() do
    Date.utc_today()
    |> Date.to_string()
    |> String.slice(0..-4)
    |> String.replace("-", "")
  end

  def update(data, _params \\ nil) do
    case data do
      %{"id" => id} -> get_by_id(id)
      %{id: id} -> get_by_id(id)
      %{"order_nr" => order_nr} -> get_by_order_nr(order_nr)
      %{order_nr: order_nr} -> get_by_order_nr(order_nr)
    end
    |> @order_record.changeset(data)
    |> @repo.insert_or_update()
  end

  def get_order_query(params) do
    id = params["id"]
    state = params["state"]

    @order_record
    |> pipe_when(id, Ecto.Query.where([o], o.id == ^id))
    |> pipe_when(state, Ecto.Query.where([o], o.state == ^state))
    |> Ecto.Query.order_by([o], desc: o.id)
  end

  def get_orders(params) do
    get_order_query(params)
    |> @repo.all()
  end

  def get_orderhtml(%_{} = order, mode \\ "order") do
    create_orderhtml(order.orderdata, order.orderinfo, order, mode)
  end

  def get_current_order_for_vid(vid, params \\ %{}) when is_binary(vid) and is_map(params) do
    with _cart = %{cart_id: cart_id} <- Kandis.Cart.get_cart_record(vid),
         %_{} = order <- get_by_cart_id(cart_id) do
      order
    else
      _err -> get_by_order_nr(params["order_nr"])
    end
    |> Kandis.KdHelpers.log("get_current_order_for_vid(#{vid})", :info)
  end

  def get_latest_order_for_vid(vid, params \\ %{}) when is_binary(vid) and is_map(params) do
    with _cart = %{cart_id: cart_id} <- Kandis.Cart.get_cart_record(vid),
         %_{} = firstorder <- get_all_by_cart_id(cart_id) |> hd(),
         %_{} = order <- firstorder |> atomize_maps do
      order
    else
      _err -> get_by_order_nr(params["order_nr"])
    end
  end

  def get_all_by_cart_id(cart_id) do
    @order_record
    |> Ecto.Query.where([o], o.cart_id == ^cart_id)
    |> Ecto.Query.where([o], o.state != "cancelled")
    |> Ecto.Query.order_by([o], desc: o.id)
    |> @repo.all()
  end

  # invoice functions

  def get_invoice_file(any_id, params \\ %{}) when is_binary(any_id) or is_integer(any_id),
    do: get_order_file(any_id, "invoice", params)

  def get_order_file(any_id, mode, params \\ %{})

  def get_order_file(any_id, "invoice" = mode, params)
      when is_binary(any_id) or is_integer(any_id) do
    get_by_any_id(any_id)
    |> case do
      %{invoice_nr: invoice_nr} when is_binary(invoice_nr) -> {:ok, invoice_nr}
      %{order_nr: order_nr} -> create_and_assign_new_invoice_nr_for_order(order_nr)
    end
    |> case do
      {:ok, invoice_nr} ->
        Pdfgenerator.get_pdf_file_for_invoice_nr(invoice_nr, mode, params)

        # {:error, error} ->
        #   raise "get_invoice_url received error:" <> inspect(error)
    end
  end

  def get_order_file(any_id, mode, params) when is_binary(any_id) or is_integer(any_id) do
    get_by_any_id(any_id)
    |> case do
      %{order_nr: order_nr} -> {:ok, order_nr}
      _ -> nil
    end
    |> case do
      {:ok, order_nr} ->
        Pdfgenerator.get_pdf_file_for_order_nr(order_nr, mode, params)

        # {:error, error} ->
        #   raise "get_invoice_url received error:" <> inspect(error)
    end
  end

  def get_invoice_url(any_id, params \\ %{}) when is_binary(any_id) or is_integer(any_id),
    do: get_order_file_url(any_id, "invoice", params)

  def get_order_file_url(any_id, mode, params \\ %{})
      when is_binary(mode) and (is_binary(any_id) or is_integer(any_id)) do
    get_order_file(any_id, mode, params)
    |> Pdfgenerator.get_url_for_file()
  end

  def create_new_invoice_nr(prefix) do
    get_latest_invoice_nr(prefix)
    |> increment_invoice_nr(prefix)
  end

  def increment_invoice_nr(invoice_nr, prefix) do
    nr = invoice_nr |> String.trim_leading(prefix) |> to_int()
    nr = nr + 1
    "#{prefix}#{nr}"
  end

  def order_nr_is_testmode?(order_nr) when is_binary(order_nr) do
    String.contains?(order_nr, "-TEST-")
  end

  def create_and_assign_new_invoice_nr_for_order(order_nr, tries \\ 0)

  def create_and_assign_new_invoice_nr_for_order(order_nr, tries) when tries > 100 do
    {:error, "could not create new invoice nr for order #{order_nr} after #{tries} tries "}
  end

  def create_and_assign_new_invoice_nr_for_order(order_nr, tries)
      when is_binary(order_nr) do
    inv_prefix =
      if order_nr_is_testmode?(order_nr) do
        @invoice_nr_testprefix
      else
        @invoice_nr_prefix
      end

    new_invoice_nr = create_new_invoice_nr(inv_prefix)

    %{order_nr: order_nr, invoice_nr: new_invoice_nr}
    |> Kandis.Order.update()
    |> case do
      {:ok, record} ->
        {:ok, record[:invoice_nr]}

      {:error,
       %Ecto.Changeset{errors: [invoice_nr: {_, [constraint: :unique, constraint_name: _]}]}} ->
        # try_again
        create_and_assign_new_invoice_nr_for_order(order_nr, tries + 1)

      {:error, error} ->
        {:error, error}
    end
  end

  def finish_order(order_nr) when is_binary(order_nr) do
    order = get_by_order_nr(order_nr)

    if order.state == "w4payment" do
      set_state(order_nr, "paid")
      Checkout.reset_checkout(order)
    end

    order = get_by_order_nr(order_nr)

    @local_order.finish_order(order)
  end

  def get_latest_invoice_nr(prefix) do
    invlike = "#{prefix}%"

    @order_record
    |> Ecto.Query.where([o], like(o.invoice_nr, ^invlike))
    |> @repo.aggregate(:max, :invoice_nr)
    |> if_nil("#{prefix}#{10000}")
  end

  def cancel_orders_for_cart_id(cart_id) when is_binary(cart_id) do
    @order_record
    |> Ecto.Query.where([o], o.cart_id == ^cart_id)
    |> Ecto.Query.where([o], o.state == "w4payment")
    |> Ecto.Query.update(set: [state: "cancelled"])
    |> @repo.update_all([])
  end

  def cancel_expired_orders(n \\ 100) do
    get_expired_orders()
    |> Enum.take(n)
    |> Enum.map(fn order_nr -> set_state(order_nr, "cancelled") end)
  end

  def get_expired_orders() do
    expire_minutes = 30
    expire_time = DateTime.utc_now() |> DateTime.add(expire_minutes * -60, :second)

    @order_record
    |> Ecto.Query.where([r], r.state == "w4payment")
    |> Ecto.Query.where([r], r.updated_at <= ^expire_time)
    |> Ecto.Query.select([r], r.order_nr)
    |> @repo.all()
  end
end
