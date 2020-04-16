defmodule Kandis.PaymentEvent do
  @moduledoc """
  A struct representing a payment-event.
  """

  use StructAccess

  @enforce_keys [:attempt_id]
  defstruct attempt_id: nil,
            created: nil,
            msg: nil,
            data: nil

  @typedoc "payment-event"
  @type t() :: %__MODULE__{
          attempt_id: String.t(),
          created: DateTime.t(),
          msg: String.t(),
          data: map() | nil
        }
end
