defmodule Kandis.Checkout do
  @moduledoc false

  alias Kandis.Cart
  alias Kandis.Order
  alias Kandis.VisitorSession
  @local_checkout Application.get_env(:kandis, :local_checkout)

  def get_visitorsession_key(), do: "checkout"

  def process(conn, %{"step" => step} = params) when is_binary(step) do
    conn =
      conn
      |> Plug.Conn.assign(:template_name, get_template_name_for_step(step))

    # call process-function of step
    apply(
      get_module_name(step),
      :process,
      [conn, params]
    )
  end

  def process(conn, _params), do: conn

  def get_template_name_for_step(step) do
    "checkout_#{step}.html"
  end

  def get_empty_checkout_record() do
    %{
      delivery_type: nil,
      payment_type: nil,
      email: ""
    }
  end

  def update(vid, clean_incoming_data) do
    VisitorSession.merge_into(vid, get_visitorsession_key(), clean_incoming_data)
  end

  def get_checkout_record(vid) when is_binary(vid) do
    VisitorSession.get_value(vid, get_visitorsession_key())
    |> case do
      nil ->
        rec = get_empty_checkout_record()
        VisitorSession.set_value(vid, get_visitorsession_key(), rec)
        rec

      %{email: _email} = record ->
        record
    end
  end

  def get_checkout_record(vid) when is_integer(vid), do: get_checkout_record(to_string(vid))

  def get_checkout_record(%{email: email} = record) when is_map(record) and is_binary(email),
    do: record

  def get_checkout_record(_), do: get_empty_checkout_record()

  def get_module_name(step) do
    String.to_atom(
      "Elixir." <>
        Application.get_env(:kandis, :steps_module_path) <>
        "." <> Macro.camelize("checkout_#{step}")
    )
  end

  def redirect_to_default_step(conn, params) do
    @local_checkout.redirect_to_default_step(conn, params)
  end

  def get_link_for_step(context, current_step) when is_map(context) do
    @local_checkout.get_link_for_step(context, current_step)
  end

  def get_next_step_link(context, current_step) when is_map(context) do
    @local_checkout.get_next_step_link(context, current_step)
  end

  def get_prev_step_link(context, current_step) when is_map(context) do
    @local_checkout.get_prev_step_link(context, current_step)
  end

  def map_atoms_to_strings(nil), do: %{}

  def map_atoms_to_strings(map) when is_map(map) do
    map |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  def create_ordercart(cart, lang \\ "en", orderinfo \\ %{})

  def create_ordercart(cart, lang, orderinfo) when is_map(cart) do
    @local_checkout.create_ordercart(cart, lang, orderinfo)
    |> Map.put(:lang, lang)
  end

  def create_ordercart(_, _, _), do: nil

  def create_orderinfo(checkout_record, vid) when is_map(checkout_record) and is_binary(vid) do
    @local_checkout.create_orderinfo(checkout_record)
    |> Map.put(:vid, vid)
  end

  def redirect_if_empty_cart(conn, vid, %{} = params, [] = opts \\ []) do
    if Cart.get_cart_count(vid) > 0 do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(
        :warning,
        opts[:msg] || "checkout was aborted because cart is empty"
      )
      |> Phoenix.Controller.redirect(to: get_cart_basepath(params))
      |> Plug.Conn.halt()
    end
  end

  def redirect_if_invalid_order(conn, order, %{} = params, [] = opts \\ []) do
    state =
      case order do
        nil -> "undefined"
        %_{} = order -> order.state
      end

    case state do
      state when state in ~w(cancelled undefined) ->
        conn
        |> Phoenix.Controller.put_flash(
          :warning,
          opts[:msg] || "checkout was aborted because no valid order was found"
        )
        |> Phoenix.Controller.redirect(to: get_cart_basepath(params))
        |> Plug.Conn.halt()

      state when state in ~w(paid emails_sent invoice_generated) ->
        conn
        |> Phoenix.Controller.redirect(to: get_link_for_step(params, "finished"))
        |> Plug.Conn.halt()

      _ ->
        conn
    end
  end

  def get_cart_basepath(params \\ %{}) when is_map(params) do
    @local_checkout.get_cart_basepath(params)
  end

  def get_shipping_country(orderinfo) when is_map(orderinfo) do
    @local_checkout.get_shipping_country(orderinfo)
  end

  def reset_checkout(order) do
    vid = order.orderinfo.vid
    cart_id = order.cart_id

    # check if vid still contains cart_id, only proceed if this is true
    cart = Cart.get_cart_record(vid)

    if(cart.cart_id == cart_id) do
      # save whole visitorsession under cart_id
      VisitorSession.clean_and_archive(
        vid,
        %{
          "cart" => Cart.get_empty_cart_record(),
          "last_order_nr" => order.order_nr,
          "payment" => nil,
          "payment_log" => nil
        },
        cart_id
      )
    end
  end

  def preview_order(vid, context) when is_binary(vid) do
    cart = Cart.get_augmented_cart_record(vid, context)
    checkout_record = Kandis.Checkout.get_checkout_record(vid)

    orderinfo = Kandis.Checkout.create_orderinfo(checkout_record, vid)
    ordercart = Kandis.Checkout.create_ordercart(cart, context["lang"], orderinfo)
    orderdata = Order.create_orderdata(ordercart, orderinfo)
    orderhtml = Order.create_orderhtml(orderdata, orderinfo)
    {orderdata, orderinfo, orderhtml}
  end

  def create_order_from_checkout(vid, context) when is_binary(vid) do
    cart = Cart.get_augmented_cart_record(vid, context)
    checkout_record = get_checkout_record(vid)

    ordercart = create_ordercart(cart, context["lang"])
    orderinfo = create_orderinfo(checkout_record, vid)
    orderdata = Order.create_orderdata(ordercart, orderinfo)

    Kandis.Order.create_new_order(orderdata, orderinfo)
  end
end
