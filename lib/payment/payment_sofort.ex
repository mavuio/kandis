defmodule Kandis.Payment.Sofort do
  @behaviour Kandis.Payment

  use Phoenix.HTML

  @providername "sofort"
  def create_payment_attempt({amount, curr}, orderdata, orderinfo) do
    # process sofort.com payment
    data = generate_payment_data({amount, curr}, orderdata, orderinfo)

    payment_url = Kandis.KdHelpers.array_get(data, ["new_transaction", "payment_url"])

    # data = update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), nil)

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      payment_url: payment_url
    }
  end

  # def update_payment_attempt_if_needed(
  #       %Kandis.PaymentAttempt{} = attempt,
  #       {amount, curr},
  #       orderdata,
  #       orderinfo
  #     ) do
  #   data =
  #     update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), attempt.data["id"])

  #   %Kandis.PaymentAttempt{
  #     provider: @providername,
  #     data: data
  #   }
  # end

  # def process_callback(conn, _params) do
  #   conn.private[:raw_body]
  #   |> XmlToMap.naive_map()
  #   |> case do
  #     %{"status_notification" => %{"transaction" => tid}} ->
  #       get_status_for_transaction(tid)
  #       |> IO.inspect(label: "mwuits-debug 2020-04-08_22:23 RESPONSE:")

  #     # |> case do
  #     # end

  #     err ->
  #       raise "cannot handle sofort.callback-data: #{inspect(err)}"
  #   end
  # end

  def get_status_for_transaction(transaction_id) when is_binary(transaction_id) do
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

  def generate_payment_data({amount, curr}, orderdata, orderinfo) do
    generate_request_xml({amount, curr}, orderdata, orderinfo)
    |> make_request()
    |> case do
      {:ok, response} -> response.body |> XmlToMap.naive_map()
      err -> raise "payment data generation failed #{inspect(err)}"
    end
  end

  def generate_request_xml({amount, curr}, orderdata, orderinfo) do
    transaction_id = orderdata.cart_id

    project_id = Application.get_env(:kandis, :sofort)[:project_id]

    next_url =
      (Application.get_env(:kandis, :sofort)[:local_url] <>
         "/ex/checkout/payment")
      |> String.replace(".test/", "/")

    notification_url =
      (Application.get_env(:kandis, :sofort)[:local_url] <>
         "/ex/checkout/callback/sofort")
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
                  <reason><%= transaction_id %></reason>
            </reasons>
            <user_variables>
                  <vid><%= orderinfo.vid %></vid>
                  <cart_id><%= orderdata.cart_id %></cart_id>
            </user_variables>
            <success_url><%= next_url %>?success=<%= transaction_id %></success_url>
            <success_link_redirect>1</success_link_redirect>
            <abort_url><%= next_url %>?abort=<%= transaction_id %></abort_url>
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
    url = "#{base_url}" |> IO.inspect(label: "mwuits-debug 2020-03-29_12:07 ")

    HTTPoison.post(url, String.trim(body), [], hackney: [basic_auth: {client_nr, api_key}])
  end
end
