defmodule OracleSage.Questions do
  @moduledoc """
  The Questions context for managing cached questions.
  """

  import Ecto.Query, warn: false
  alias OracleSage.Repo
  alias OracleSage.Question

  @doc """
  Returns the list of recent questions for a user (last 5).
  """
  def list_recent_questions(user_id) do
    from(q in Question,
      where: q.user_id == ^user_id,
      order_by: [desc: q.searched_at],
      limit: 5
    )
    |> Repo.all()
  end

  @doc """
  Gets a single question by id.
  """
  def get_question!(id), do: Repo.get!(Question, id)

  @doc """
  Creates a question.
  """
  def create_question(attrs \\ %{}) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a question.
  """
  def update_question(%Question{} = question, attrs) do
    question
    |> Question.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a question.
  """
  def delete_question(%Question{} = question) do
    Repo.delete(question)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking question changes.
  """
  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  @doc """
  Cache a question for a user, ensuring only last 5 are kept.
  """
  def cache_question(question_text, user_id) do
    # First, create the new question
    {:ok, new_question} = create_question(%{
      question: question_text,
      searched_at: NaiveDateTime.utc_now(),
      user_id: user_id
    })

    # Then, keep only the 5 most recent questions for this user
    recent_questions = list_recent_questions(user_id)
    if length(recent_questions) > 5 do
      # Delete the oldest questions beyond the 5 most recent
      questions_to_delete = Enum.drop(recent_questions, 5)
      Enum.each(questions_to_delete, &delete_question/1)
    end

    {:ok, new_question}
  end
end