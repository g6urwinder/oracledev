defmodule OracleSage.StackOverflowAPI do
  @moduledoc """
  Module to interact with Stack Overflow API for fetching questions and answers.
  """
  require Logger

  @base_url "https://api.stackexchange.com/2.3"
  @site "stackoverflow"

  def extract_key_terms(query) do
    # Extract important programming terms and keywords
    extracted = query
    |> String.downcase()
    |> String.replace(~r/[^\w\s#\+\.]/, " ")  # Keep programming chars like # + but remove * - 
    |> String.split()
    |> Enum.filter(fn word -> 
      # Keep programming-related words and filter out common words
      String.length(word) >= 3 and word not in ~w(
        the and but for are was will you can how what when where why which
        that this they them their with from have been said each about after
        before during into through under over between among within without
        would could should might must may also just only even still
      )
    end)
    |> Enum.take(5)  # Limit to 5 key terms
    |> Enum.join(" ")
    
    # Fallback to original query if extraction results in empty string
    case String.trim(extracted) do
      "" -> 
        Logger.debug("Key term extraction failed for: #{query}, using fallback")
        String.slice(query, 0, 50)  # Use first 50 chars as fallback
      result -> 
        Logger.debug("Extracted key terms from '#{query}' -> '#{result}'")
        result
    end
  end

  # Clean search terms for display (remove special chars but keep content)
  defp clean_search_terms_for_display(terms) do
    terms
    |> String.replace(~r/^[\*\-\+\s]+/, "")  # Remove leading special chars
    |> String.replace(~r/[\*\-\+]+/, " ")    # Replace special chars with spaces
    |> String.replace(~r/\s+/, " ")          # Normalize multiple spaces
    |> String.trim()
  end

  def search_questions(query, options \\ []) do
    # Use general search (q) for better results with AI-generated questions
    # Extract key terms from the query for better matching
    search_terms = extract_key_terms(query)
    
    params = %{
      "intitle" => search_terms,
      "site" => @site,
      "order" => "desc",
      "sort" => "relevance",
      "pagesize" => Keyword.get(options, :pagesize, 5),
      "filter" => "withbody"
    }

    Logger.debug("Stack Overflow API request - URL: #{@base_url}/search, Params: #{inspect(params)}")
    
    case HTTPoison.get("#{@base_url}/search", [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("Stack Overflow API success: 200")
        result = Jason.decode(body)
        case result do
          {:ok, %{"items" => items}} when is_list(items) ->
            Logger.debug("Found #{length(items)} questions")
          {:ok, response} ->
            Logger.warning("Unexpected response structure: #{inspect(Map.keys(response))}")
          {:error, error} ->
            Logger.error("JSON decode error: #{inspect(error)}")
        end
        result

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("Stack Overflow API failed: #{status_code}, Body: #{body}")
        {:error, "API request failed with status: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request error: #{reason}")
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def get_question_answers(question_id, options \\ []) do
    params = %{
      "site" => @site,
      "order" => "desc",
      "sort" => "votes",
      "pagesize" => Keyword.get(options, :pagesize, 10),
      "filter" => "withbody"
    }

    # Build the actual URL for logging
    query_string = URI.encode_query(params)
    full_url = "#{@base_url}/questions/#{question_id}/answers?#{query_string}"
    
    # Log the API call
    log_stackoverflow_api_call("answers", full_url, params, "question_id:#{question_id}")
    
    start_time = System.monotonic_time(:millisecond)

    case HTTPoison.get("#{@base_url}/questions/#{question_id}/answers", [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        case Jason.decode(body) do
          {:ok, %{"items" => items} = response} ->
            log_stackoverflow_api_response("answers", 200, length(items), response_time, "question_id:#{question_id}")
            {:ok, response}
          {:ok, response} ->
            log_stackoverflow_api_response("answers", 200, 0, response_time, "question_id:#{question_id}")
            {:ok, response}
          {:error, _} = error ->
            log_stackoverflow_api_response("answers", 200, 0, response_time, "question_id:#{question_id}", "JSON decode error")
            error
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        log_stackoverflow_api_response("answers", status_code, 0, response_time, "question_id:#{question_id}", "HTTP #{status_code}: #{String.slice(body, 0, 100)}")
        {:error, "API request failed with status: #{status_code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        log_stackoverflow_api_response("answers", 0, 0, response_time, "question_id:#{question_id}", "HTTP Error: #{reason}")
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  def search_and_get_answers(query, options \\ []) do
    user_id = Keyword.get(options, :user_id, "demo_user")
    Logger.info("Starting LLM-guided search for: #{query}")
    
    OracleSage.SearchProgress.broadcast_progress(user_id, "start", "🚀 Starting intelligent search...", %{query: query})
    
    # Try original query first, then use LLM with context about what failed
    search_strategies = [
      fn -> search_with_original_query(query, options) end,
      fn(failed_attempts) -> search_with_llm_simplified_query(query, failed_attempts, options) end,
      fn(failed_attempts) -> search_with_llm_alternative_query(query, failed_attempts, options) end
    ]
    
    try_search_strategies(search_strategies, query, 1, user_id, [])
  end
  
  defp try_search_strategies([], query, attempt, user_id, failed_attempts) do
    Logger.info("All strategies failed, trying final fallback with programming language")
    
    # Final attempt - use LLM to detect programming language
    fallback_terms = case OracleSage.LLMClient.detect_programming_language(query) do
      {:ok, language} when language != "" -> language
      _ -> extract_programming_language(query) # Manual fallback
    end
    
    final_terms = if fallback_terms != "", do: fallback_terms, else: "programming"
    clean_terms = clean_search_terms_for_display(final_terms)
    
    OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, attempt, "Language Fallback", clean_terms)
    
    # Use loose search for final fallback
    fallback_options = [search_mode: :loose]
    case search_questions_with_params(final_terms, fallback_options) do
      {:ok, %{"items" => questions}} when length(questions) > 0 ->
        question = List.first(questions)
        question_id = question["question_id"]
        
        case get_question_answers(question_id) do
          {:ok, %{"items" => answers}} ->
            Logger.info("Fallback found #{length(answers)} answers with: #{final_terms}")
            OracleSage.SearchProgress.broadcast_strategy_result(user_id, attempt, "Language Fallback", true, length(answers))
            OracleSage.SearchProgress.broadcast_complete(user_id, attempt, "Language Fallback")
            {:ok, %{
              "question" => question,
              "answers" => answers,
              "search_strategy" => attempt,
              "total_attempts" => attempt
            }}
          
          {:error, _} ->
            OracleSage.SearchProgress.broadcast_error(user_id, "No relevant questions found after trying all strategies")
            {:error, "No relevant questions found after trying all strategies"}
        end
      
      _ ->
        OracleSage.SearchProgress.broadcast_error(user_id, "No relevant questions found after trying all strategies")
        {:error, "No relevant questions found after trying all strategies"}
    end
  end
  
  defp try_search_strategies([strategy | remaining], query, attempt, user_id, failed_attempts) do
    Logger.debug("Search attempt #{attempt}")
    
    # Execute strategy with context about failed attempts (first strategy doesn't need context)
    result = if attempt == 1 do
      strategy.()
    else
      strategy.(failed_attempts)
    end
    
    case result do
      {:ok, %{"items" => questions}} when length(questions) > 0 ->
        Logger.info("Found #{length(questions)} questions with strategy #{attempt}")
        
        question = List.first(questions)
        question_id = question["question_id"]
        
        case get_question_answers(question_id) do
          {:ok, %{"items" => answers}} ->
            Logger.info("Got #{length(answers)} answers")
            strategy_name = get_strategy_name(attempt)
            OracleSage.SearchProgress.broadcast_strategy_result(user_id, attempt, strategy_name, true, length(answers))
            OracleSage.SearchProgress.broadcast_complete(user_id, attempt, strategy_name)
            {:ok, %{
              "question" => question,
              "answers" => answers,
              "search_strategy" => attempt,
              "total_attempts" => attempt
            }}
          
          {:error, reason} ->
            Logger.debug("Failed to get answers: #{reason}, trying next strategy")
            strategy_name = get_strategy_name(attempt)
            OracleSage.SearchProgress.broadcast_strategy_result(user_id, attempt, strategy_name, false)
            failed_attempt = %{strategy: strategy_name, reason: "no_answers", terms: extract_key_terms(query)}
            try_search_strategies(remaining, query, attempt + 1, user_id, [failed_attempt | failed_attempts])
        end
      
      {:ok, %{"items" => []}} ->
        Logger.debug("No questions found with strategy #{attempt}, trying next")
        strategy_name = get_strategy_name(attempt)
        OracleSage.SearchProgress.broadcast_strategy_result(user_id, attempt, strategy_name, false)
        failed_attempt = %{strategy: strategy_name, reason: "no_questions", terms: extract_key_terms(query)}
        try_search_strategies(remaining, query, attempt + 1, user_id, [failed_attempt | failed_attempts])
      
      {:error, reason} ->
        Logger.debug("Strategy #{attempt} failed: #{reason}, trying next")
        strategy_name = get_strategy_name(attempt)
        OracleSage.SearchProgress.broadcast_strategy_result(user_id, attempt, strategy_name, false)
        failed_attempt = %{strategy: strategy_name, reason: "api_error", terms: extract_key_terms(query)}
        try_search_strategies(remaining, query, attempt + 1, user_id, [failed_attempt | failed_attempts])
    end
  end

  defp get_strategy_name(attempt) do
    case attempt do
      1 -> "Original Terms"
      2 -> "AI Simplified"
      3 -> "AI Alternative"
      _ -> "Fallback"
    end
  end
  
  defp search_with_original_query(query, options) do
    user_id = Keyword.get(options, :user_id, "demo_user")
    default_mode = Keyword.get(options, :default_search_mode, :strict)
    search_terms = extract_key_terms(query)
    clean_terms = clean_search_terms_for_display(search_terms)
    
    mode_description = if default_mode == :loose, do: "loose", else: "strict"
    Logger.debug("Strategy 1: Using original key terms with #{mode_description} search: '#{search_terms}'")
    OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, 1, "Original Terms", clean_terms)
    
    # Use the user's selected search mode
    options_with_mode = Keyword.put(options, :search_mode, default_mode)
    search_questions_with_params(search_terms, options_with_mode)
  end
  
  defp search_with_llm_simplified_query(query, failed_attempts, options) do
    user_id = Keyword.get(options, :user_id, "demo_user")
    default_mode = Keyword.get(options, :default_search_mode, :strict)
    OracleSage.SearchProgress.broadcast_llm_request(user_id, :simplify)
    
    case OracleSage.LLMClient.simplify_search_query(query, failed_attempts) do
      {:ok, simplified_query} ->
        clean_terms = clean_search_terms_for_display(simplified_query)
        # If user chose strict and it failed, try loose for LLM strategies
        next_mode = if default_mode == :strict, do: :loose, else: :strict
        mode_description = if next_mode == :loose, do: "loose", else: "strict"
        
        Logger.debug("Strategy 2: LLM simplified query with #{mode_description} search: '#{simplified_query}'")
        OracleSage.SearchProgress.broadcast_llm_response(user_id, :simplify, clean_terms)
        OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, 2, "AI Simplified", clean_terms)
        
        # Use alternate search mode for simplified terms
        options_with_mode = Keyword.put(options, :search_mode, next_mode)
        search_questions_with_params(simplified_query, options_with_mode)
      
      {:error, _reason} ->
        # Fallback to manual simplification
        search_terms = query
        |> extract_key_terms()
        |> String.split()
        |> Enum.take(3)
        |> Enum.join(" ")
        clean_terms = clean_search_terms_for_display(search_terms)
        Logger.debug("Strategy 2: Manual fallback with loose search: '#{search_terms}'")
        OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, 2, "Manual Fallback", clean_terms)
        
        # Use loose search for manual fallback
        options_with_mode = Keyword.put(options, :search_mode, :loose)
        search_questions_with_params(search_terms, options_with_mode)
    end
  end
  
  defp search_with_llm_alternative_query(query, failed_attempts, options) do
    user_id = Keyword.get(options, :user_id, "demo_user")
    OracleSage.SearchProgress.broadcast_llm_request(user_id, :alternative)
    
    case OracleSage.LLMClient.generate_alternative_search_query(query, failed_attempts) do
      {:ok, alternative_query} ->
        clean_terms = clean_search_terms_for_display(alternative_query)
        Logger.debug("Strategy 3: LLM alternative query with loose search: '#{alternative_query}'")
        OracleSage.SearchProgress.broadcast_llm_response(user_id, :alternative, clean_terms)
        OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, 3, "AI Alternative", clean_terms)
        
        # Use loose search for alternative terms
        options_with_mode = Keyword.put(options, :search_mode, :loose)
        search_questions_with_params(alternative_query, options_with_mode)
      
      {:error, _reason} ->
        # Final fallback to language-based search
        language = extract_programming_language(query)
        search_terms = if language != "", do: language, else: "programming"
        clean_terms = clean_search_terms_for_display(search_terms)
        Logger.debug("Strategy 3: Language fallback with loose search: '#{search_terms}'")
        OracleSage.SearchProgress.broadcast_strategy_attempt(user_id, 3, "Language Fallback", clean_terms)
        
        # Use loose search for language fallback
        options_with_mode = Keyword.put(options, :search_mode, :loose)
        search_questions_with_params(search_terms, options_with_mode)
    end
  end
  
  defp search_questions_with_params(search_terms, options) do
    user_id = Keyword.get(options, :user_id, "demo_user")
    search_mode = Keyword.get(options, :search_mode, :strict)
    
    # Try different search approaches based on mode
    params = case search_mode do
      :strict ->
        # Exact title match (current approach)
        %{
          "intitle" => search_terms,
          "site" => @site,
          "order" => "desc",
          "sort" => "relevance",
          "pagesize" => Keyword.get(options, :pagesize, 5),
          "filter" => "withbody"
        }
      
      :loose ->
        # Use fewer words in title for looser matching
        words = String.split(search_terms, " ")
        # Take first 1-2 most important words for title search
        main_words = case length(words) do
          1 -> List.first(words)
          2 -> Enum.join(words, " ")
          _ -> Enum.take(words, 2) |> Enum.join(" ")
        end
        
        %{
          "intitle" => main_words,
          "site" => @site,
          "order" => "desc", 
          "sort" => "relevance",
          "pagesize" => Keyword.get(options, :pagesize, 5),
          "filter" => "withbody"
        }
      
      :tags ->
        # Search by individual words as tags
        words = String.split(search_terms, " ")
        main_word = List.first(words) || search_terms
        %{
          "tagged" => main_word,
          "intitle" => search_terms,
          "site" => @site,
          "order" => "desc",
          "sort" => "relevance", 
          "pagesize" => Keyword.get(options, :pagesize, 5),
          "filter" => "withbody"
        }
    end
    
    # Build the actual URL that will be sent to Stack Overflow
    query_string = URI.encode_query(params)
    full_url = "#{@base_url}/search?#{query_string}"
    clean_terms = clean_search_terms_for_display(search_terms)
    
    # Log the API call details
    log_stackoverflow_api_call("search", full_url, params, search_terms)
    
    OracleSage.SearchProgress.broadcast_stackoverflow_request(user_id, clean_terms, full_url)
    
    start_time = System.monotonic_time(:millisecond)
    
    case HTTPoison.get("#{@base_url}/search", [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        case Jason.decode(body) do
          {:ok, %{"items" => items} = response} ->
            log_stackoverflow_api_response("search", 200, length(items), response_time, search_terms)
            OracleSage.SearchProgress.broadcast_stackoverflow_response(user_id, true, length(items))
            {:ok, response}
          {:ok, response} ->
            log_stackoverflow_api_response("search", 200, 0, response_time, search_terms)
            OracleSage.SearchProgress.broadcast_stackoverflow_response(user_id, true, 0)
            {:ok, response}
          {:error, _} = error ->
            log_stackoverflow_api_response("search", 200, 0, response_time, search_terms, "JSON decode error")
            OracleSage.SearchProgress.broadcast_stackoverflow_response(user_id, false, 0)
            error
        end
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        log_stackoverflow_api_response("search", status_code, 0, response_time, search_terms, "HTTP #{status_code}: #{String.slice(body, 0, 100)}")
        OracleSage.SearchProgress.broadcast_stackoverflow_response(user_id, false, 0)
        {:error, "API request failed with status: #{status_code}"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        response_time = System.monotonic_time(:millisecond) - start_time
        log_stackoverflow_api_response("search", 0, 0, response_time, search_terms, "HTTP Error: #{reason}")
        OracleSage.SearchProgress.broadcast_stackoverflow_response(user_id, false, 0)
        {:error, "HTTP request failed: #{reason}"}
    end
  end
  
  defp extract_programming_language(query) do
    language_keywords = ~w(python javascript java ruby go rust php swift kotlin scala)
    
    query
    |> String.downcase()
    |> String.split()
    |> Enum.find("", fn word -> word in language_keywords end)
  end

  defp decode_html_entities(nil), do: ""
  defp decode_html_entities(text) when is_binary(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&copy;", "©")
    |> String.replace("&reg;", "®")
    # Add more common HTML entities as needed
  end
  defp decode_html_entities(text), do: text

  def format_answer(answer) do
    %{
      "answer_id" => answer["answer_id"],
      "score" => answer["score"],
      "is_accepted" => answer["is_accepted"],
      "body" => decode_html_entities(answer["body"]),
      "creation_date" => answer["creation_date"],
      "last_activity_date" => answer["last_activity_date"],
      "owner" => %{
        "display_name" => get_in(answer, ["owner", "display_name"]),
        "reputation" => get_in(answer, ["owner", "reputation"])
      }
    }
  end

  def format_question(question) do
    %{
      "question_id" => question["question_id"],
      "title" => decode_html_entities(question["title"]),
      "body" => decode_html_entities(question["body"]),
      "score" => question["score"],
      "view_count" => question["view_count"],
      "answer_count" => question["answer_count"],
      "creation_date" => question["creation_date"],
      "last_activity_date" => question["last_activity_date"],
      "tags" => question["tags"],
      "owner" => %{
        "display_name" => get_in(question, ["owner", "display_name"]),
        "reputation" => get_in(question, ["owner", "reputation"])
      }
    }
  end

  # Comprehensive logging for Stack Overflow API calls
  defp log_stackoverflow_api_call(endpoint, full_url, params, search_context) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    Logger.info("""
    
    ======================== STACKOVERFLOW API CALL ========================
    Timestamp: #{timestamp}
    Endpoint: #{endpoint}
    Search Context: #{search_context}
    Full URL: #{full_url}
    Parameters: #{inspect(params, pretty: true)}
    =====================================================================
    """)
  end

  defp log_stackoverflow_api_response(endpoint, status_code, result_count, response_time_ms, search_context, error_details \\ nil) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    status_emoji = if status_code == 200, do: "✅", else: "❌"
    
    base_log = """
    
    ===================== STACKOVERFLOW API RESPONSE =====================
    Timestamp: #{timestamp}
    #{status_emoji} Endpoint: #{endpoint}
    Search Context: #{search_context}
    Status Code: #{status_code}
    Response Time: #{response_time_ms}ms
    Results Found: #{result_count}
    """
    
    error_log = if error_details do
      "Error Details: #{error_details}\n"
    else
      ""
    end
    
    Logger.info(base_log <> error_log <> "====================================================================\n")
  end
end