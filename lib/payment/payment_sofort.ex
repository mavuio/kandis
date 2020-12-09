defmodule Kandis.Payment.Sofort do
  @behaviour Kandis.Payment

  use Phoenix.HTML

  @providername "sofort"
  def create_payment_attempt({amount, curr}, order_nr, orderdata, orderinfo) do
    # process sofort.com payment
    data = generate_payment_data({amount, curr}, order_nr, orderdata, orderinfo)

    nil |> IO.inspect(label: "mwuits-debug 2020-08-19_00:20 payment data generated")
    payment_url = Kandis.KdHelpers.array_get(data, ["new_transaction", "payment_url"])
    id = Kandis.KdHelpers.array_get(data, ["new_transaction", "transaction"])

    # data = update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), nil)

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

  def generate_payment_data({amount, curr}, order_nr, orderdata, orderinfo) do
    generate_request_xml({amount, curr}, order_nr, orderdata, orderinfo)
    |> IO.inspect(label: "mwuits-debug 2020-04-16_10:20b REQUESTXML")
    |> make_request()
    |> case do
      {:ok, response} ->
        response.body |> XmlToMap.naive_map()

      err ->
        raise "payment data generation failed #{inspect(err)}"
    end
  end

  def generate_request_xml({amount, curr}, order_nr, orderdata, orderinfo) do
    project_id = Application.get_env(:kandis, :sofort)[:project_id]

    lang = orderdata[:lang]

    next_url =
      (Application.get_env(:kandis, :sofort)[:local_baseurl] <>
         "/#{lang}/checkout/payment_return")
      |> String.replace(".test/", "/")

    notification_url =
      (Application.get_env(:kandis, :sofort)[:local_baseurl] <>
         "/checkout/callback/sofort" <> "?vid=#{orderinfo.vid}")
      |> String.replace(".test/", "/")

    ~E(
      <?xml version="1.0" encoding="UTF-8" ?>
      <multipay>
            <project_id><%= project_id %></project_id>
            <interface_version>Kandis/Sofort0.2</interface_version>
            <amount><%= amount %></amount>
            <currency_code><%= curr %></currency_code>
            <reasons>
                  <reason>EVA BLUT Order</reason>
                  <reason><%= order_nr %></reason>
            </reasons>
            <user_variables>
                  <vid><%= orderinfo.vid %></vid>
                  <cart_id><%= orderdata.cart_id %></cart_id>
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
    url = "#{base_url}" |> IO.inspect(label: "sofort.com URL ")

    HTTPoison.post(url, String.trim(body), [], hackney: [basic_auth: {client_nr, api_key}])
    |> IO.inspect(label: "mwuits-debug 2020-08-19_00:40 ➜ RESPONSE")
  end
end

1
