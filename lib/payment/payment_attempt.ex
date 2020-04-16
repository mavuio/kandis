defmodule Kandis.PaymentAttempt do
  @moduledoc """
  A struct representing a payment-attempt.
  """

  use StructAccess

  @enforce_keys [:provider, :order_nr, :id]
  defstruct provider: nil,
            order_nr: nil,
            id: nil,
            created: nil,
            data: nil,
            payment_url: nil

  @typedoc "payment-attempt"
  @type t() :: %__MODULE__{
          provider: String.t(),
          order_nr: String.t() | nil,
          id: String.t(),
          data: map() | nil,
          created: DateTime.t() | nil,
          payment_url: String.t() | nil
        }
end
