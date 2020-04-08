defmodule Kandis.Checkout do
  @moduledoc false

  alias Kandis.Cart
  alias Kandis.VisitorSession
  @local_checkout Application.get_env(:kandis, :local_checkout)

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

  def create_ordercart(cart, lang \\ "en") when is_map(cart) do
    @local_checkout.create_ordercart(cart)
    |> Map.put(:lang, lang)
  end

  def create_orderinfo(checkout_record, sid) when is_map(checkout_record) and is_binary(sid) do
    @local_checkout.create_orderinfo(checkout_record)
    |> Map.put(:sid, sid)
  end

  def redirect_if_empty_cart(conn, params) do
    if Cart.get_cart_count(params[:current_userid]) > 0 do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:warning, "checkout was aborted because cart is empty")
      |> Phoenix.Controller.redirect(
        to: EvablutWeb.Router.Helpers.cart_path(conn, :step, params["lang"] || "en")
      )
      |> Plug.Conn.halt()
    end
  end

  def redirect_if_empty_email(conn, params) do
    checkout_record = VisitorSession.get_value(params[:current_userid], "checkout", %{})

    if checkout_record[:email] do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(
        to: EvablutWeb.Router.Helpers.checkout_path(conn, :index, params["lang"] || "en")
      )
      |> Plug.Conn.halt()
    end
  end

  def get_shipping_country(orderinfo) when is_map(orderinfo) do
    @local_checkout.get_shipping_country(orderinfo)
  end
end
