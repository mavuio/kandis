defmodule Kandis.Repo.Migrations.CreateVisitorsession do
  use Ecto.Migration

  def change do
    create table(:visitorsession) do
      add(:sid, :string, null: false)
      add(:state, :binary)

      timestamps()
    end

    create(unique_index(:visitorsession, [:sid]))
  end
end
