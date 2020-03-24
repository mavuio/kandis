defmodule Kandis.VisitorSessionStore do
  use Ecto.Schema
  import Ecto.Changeset

  schema "visitorsession" do
    field(:sid, :string)
    field(:state, :binary)
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :sid,
      :state
    ])
  end
end
