defmodule Kandis.Payment.Stripe do
  @behaviour Kandis.Payment

  @providername "stripe"
  def create_payment_attempt({amount, curr}, order_nr, _orderdata, orderinfo) do
    #  total_price = orderdata.stats.total_price

    data = update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), nil)

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
        _orderdata,
        orderinfo
      ) do
    data =
      update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), attempt.data["id"])

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data,
      id: data["id"],
      order_nr: order_nr
    }
  end

  def get_stripe_payload(orderinfo) do
    %{
      # "metadata[cart]" =>
      #   Application.get_env(:evablut, :config)[:local_url] <> "/ex/be/cart/" <> vid,
      "metadata" => %{visit_id: orderinfo[:vid]},
      "description" => orderinfo[:email],
      "automatic_payment_methods" => %{enabled: true}
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
      |> Decimal.to_integer()

    %{
      "currency" => curr
    }
    |> Map.merge(data)
    |> Map.put("amount", centamount)
  end

  def post_intent(data, client_secret \\ nil) do
    path =
      case client_secret do
        secret when is_binary(secret) -> "payment_intents/#{secret}"
        _ -> "payment_intents"
      end

    call_api(path, body: data)
    |> case do
      {:ok, rec} ->
        rec

      {:error, error_info} ->
        nil
    end
  end

  def config(:secret_key) do
    Application.get_env(:stripy, :secret_key)
  end

  def auth() do
    [
      authorization: "Bearer #{config(:secret_key)}",
      stripe_version: "2017-06-05"
    ]
  end

  def call_api(path, opts \\ [])
      when is_binary(path) do
    opts = Keyword.update(opts, :body, "", fn body -> Plug.Conn.Query.encode(body) end)

    Req.request(
      opts[:method] || :post,
      path,
      [
        base_url: "https://api.stripe.com/v1/",
        headers: auth() ++ [content_type: "application/x-www-form-urlencoded"],
        headers: auth()
      ] ++
        opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: error_status, body: body}} -> {:error, %{status: error_status, body: body}}
      e -> e
    end
  end

  def process_callback(conn, %{"type" => type} = params) do
    metadata = params["data"]["object"]["metadata"]
    id = params["data"]["object"]["id"]

    vid = metadata["visit_id"]

    attempt = Kandis.Payment.get_attempt_by_id(id, vid)

    params
    |> Kandis.Payment.log_event(vid, id, "got #{type} response from #{@providername}")

    msg =
      case type do
        "payment_intent.succeeded" ->
          complete_order_for_vid(vid, attempt)

        _ ->
          "event #{type} received for vid #{vid}"
      end

    Plug.Conn.send_resp(conn, 200, "Kandis: #{DateTime.utc_now()}  #{msg}")
  end

  def complete_order_for_vid(vid, attempt) do
    order = Kandis.Order.get_current_order_for_vid(vid)

    case order do
      %_{} = order ->
        # set order-nr in intent

        set_order_nr_in_intent(order, attempt)
        Kandis.Order.finish_order(order.order_nr)
        "order #{order.order_nr} successfully processed "

      _ ->
        "order not found for #{vid}"
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
