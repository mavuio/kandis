defmodule Chebur do
  @moduledoc false

  def treat(:pet) do
    "wiggle"
  end

  def treat(:striegel) do
    "rollaround"
  end

  def treat(treatment) do
    case treatment do
      :pet -> "purr"
      :tickle -> "scratch"
      :striegel -> "meow"
      _ -> "ignore"
    end
  end

  defoverridable treat: 1

  def treat(:pet) do
    "bite"
  end

  def treat(val) do
    super(val)
  end

  # defoverridable treat: 1

  # def treat(treatment) do
  #   "chebur does: " <> super(treatment)
  # end
end
