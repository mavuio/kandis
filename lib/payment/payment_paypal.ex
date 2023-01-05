defmodule Kandis.Payment.Paypal do
  # @behaviour Kandis.Payment

  use Phoenix.HTML

  import HappyWith

  @providername "paypal"

  def get_client_id() do
    Application.get_env(:kandis, :paypal)[:client_id]
  end

  def format_price_for_api(decimalval) do
    decimalval
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  def process_callback(conn, params) do
    params
    |> case do
      %{
        "event_type" => event_type,
        "resource" => %{
          "id" => paypal_id,
          "purchase_units" => [
            %{
              "invoice_id" => order_nr,
              "custom_id" => vid,
              "amount" => %{"currency_code" => currency_code, "value" => amount_str}
            }
          ],
          "status" => status
        }
      } ->
        paypal_id
        |> MavuUtils.log(
          "callback '#{event_type}' '#{status}' for paypal-order #{order_nr} vid #{vid} clcyan",
          :info
        )

        case event_type do
          "CHECKOUT.ORDER.APPROVED" ->
            happy_with do
              @get_order order when is_map(order) <- Kandis.Order.get_by_order_nr(order_nr)
              @check_currency "EUR" <- currency_code
              @get_should_amount_str should_amount_str <-
                                       format_price_for_api(order.orderitems.stats.total_price)

              @check_amount :eq <-
                              Decimal.cmp(
                                Decimal.round(should_amount_str),
                                Decimal.round(amount_str)
                              )
              @finish_order res <- Kandis.Order.finish_order(order_nr)
              res
            else
              {error_tag, _error_context} ->
                raise "'@#{error_tag}' failed, #{inspect(params, pretty: true)}"
            end

          _ ->
            nil
        end

      _ ->
        raise "cannot parse paypal.callback-data: #{inspect(params, pretty: true)}"
    end

    Plug.Conn.send_resp(conn, 200, "data received, thx")
  end
end
