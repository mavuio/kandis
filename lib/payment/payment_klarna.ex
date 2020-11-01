defmodule Kandis.Payment.Klarna do
  @behaviour Kandis.Payment

  use Phoenix.HTML

  @providername "klarna"

  def create_payment_attempt({_amount, _curr}, order_nr, orderdata, orderinfo) do
    #  total_price = orderdata.stats.total_price

    payload = get_klarna_payload(orderdata, orderinfo)

    data = create_klarna_session(payload)

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      id: data["session_id"],
      order_nr: order_nr
    }
  end

  def update_payment_attempt_if_needed(
        %Kandis.PaymentAttempt{} = attempt,
        {_amount, _curr},
        _order_nr,
        orderdata,
        orderinfo
      ) do
    payload = get_klarna_payload(orderdata, orderinfo)

    update_klarna_session(payload, attempt.id)

    attempt
  end

  def process_payment(vid, order) when is_binary(vid) and is_map(order) do
    get_latest_authorization_event(vid)
    |> case do
      %{authorization_token: authorization_token, attempt_id: tid} ->
        place_order(authorization_token, order)
        |> case do
          data when is_map(data) ->
            Kandis.Payment.log_event(data, vid, tid, "placed_klarna_order")
            |> case do
              _event = %{data: %{"fraud_status" => "ACCEPTED", "order_id" => order_id}} ->
                {:ok, order_id}

              _event = %{
                data: %{
                  "error_messages" => [
                    "The order has been already completed with different request body"
                  ]
                }
              } ->
                {:ok, "n/a"}

              event ->
                {:error, %{"msg" => "klarna could not process order", "data" => event}}
            end

          _ ->
            {:error, %{"msg" => "klarna could not receive order"}}
        end

      _ ->
        {:error, %{"msg" => "no authorization event found"}}
    end
  end

  def place_order(authorization_token, order)
      when is_map(order) and is_binary(authorization_token) do
    payload =
      get_klarna_payload(order.orderdata, order.orderinfo)
      |> Map.merge(%{
        "merchant_reference1" => order.order_nr,
        "merchant_reference2" => order.cart_id
      })

    make_request("/payments/v1/authorizations/#{authorization_token}/order", payload)
  end

  # order= Order.get_current_order_for_vid(vid)

  def get_authorization_events(vid) when is_binary(vid) do
    Kandis.Payment.get_all_payment_events(vid)
    |> Enum.map(fn a ->
      a
      |> Map.put(:authorization_token, a.data["authorization_token"])
      |> Map.put(:approved, a.data["approved"])
      |> Map.drop([:data, :__struct__, :msg])
    end)
    |> Enum.filter(fn a -> Kandis.KdHelpers.present?(a.authorization_token) end)
  end

  def get_latest_authorization_event(vid) when is_binary(vid) do
    get_authorization_events(vid)
    |> Enum.at(0)
  end

  def create_klarna_session(payload) when is_map(payload) do
    make_request("/payments/v1/sessions", payload)
  end

  def update_klarna_session(payload, session_id) when is_binary(session_id) and is_map(payload) do
    make_request("/payments/v1/sessions/#{session_id}", payload)
  end

  def release_klarna_authorization(authorization_token) when is_binary(authorization_token) do
    make_request("/payments/v1/authorizations/#{authorization_token}", :delete)
  end

  def get_klarna_session(session_id) when is_binary(session_id) do
    make_request("/payments/v1/sessions/#{session_id}", :get)
  end

  def get_taxamount_from_orderdata(orderdata) when is_map(orderdata) do
    orderdata.stats.taxrates
    |> Map.to_list()
    |> Enum.reduce("0", fn {_taxrate, tax_stats}, acc ->
      Decimal.add(acc, tax_stats.tax)
    end)
  end

  def centify(decimalval) do
    decimalval
    |> Decimal.mult(100)
    |> Decimal.round()
    |> Decimal.to_integer()
  end

  def get_order_lines_for_klarna(lineitems) when is_list(lineitems) do
    lineitems
    |> Enum.filter(fn l -> Enum.member?(~w(product addon), l.type) end)
    |> Enum.map(fn l ->
      rec =
        case l.type do
          "product" ->
            %{
              "type" => "physical",
              "reference" => l.sku,
              "name" => l.title <> " " <> l.subtitle,
              "quantity" => l.amount,
              "unit_price" => centify(l.single_price),
              "tax_rate" => centify(l.taxrate),
              "total_amount" => centify(l.total_price),
              "total_discount_amount" => 0
              # "image_url" => "https://www.exampleobjects.com/logo.png",
              # "product_url" => "https://www.estore.com/products/f2a8d7e34"
            }

          "addon" ->
            %{
              "type" => "shipping_fee",
              "quantity" => 1,
              "name" => l.title,
              "unit_price" => centify(l.total_price),
              "tax_rate" => centify(l.taxrate),
              "total_amount" => centify(l.total_price)
            }
        end

      total_tax_amount =
        if rec["tax_rate"] == 0 do
          0
        else
          Kernel.round(
            rec["total_amount"] - rec["total_amount"] * 10000 / (10000 + rec["tax_rate"])
          )
        end

      Map.put(rec, "total_tax_amount", total_tax_amount)
    end)
  end

  def get_klarna_payload(orderdata, orderinfo) do
    # orderdata
    # |> IO.inspect(label: "mwuits-debug 2020-08-20_01:07 get_klarna_paylaod ➜  orderdata")

    # orderinfo
    # |> IO.inspect(label: "mwuits-debug 2020-08-20_01:07 get_klarna_paylaod ➜  orderinfo")

    taxamount = get_taxamount_from_orderdata(orderdata)

    %{
      "purchase_country" => "AT",
      "purchase_currency" => "EUR",
      "locale" => "de-AT",
      "order_amount" => centify(orderdata.stats.total_price),
      "order_tax_amount" => centify(taxamount),
      "order_lines" => get_order_lines_for_klarna(orderdata.lineitems),
      "billing_address" => %{
        "given_name" => orderinfo[:first_name],
        "family_name" => orderinfo[:last_name],
        "email" => orderinfo[:email],
        "street_address" => orderinfo[:street],
        # "street_address2" => nil,
        "postal_code" => orderinfo[:zip],
        "city" => orderinfo[:city],
        "phone" => orderinfo[:phone],
        "country" => orderinfo[:country]
      }
    }

    # |> Kandis.KdError.die(label: "mwuits-debug 2020-08-20_01:17 ")
  end

  def make_request(url, method) when is_atom(method) do
    base_url = Application.get_env(:kandis, :klarna)[:base_url] |> String.trim_trailing("/")
    username = Application.get_env(:kandis, :klarna)[:username]
    password = Application.get_env(:kandis, :klarna)[:password]
    url = "#{base_url}#{url}" |> IO.inspect(label: "mwuits-debug 2020-03-29_12:07 ")

    HTTPoison.request(method, url, _body = "", _headers = [],
      hackney: [basic_auth: {username, password}]
    )
    |> case do
      {:ok, response} ->
        body =
          response
          |> Map.get(:body)

        case body do
          nil ->
            body

          "" ->
            body

          _ ->
            body
            |> Jason.decode()
            |> case do
              {:ok, str} -> str |> IO.inspect(label: "mwuits-debug 2020-08-19_00:40 ➜ RESPONSE")
              {:error, _} -> %{"error" => body}
            end
        end

      _ ->
        nil
    end
  end

  def make_request(url, payload) when is_map(payload) do
    base_url = Application.get_env(:kandis, :klarna)[:base_url] |> String.trim_trailing("/")
    username = Application.get_env(:kandis, :klarna)[:username]
    password = Application.get_env(:kandis, :klarna)[:password]
    url = "#{base_url}#{url}" |> IO.inspect(label: "mwuits-debug 2020-03-29_12:07 ")

    body =
      payload
      |> Jason.encode!()
      |> IO.inspect(label: "mwuits-debug 2020-08-20_11:08 ")

    # |> Kandis.KdError.die(label: "mwuits-debug 2020-08-20_02:07 ")

    HTTPoison.post(url, body, [{"Content-Type", "application/json"}],
      hackney: [basic_auth: {username, password}]
    )
    |> case do
      {:ok, response} ->
        body =
          response
          |> Map.get(:body)

        case body do
          nil ->
            body

          "" ->
            body

          _ ->
            body
            |> Jason.decode()
            |> case do
              {:ok, str} -> str |> IO.inspect(label: "mwuits-debug 2020-08-19_00:40 ➜ RESPONSE")
              {:error, _} -> %{"error" => body}
            end
        end

      _ ->
        nil
    end
  end
end

1
