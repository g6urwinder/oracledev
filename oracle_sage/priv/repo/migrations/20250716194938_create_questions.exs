defmodule OracleSage.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions) do
      add :question, :text
      add :searched_at, :naive_datetime
      add :user_id, :string

      timestamps(type: :utc_datetime)
    end
    
    create index(:questions, [:user_id, :searched_at])
    create index(:questions, [:searched_at])
  end
end
