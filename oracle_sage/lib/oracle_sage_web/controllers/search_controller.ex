defmodule OracleSageWeb.SearchController do
  use OracleSageWeb, :controller

  alias OracleSage.{Questions, StackOverflowAPI}

  def search(conn, %{"q" => query, "user_id" => user_id}) when is_binary(query) and query != "" do
    # Cache the question
    {:ok, _cached_question} = Questions.cache_question(query, user_id)

    # Search Stack Overflow
    case StackOverflowAPI.search_and_get_answers(query) do
      {:ok, %{"question" => question, "answers" => answers}} ->
        formatted_question = StackOverflowAPI.format_question(question)
        formatted_answers = Enum.map(answers, &StackOverflowAPI.format_answer/1)

        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          question: formatted_question,
          answers: formatted_answers,
          total_answers: length(formatted_answers)
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: reason
        })
    end
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "Query parameter 'q' and 'user_id' are required"
    })
  end

  def recent_questions(conn, %{"user_id" => user_id}) do
    recent_questions = Questions.list_recent_questions(user_id)
    
    conn
    |> put_status(:ok)
    |> json(%{
      success: true,
      questions: recent_questions
    })
  end

  def recent_questions(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "User ID parameter is required"
    })
  end
end