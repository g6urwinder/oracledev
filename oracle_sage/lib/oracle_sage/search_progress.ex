defmodule OracleSage.SearchProgress do
  @moduledoc """
  Module for broadcasting real-time search progress updates to users
  """

  def broadcast_progress(user_id, step, message, details \\ %{}) do
    OracleSageWeb.Endpoint.broadcast("search:#{user_id}", "search_update", %{
      step: step,
      message: message,
      details: details,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  def broadcast_strategy_attempt(user_id, attempt, strategy_name, search_terms) do
    # Only broadcast for important strategies to reduce clutter
    if attempt <= 2 do
      message = case attempt do
        1 -> "🔍 Searching with original terms"
        2 -> "🤖 Trying AI-optimized search"
        _ -> "Trying #{strategy_name}"
      end
      
      broadcast_progress(user_id, "strategy_attempt", message, %{
        strategy: strategy_name,
        search_terms: search_terms,
        attempt: attempt
      })
    end
  end

  def broadcast_strategy_result(user_id, attempt, strategy_name, success, result_count \\ 0) do
    # Only broadcast meaningful results to reduce clutter
    if success do
      message = case attempt do
        1 -> "✅ Found #{result_count} answers"
        2 -> "✅ AI optimization found #{result_count} answers"
        _ -> "✅ #{strategy_name} found #{result_count} answers"
      end
      
      broadcast_progress(user_id, "strategy_result", message, %{
        strategy: strategy_name,
        success: success,
        result_count: result_count,
        attempt: attempt
      })
    else
      # Only show failure for first strategy, skip noise for others
      if attempt == 1 do
        broadcast_progress(user_id, "strategy_result", "🔄 Trying AI optimization", %{
          strategy: strategy_name,
          success: success,
          result_count: result_count,
          attempt: attempt
        })
      end
    end
  end

  def broadcast_llm_request(user_id, type) do
    # Only show important LLM requests to reduce clutter
    case type do
      :simplify -> 
        broadcast_progress(user_id, "llm_request", "🤖 Optimizing search terms", %{type: type})
      :rerank -> 
        broadcast_progress(user_id, "llm_request", "🤖 AI ranking answers", %{type: type})
      _ -> 
        # Skip alternative and related for now to reduce noise
        :ok
    end
  end

  def broadcast_llm_response(user_id, type, result) do
    message = case type do
      :simplify -> "🤖 AI simplified to: \"#{result}\""
      :alternative -> "🤖 AI suggested: \"#{result}\""
      :rerank -> "🤖 AI finished reranking answers"
      :related -> "🤖 AI generated #{length(result)} related questions"
    end

    broadcast_progress(user_id, "llm_response", message, %{type: type, result: result})
  end

  def broadcast_stackoverflow_request(user_id, search_terms, full_url) do
    # Only show API request for first two attempts to reduce clutter
    if String.contains?(full_url, "intitle=") do
      terms = URI.decode_query(URI.parse(full_url).query)["intitle"] || search_terms
      if not String.contains?(terms, "-") do  # Skip malformed queries
        broadcast_progress(user_id, "stackoverflow_request", "📚 Searching Stack Overflow", %{
          search_terms: search_terms,
          api_url: full_url
        })
      end
    end
  end

  def broadcast_stackoverflow_response(user_id, success, count \\ 0) do
    message = if success do
      "📚 Found #{count} Stack Overflow questions"
    else
      "📚 No Stack Overflow results found"
    end

    broadcast_progress(user_id, "stackoverflow_response", message, %{
      success: success,
      count: count
    })
  end

  def broadcast_complete(user_id, total_attempts, final_strategy) do
    broadcast_progress(user_id, "complete", "✨ Search completed successfully!", %{
      total_attempts: total_attempts,
      final_strategy: final_strategy
    })
  end

  def broadcast_error(user_id, error_message) do
    broadcast_progress(user_id, "error", "❌ Search failed: #{error_message}", %{
      error: error_message
    })
  end
end