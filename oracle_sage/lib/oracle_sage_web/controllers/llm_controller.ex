defmodule OracleSageWeb.LLMController do
  use OracleSageWeb, :controller
  require Logger

  alias OracleSage.{Questions, StackOverflowAPI, LLMClient, Instrumentation}

  def search_and_rerank(conn, %{"q" => query, "user_id" => user_id} = params) when is_binary(query) and query != "" do
    search_mode = Map.get(params, "search_mode", "strict")
    Logger.debug("Received search request - Query: '#{query}', User: '#{user_id}', Mode: '#{search_mode}'")
    
    result = Instrumentation.with_span("search_and_rerank", %{}, fn ->
      Instrumentation.add_user_context(user_id)
      Instrumentation.add_search_context(query, search_mode)
      
      # Cache the question
      {:ok, _cached_question} = Instrumentation.trace_database_operation("cache_question", "questions", fn ->
        Questions.cache_question(query, user_id)
      end)

      # Convert search mode to atom and determine if we should use loose search by default
      mode_atom = case search_mode do
        "loose" -> :loose
        _ -> :strict
      end

      # Search Stack Overflow with progressive fallback
      StackOverflowAPI.search_and_get_answers(query, user_id: user_id, default_search_mode: mode_atom)
    end)

    case result do
      {:ok, %{"question" => question, "answers" => answers, "search_strategy" => strategy, "total_attempts" => attempts}} ->
        formatted_question = StackOverflowAPI.format_question(question)
        formatted_answers = Enum.map(answers, &StackOverflowAPI.format_answer/1)

        Instrumentation.record_search_results(1, length(answers), strategy)

        # Create search feedback message
        search_info = case strategy do
          1 -> "Found with original search terms"
          2 -> "Found with AI-simplified search terms"
          3 -> "Found with AI-generated alternative terms"
          _ -> "Found with fallback search"
        end

        # Rerank answers using LLM
        case LLMClient.rerank_answers(formatted_question, formatted_answers) do
          {:ok, reranked_answers} ->
            # Generate related questions
            {:ok, related_questions} = LLMClient.generate_related_questions(formatted_question)
            
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              question: formatted_question,
              original_answers: formatted_answers,
              reranked_answers: reranked_answers,
              total_answers: length(formatted_answers),
              related_questions: related_questions,
              search_info: "#{search_info} (#{attempts} attempt#{if attempts > 1, do: "s", else: ""})"
            })

          {:error, _reason} ->
            # Fallback to original order
            conn
            |> put_status(:ok)
            |> json(%{
              success: true,
              question: formatted_question,
              original_answers: formatted_answers,
              reranked_answers: formatted_answers,
              total_answers: length(formatted_answers),
              search_info: "#{search_info} (#{attempts} attempt#{if attempts > 1, do: "s", else: ""})",
              warning: "LLM reranking failed, showing original order"
            })
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: reason
        })
    end
  end

  def search_and_rerank(conn, params) do
    Logger.warning("Invalid search request - Params: #{inspect(params)}")
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "Query parameter 'q' and 'user_id' are required"
    })
  end
end