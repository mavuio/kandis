defmodule Cat do
  @moduledoc false

  @callback treat(atom()) :: binary()

  # @callback eat(atom()) :: binary()

  @callback walk(atom()) :: binary()
  @optional_callbacks walk: 1

  defmacro __using__(_) do
    quote do
      use Pet

      @behaviour Cat
      def treat(treatment) do
        case treatment do
          :pet -> "purr"
          :tickle -> "bite"
          _ -> "ignore"
        end
      end

      defoverridable Cat
    end
  end
end
