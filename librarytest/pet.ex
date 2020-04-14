defmodule Pet do
  @moduledoc false

  @callback treat(atom()) :: binary()
  @callback eat(atom()) :: binary()

  defmacro __using__(_) do
    quote do
      @behaviour Pet
      defoverridable Pet

      def eat(food) do
        "animal eats #{to_string(food)}"
      end
    end
  end
end
