defmodule OracleSage.Question do
  use Ecto.Schema
  import Ecto.Changeset
  
  @derive {Jason.Encoder, only: [:id, :question, :searched_at, :user_id, :inserted_at, :updated_at]}

  schema "questions" do
    field :question, :string
    field :searched_at, :naive_datetime
    field :user_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [:question, :searched_at, :user_id])
    |> validate_required([:question, :searched_at, :user_id])
  end
end
