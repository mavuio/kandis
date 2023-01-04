defmodule Kandis.Payment.Sofort do
  @behaviour Kandis.Payment

  use Phoenix.HTML
  import Kandis.KdHelpers

  @providername "sofort"
  def create_payment_attempt({amount, curr}, order_nr, orderitems, ordervars) do
    # process sofort.com payment

    data = generate_payment_data({amount, curr}, order_nr, orderitems, ordervars)

    nil |> Kandis.KdHelpers.log("SOFORT payment data generated", :info)
    payment_url = Kandis.KdHelpers.array_get(data, ["new_transaction", "payment_url"])
    id = Kandis.KdHelpers.array_get(data, ["new_transaction", "transaction"])

    # data = update_or_create_intent({amount, curr}, get_stripe_payload(ordervars), nil)

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      id: id,
      order_nr: order_nr,
      payment_url: payment_url,
      created: nil
    }
  end

  def process_callback(conn, %{"vid" => vid} = _params) do
    msg =
      conn.private[:raw_body]
      |> XmlToMap.naive_map()
      |> case do
        %{"status_notification" => %{"transaction" => tid}} ->
          info = fetch_info_for_transaction(tid)

          attempt = Kandis.Payment.get_attempt_by_id(tid, vid)

          {status, order_nr} =
            case {info["transactions"]["transaction_details"]["status"], attempt} do
              {"untraceable", %Kandis.PaymentAttempt{} = attempt} ->
                {:ok, attempt.order_nr}

              {_, _} ->
                {:error, nil}
            end

          info
          |> Kandis.Payment.log_event(vid, tid, "got #{status} response from #{@providername}")

          if status == :ok do
            Kandis.Order.finish_order(order_nr)
          end

          status

        err ->
          "cannot handle sofort.callback-data: #{inspect(err)}"
      end

    Plug.Conn.send_resp(conn, 200, "#{msg}")
  end

  def fetch_info_for_transaction(transaction_id) when is_binary(transaction_id) do
    ~E(<?xml version="1.0" encoding="UTF-8" ?>
        <transaction_request version="2">
              <transaction><%= transaction_id %></transaction>
        </transaction_request>
    )
    |> case do
      {:safe, string_parts} -> Enum.join(string_parts)
    end
    |> make_request()
    |> case do
      {:ok, response} -> response.body |> XmlToMap.naive_map()
      err -> raise "payment url generation failed #{inspect(err)}"
    end
  end

  def generate_payment_data({amount, curr}, order_nr, orderitems, ordervars) do
    generate_request_xml({amount, curr}, order_nr, orderitems, ordervars)
    |> Kandis.KdHelpers.log("generate_payment_data REQUESTXML", :info)
    |> make_request()
    |> case do
      {:ok, response} ->
        response.body |> XmlToMap.naive_map()

      err ->
        raise "payment data generation failed #{inspect(err)}"
    end
  end

  def generate_request_xml({amount, curr}, order_nr, orderitems, ordervars) do
    project_id = Application.get_env(:kandis, :sofort)[:project_id]

    lang = orderitems[:lang]

    next_url =
      (Application.get_env(:kandis, :sofort)[:local_baseurl] <>
         "/#{lang}/checkout/payment_return")
      |> String.replace(".test/", "/")

    notification_url =
      (Application.get_env(:kandis, :sofort)[:local_baseurl] <>
         "/checkout/callback/sofort" <> "?vid=#{ordervars.vid}")
      |> String.replace(".test/", "/")

    payment_reason =
      orderitems[:payment_reason]
      |> if_nil(Application.get_env(:kandis, :sofort)[:payment_reason])
      |> if_nil("Online - Order")

    amount_str = amount |> Decimal.new() |> Decimal.round(2) |> to_string()

    ~E(
      <?xml version="1.0" encoding="UTF-8" ?>
      <multipay>
            <project_id><%= project_id %></project_id>
            <interface_version>Kandis/Sofort0.2</interface_version>
            <amount><%= amount_str %></amount>
            <currency_code><%= curr %></currency_code>
            <reasons>
                  <reason><%= payment_reason %></reason>
                  <reason><%= order_nr %></reason>
            </reasons>
            <user_variables>
                  <vid><%= ordervars.vid %></vid>
                  <cart_id><%= orderitems.cart_id %></cart_id>
            </user_variables>
            <success_url><%= next_url %>?status=success&amp;order_nr=<%= order_nr %></success_url>
            <success_link_redirect>1</success_link_redirect>
            <abort_url><%= next_url %>?status=cancelled&amp;order_nr=<%= order_nr %></abort_url>
            <notification_urls>
                  <notification_url><%= notification_url %></notification_url>
            </notification_urls>
            <su />
      </multipay>
    )
    |> case do
      {:safe, string_parts} -> Enum.join(string_parts) |> String.trim()
    end
  end

  def make_request(body) do
    base_url = Application.get_env(:kandis, :sofort)[:base_url]
    api_key = Application.get_env(:kandis, :sofort)[:api_key]
    client_nr = Application.get_env(:kandis, :sofort)[:client_nr]
    url = "#{base_url}" |> Kandis.KdHelpers.log("sofort.com URL ", :info)

    HTTPoison.post(url, String.trim(body), [], hackney: [basic_auth: {client_nr, api_key}])
    |> Kandis.KdHelpers.log("SOFORT ➜ RESPONSE", :info)
  end
end

1
