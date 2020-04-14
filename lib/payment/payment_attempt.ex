defmodule Kandis.PaymentAttempt do
  @moduledoc """
  A struct representing a payment-attempt.
  """

  use StructAccess

  @enforce_keys [:provider]
  defstruct provider: nil,
            data: nil

  @typedoc "payment-attempt"
  @type t() :: %__MODULE__{
          provider: String.t(),
          data: map() | nil
        }
end
