defmodule Kandis.Payment do
  @moduledoc false
  alias Kandis.PaymentAttempt
  alias Kandis.PaymentEvent

  @callback create_payment_attempt({binary(), binary()}, binary(), map(), map()) ::
              Kandis.PaymentAttempt.t()

  @callback update_payment_attempt_if_needed(
              Kandis.PaymentAttempt.t(),
              {binary(), binary()},
              map(),
              map()
            ) :: Kandis.PaymentAttempt.t()

  @optional_callbacks [update_payment_attempt_if_needed: 4]

  def get_visitorsession_key(), do: "payment"

  def default_currency(), do: "EUR"

  def get_module_name(providername) do
    String.to_atom("Elixir.Kandis.Payment." <> Macro.camelize(providername))
  end

  def process_callback(conn, %{"provider" => provider} = params) when is_binary(provider) do
    # call process_callback-function of provider
    apply(
      get_module_name(provider),
      :process_callback,
      [conn, params]
    )
  end

  def process_callback(conn, _params), do: conn

  def create_payment_attempt(providername, order_nr, orderdata, orderinfo) do
    amount = orderdata.stats.total_price
    curr = default_currency()

    # vid = orderinfo.vid

    apply(get_module_name(providername), :create_payment_attempt, [
      {amount, curr},
      order_nr,
      orderdata,
      orderinfo
    ])
  end

  def log_event(data, vid, tid, msg)
      when is_map(data) and is_binary(vid) and is_binary(tid) and is_binary(msg) do
    %Kandis.PaymentEvent{
      attempt_id: tid,
      msg: msg,
      data: data
    }
    |> add_payment_event(vid)
  end

  def add_payment_attempt(%PaymentAttempt{} = attempt, vid) do
    attempt =
      if is_nil(attempt.created) do
        put_in(attempt.created, DateTime.utc_now())
      end

    attempts = [attempt | get_all_payment_attempts(vid)]
    Kandis.VisitorSession.set_value(vid, get_visitorsession_key(), attempts)
    attempt
  end

  def add_payment_event(%PaymentEvent{} = event, vid) do
    event =
      if is_nil(event.created) do
        put_in(event.created, DateTime.utc_now())
      end

    events = [event | get_all_payment_events(vid)]
    Kandis.VisitorSession.set_value(vid, get_visitorsession_key() <> "_log", events)
    event
  end

  def get_all_payment_attempts(vid) when is_binary(vid) do
    Kandis.VisitorSession.get_value(vid, get_visitorsession_key(), [])
  end

  def get_all_payment_events(vid) when is_binary(vid) do
    Kandis.VisitorSession.get_value(vid, get_visitorsession_key() <> "_log", [])
  end

  def get_latest_payment_attempt(vid) do
    get_all_payment_attempts(vid)
    |> hd()
  end

  def get_all_payment_attempts_for_provider(providername, vid)
      when is_binary(providername) and is_binary(vid) do
    get_all_payment_attempts(vid)
    |> Enum.filter(&(&1.provider == providername))
  end

  def get_payment_attempt_for_provider(providername, vid)
      when is_binary(vid) and is_binary(providername) do
    get_all_payment_attempts_for_provider(providername, vid)
    |> hd()
  end

  def create_and_add_payment_attempt_for_provider(providername, order_nr, orderdata, orderinfo)
      when is_binary(providername) and is_map(orderinfo) and is_map(orderdata) do
    create_payment_attempt(providername, order_nr, orderdata, orderinfo)
    |> add_payment_attempt(orderinfo.vid)
  end

  def get_or_create_payment_attempt_for_provider(providername, order_nr, orderdata, orderinfo)
      when is_binary(providername) and is_map(orderinfo) and is_map(orderdata) do
    case get_payment_attempt_for_provider(providername, orderinfo.vid) do
      nil ->
        create_payment_attempt(providername, order_nr, orderdata, orderinfo)
        |> add_payment_attempt(orderinfo.vid)

      attempt ->
        attempt |> update_payment_attempt_if_needed(orderinfo.vid, order_nr, orderdata, orderinfo)
    end
  end

  def get_attempt_by_id(id, vid) when is_binary(id) do
    get_all_payment_attempts(vid)
    |> Enum.filter(&(&1.id == id))
    |> hd()
  end

  def update_payment_attempt_if_needed(
        %PaymentAttempt{} = attempt,
        vid,
        order_nr,
        orderdata,
        orderinfo
      )
      when is_binary(vid) and is_map(orderinfo) and is_map(orderdata) do
    amount = orderdata.stats.total_price
    curr = default_currency()

    # vid = orderinfo.vid

    apply(get_module_name(attempt.provider), :update_payment_attempt_if_needed, [
      attempt,
      {amount, curr},
      order_nr,
      orderdata,
      orderinfo
    ])
  end
end
