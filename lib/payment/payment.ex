defmodule Kandis.Payment do
  @moduledoc false
  alias Kandis.PaymentAttempt

  @callback create_payment_attempt({binary(), binary()}, map(), map()) ::
              Kandis.PaymentAttempt.t()

  @callback update_payment_attempt_if_needed(
              Kandis.PaymentAttempt.t(),
              {binary(), binary()},
              map(),
              map()
            ) :: Kandis.PaymentAttempt.t()

  def get_visitorsession_key(), do: "payment"

  def default_currency(), do: "EUR"

  def get_module_name(providername) do
    String.to_atom("Elixir.Kandis.Payment." <> Macro.camelize(providername))
  end

  def create_payment_attempt(providername, orderdata, orderinfo) do
    amount = orderdata.stats.total_price
    curr = default_currency()

    # vid = orderinfo.vid

    apply(get_module_name(providername), :create_payment_attempt, [
      {amount, curr},
      orderdata,
      orderinfo
    ])
  end

  def add_payment_attempt(%PaymentAttempt{} = attempt, vid) do
    attempts = [attempt | get_all_payment_attempts(vid)]
    Kandis.VisitorSession.set_value(vid, get_visitorsession_key(), attempts)
    attempt
  end

  def get_all_payment_attempts(vid) when is_binary(vid) do
    Kandis.VisitorSession.get_value(vid, get_visitorsession_key(), [])
  end

  def get_latest_payment_attempt(vid) do
    get_all_payment_attempts(vid)
    |> hd()
  end

  def get_payment_attempt_for_provider(providername, vid) do
    get_all_payment_attempts(vid)
    |> Enum.find(&(&1.provider == providername))
  end

  def get_or_create_payment_attempt_for_provider(providername, orderdata, orderinfo) do
    case get_payment_attempt_for_provider(providername, orderinfo.vid) do
      nil ->
        create_payment_attempt(providername, orderdata, orderinfo)
        |> add_payment_attempt(orderinfo.vid)

      attempt ->
        attempt |> update_payment_attempt_if_needed(orderinfo.vid, orderdata, orderinfo)
    end
  end

  def update_payment_attempt_if_needed(%PaymentAttempt{} = attempt, vid, orderdata, orderinfo)
      when is_binary(vid) and is_map(orderinfo) and is_map(orderdata) do
    amount = orderdata.stats.total_price
    curr = default_currency()

    vid = orderinfo.vid

    apply(get_module_name(attempt.provider), :update_payment_attempt_if_needed, [
      attempt,
      {amount, curr},
      orderdata,
      orderinfo
    ])
  end
end
