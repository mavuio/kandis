defmodule Kandis.Payment.Stripe do
  @behaviour Kandis.Payment

  @providername "stripe"
  def create_payment_attempt({amount, curr}, order_nr, orderdata, orderinfo) do
    #  total_price = orderdata.stats.total_price

    data = update_or_create_intent({amount, curr}, get_stripe_payload(orderdata, orderinfo), nil)

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      id: data["id"],
      order_nr: order_nr
    }
  end

  def update_payment_attempt_if_needed(
        %Kandis.PaymentAttempt{} = attempt,
        {amount, curr},
        order_nr,
        orderdata,
        orderinfo
      ) do
    data =
      update_or_create_intent(
        {amount, curr},
        get_stripe_payload(orderdata, orderinfo),
        attempt.data["id"]
      )

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      id: data["id"],
      order_nr: order_nr
    }
  end

  def get_stripe_payload(orderdata, orderinfo) when is_map(orderinfo) and is_map(orderdata) do
    %{
      # "metadata[cart]" =>
      #   Application.get_env(:evablut, :config)[:local_url] <> "/ex/be/cart/" <> vid,
      "metadata[visit_id]" => orderinfo[:vid],
      "metadata[cart_id]" => orderdata[:cart_id],
      "description" => orderinfo[:email]
    }
  end

  # head_addons = []
  # head_addons = head_addons ++ ["<script src=\"https://js.stripe.com/v3/\"></script>"]

  # finished_url =
  #   EvablutWeb.Router.Helpers.checkout_step_path(
  #     EvablutWeb.Endpoint,
  #     :step,
  #     context["lang"],
  #     "finished"
  #   )

  # [
  #   stripe_data: stripe_data,
  #   stripe_pk: Application.fetch_env!(:stripy, :public_key),
  #   head_addons: head_addons,
  #   finished_url: finished_url
  # ]

  def update_or_create_intent(_, data \\ %{}, intent_id \\ nil)

  def update_or_create_intent({amount, curr}, data, intent_id) do
    data
    |> process_data_for_stripe_api({amount, curr})
    |> post_intent(intent_id)
  end

  def update_or_create_intent(nil, data, intent_id) do
    data
    |> post_intent(intent_id)
  end

  def process_data_for_stripe_api(data, {amount, curr}) do
    centamount =
      Decimal.mult("#{amount}", 100)
      |> Decimal.round()
      |> Decimal.to_integer()

    %{
      "currency" => curr
    }
    |> Map.merge(data)
    |> Map.put("amount", centamount)
  end

  def post_intent(data, client_secret \\ nil) do
    url =
      case client_secret do
        secret when is_binary(secret) -> "payment_intents/#{secret}"
        _ -> "payment_intents"
      end

    case Stripy.req(:post, url, data)
         |> Kandis.KdHelpers.log("Stripe POST intent", :info) do
      {:ok, response} ->
        response.body
        |> Jason.decode()
        |> case do
          {:ok, response_data} ->
            response_data

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  def process_callback(conn, %{"type" => type} = params) do
    metadata = params["data"]["object"]["metadata"]
    id = params["data"]["object"]["id"]

    vid = metadata["visit_id"]
    cart_id = metadata["cart_id"]

    attempt = Kandis.Payment.get_attempt_by_id(id, vid)

    params
    |> Kandis.Payment.log_event(vid, id, "got #{type} response from #{@providername}")

    msg =
      case type do
        "payment_intent.succeeded" ->
          complete_order_for_cart_id(cart_id, attempt)

        _ ->
          "event #{type} received for cart_id #{cart_id}"
      end

    Plug.Conn.send_resp(conn, 200, "Kandis: #{DateTime.utc_now()}  #{msg}")
  end

  def complete_order_for_cart_id(cart_id, attempt) when is_binary(cart_id) do
    order = Kandis.Order.get_by_cart_id(cart_id)

    case order do
      %_{} = order ->
        # set order-nr in intent

        Kandis.Order.finish_order(order.order_nr)

        if attempt do
          set_order_nr_in_intent(order, attempt)
        end

        "order #{order.order_nr} successfully processed "

      _ ->
        raise "payment_stripe: order not found for cartid #{cart_id}"
    end
  end

  def set_order_nr_in_intent(order, attempt) do
    update_or_create_intent(
      nil,
      %{
        "description" => "Order #{order.order_nr}",
        "metadata[order_nr]" => order.order_nr,
        "metadata[order]" =>
          Application.get_env(:kandis, :local_url) <>
            "/ex/be/order/" <> order.order_nr
      },
      attempt.id
    )
  end
end
