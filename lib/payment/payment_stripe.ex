defmodule Kandis.Payment.Stripe do
  @behaviour Kandis.Payment

  @providername "stripe"
  def create_payment_attempt({amount, curr}, orderdata, orderinfo) do
    #  total_price = orderdata.stats.total_price

    data = update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), nil)

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data
    }
  end

  def update_payment_attempt_if_needed(
        %Kandis.PaymentAttempt{} = attempt,
        {amount, curr},
        orderdata,
        orderinfo
      ) do
    data =
      update_or_create_intent({amount, curr}, get_stripe_payload(orderinfo), attempt.data["id"])

    %Kandis.PaymentAttempt{
      provider: @providername,
      data: data
    }
  end

  def get_stripe_payload(orderinfo) do
    %{
      # "metadata[cart]" =>
      #   Application.get_env(:evablut, :config)[:local_url] <> "/ex/be/cart/" <> vid,
      "metadata[visit_id]" => orderinfo[:vid],
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

  def update_or_create_intent({amount, curr}, data \\ %{}, client_secret \\ nil) do
    data
    |> process_data_for_stripe_api({amount, curr})
    |> post_intent(client_secret)
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
    url =
      case client_secret do
        secret when is_binary(secret) -> "payment_intents/#{secret}"
        _ -> "payment_intents"
      end

    case Stripy.req(:post, url, data) |> IO.inspect(label: "mwuits-debug 2020-03-27_21:58 ") do
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
end
