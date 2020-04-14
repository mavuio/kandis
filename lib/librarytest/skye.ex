defmodule Skye do
  @moduledoc false
  use Cat

  # def treat(treatment) do
  #   case treatment do
  #     :pet -> "PURR"
  #     :tickle -> "BITE"
  #     _ -> "IGNORE"
  #   end
  # end

  # defoverridable treat: 1

  # def treat(treatment) do
  #   "cat does: " <> super(treatment)
  # end

  @impl Cat
  def treat(treatment) do
    "skye does: " <> super(treatment)
  end
end
