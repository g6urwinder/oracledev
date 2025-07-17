defmodule OracleSage.LLMClient do
  @moduledoc """
  Client for interacting with local LLM models via OpenAI-compatible API.
  Supports Ollama, LM Studio, and other OpenAI-compatible local servers.
  """
  require Logger

  @default_base_url "http://localhost:11434"  # Ollama default
  @default_model "llama3.2"  # Default model
  @timeout 60_000  # 60 seconds timeout

  # Build context string about previous failed attempts
  defp build_failure_context([]), do: ""
  defp build_failure_context(failed_attempts) do
    failed_terms = failed_attempts
    |> Enum.map(fn attempt -> attempt.terms end)
    |> Enum.join("\", \"")
    
    "\nThese search terms failed (found no results): \"#{failed_terms}\"\nAvoid these exact terms and try different words."
  end

  def generate_related_questions(question, options \\ []) do
    base_url = get_base_url(options)
    model = get_model(options)

    payload = %{
      model: model,
      messages: [
        %{
          role: "user",
          content: "Generate 4 short related questions about: #{question["title"]}\n\nRules:\n- Keep each question under 50 characters\n- Use simple terms\n- Make them searchable on Stack Overflow\n\nFormat:\n1. Question 1\n2. Question 2\n3. Question 3\n4. Question 4"
        }
      ],
      temperature: 0.3,
      max_tokens: 100
    }

    case make_request(base_url, payload) do
      {:ok, response} ->
        Logger.debug("LLM Response for related questions: #{response}")
        parse_related_questions(response)

      {:error, reason} ->
        Logger.error("LLM failed for related questions: #{reason}")
        # Instead of fallback, try a simpler LLM request
        retry_simple_related_questions(question, base_url, model)
    end
  end

  def rerank_answers(question, answers, options \\ []) do
    base_url = get_base_url(options)
    model = get_model(options)

    prompt = build_rerank_prompt(question, answers)

    payload = %{
      model: model,
      messages: [
        %{
          role: "system",
          content: "You are an expert programming assistant. Analyze Stack Overflow answers and provide: 1) Reranked answer IDs in order, 2) Brief explanation for each answer's relevance. Format: ID:explanation"
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.1,
      max_tokens: 1500
    }

    case make_request(base_url, payload) do
      {:ok, response} ->
        parse_rerank_with_explanations(response, answers)

      {:error, _reason} ->
        # Fallback to original order if LLM fails
        {:ok, add_default_explanations(answers)}
    end
  end

  defp get_base_url(options) do
    Keyword.get(options, :base_url, 
      System.get_env("LLM_BASE_URL", @default_base_url)
    )
  end

  defp get_model(options) do
    Keyword.get(options, :model, 
      System.get_env("LLM_MODEL", @default_model)
    )
  end

  defp build_rerank_prompt(question, answers) do
    answer_text = answers
    |> Enum.with_index()
    |> Enum.map(fn {answer, index} ->
      """
      Answer #{index + 1} (ID: #{answer["answer_id"]}) - Score: #{answer["score"]}:
      #{String.slice(answer["body"], 0, 400)}...
      """
    end)
    |> Enum.join("\n\n")

    """
    Question: #{question["title"]}

    Analyze these Stack Overflow answers and provide:
    1. Reranked answer IDs in order of relevance
    2. Brief explanation for each answer's relevance

    #{answer_text}

    Format your response as:
    ID1: Brief explanation why this answer is most relevant
    ID2: Brief explanation why this answer is second most relevant
    ID3: Brief explanation why this answer is third most relevant

    Focus on: accuracy, relevance, code quality, and helpfulness.
    Keep explanations under 10 words each.
    """
  end

  defp make_request(base_url, payload) do
    # Use Ollama's native API instead of OpenAI-compatible endpoint
    url = "#{base_url}/api/generate"
    headers = [{"Content-Type", "application/json"}]
    
    # Convert OpenAI format to Ollama format
    ollama_payload = %{
      model: payload[:model],
      prompt: get_prompt_from_messages(payload[:messages]),
      stream: false,
      options: %{
        temperature: payload[:temperature] || 0.3,
        num_predict: payload[:max_tokens] || 150
      }
    }

    case HTTPoison.post(url, Jason.encode!(ollama_payload), headers, timeout: @timeout, recv_timeout: @timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"response" => content}} ->
            {:ok, content}
          {:error, _} ->
            {:error, "Failed to parse Ollama response"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, "Ollama API returned #{status_code}: #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  defp get_prompt_from_messages(messages) do
    messages
    |> Enum.map(fn 
      %{role: "system", content: content} -> "System: #{content}\n"
      %{role: "user", content: content} -> "User: #{content}\n"
      %{role: "assistant", content: content} -> "Assistant: #{content}\n"
    end)
    |> Enum.join()
  end

  defp parse_rerank_with_explanations(response, original_answers) do
    # Try to parse ID:explanation format
    lines = response
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line -> String.contains?(line, ":") end)

    explanations = lines
    |> Enum.map(fn line ->
      case String.split(line, ":", parts: 2) do
        [id_str, explanation] ->
          case Integer.parse(String.trim(id_str)) do
            {id, _} -> {id, String.trim(explanation)}
            _ -> nil
          end
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.into(%{})

    # Reorder answers and add explanations
    reranked_answers = explanations
    |> Enum.map(fn {id, explanation} ->
      case Enum.find(original_answers, fn answer -> 
        String.to_integer(to_string(answer["answer_id"])) == id
      end) do
        nil -> nil
        answer -> Map.put(answer, "ai_explanation", explanation)
      end
    end)
    |> Enum.filter(& &1)

    # Add any missing answers at the end with default explanations
    missing_answers = original_answers -- reranked_answers
    |> Enum.map(fn answer ->
      Map.put(answer, "ai_explanation", "Good alternative solution")
    end)

    final_answers = reranked_answers ++ missing_answers

    {:ok, final_answers}
  rescue
    _ ->
      # Fallback to original order with default explanations
      {:ok, add_default_explanations(original_answers)}
  end

  defp add_default_explanations(answers) do
    answers
    |> Enum.with_index()
    |> Enum.map(fn {answer, index} ->
      explanation = case index do
        0 -> "Highest voted solution"
        1 -> "Alternative approach"
        2 -> "Additional perspective"
        _ -> "Worth considering"
      end
      Map.put(answer, "ai_explanation", explanation)
    end)
  end

  defp parse_related_questions(response) do
    questions = response
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line -> 
      String.match?(line, ~r/^\d+\./) 
    end)
    |> Enum.map(fn line ->
      line
      |> String.replace(~r/^\d+\.\s*/, "")
      |> String.trim()
      |> String.slice(0, 80)  # Limit to 80 characters
    end)
    |> Enum.filter(fn q -> String.length(q) > 10 and String.length(q) <= 80 end)
    |> Enum.take(4)  # Ensure we only take 4 questions

    {:ok, questions}
  rescue
    _ ->
      {:ok, []}
  end

  def simplify_search_query(original_query, failed_attempts \\ [], options \\ []) do
    base_url = get_base_url(options)
    model = get_model(options)
    
    # Build context about what failed
    context = build_failure_context(failed_attempts)
    
    payload = %{
      model: model,
      messages: [
        %{
          role: "user",
          content: "Extract DIFFERENT key terms. Return ONLY valid JSON, no explanations.\n\nOriginal query: \"#{original_query}\"\n#{context}\n\nTry different, shorter terms that might find results:\n{\"terms\": \"different key words\"}"
        }
      ],
      temperature: 0.2,
      max_tokens: 30
    }
    
    case make_request(base_url, payload) do
      {:ok, response} ->
        case parse_json_terms(response) do
          {:ok, terms} ->
            Logger.debug("LLM simplified '#{original_query}' → '#{terms}'")
            {:ok, terms}
          {:error, _} ->
            # Fallback to manual extraction
            fallback_terms = OracleSage.StackOverflowAPI.extract_key_terms(original_query)
            Logger.warning("LLM JSON parsing failed, using fallback: '#{fallback_terms}'")
            {:ok, fallback_terms}
        end
      
      {:error, reason} ->
        Logger.error("LLM simplification failed: #{reason}")
        {:error, reason}
    end
  end
  
  def generate_alternative_search_query(original_query, failed_attempts \\ [], options \\ []) do
    base_url = get_base_url(options)
    model = get_model(options)
    
    # Build context about what failed
    context = build_failure_context(failed_attempts)
    
    payload = %{
      model: model,
      messages: [
        %{
          role: "user", 
          content: "Generate COMPLETELY different alternative terms using synonyms. Return ONLY valid JSON, no explanations.\n\nOriginal query: \"#{original_query}\"\n#{context}\n\nTry totally different approach with synonyms:\n{\"terms\": \"synonym alternative words\"}"
        }
      ],
      temperature: 0.5,
      max_tokens: 30
    }
    
    case make_request(base_url, payload) do
      {:ok, response} ->
        case parse_json_terms(response) do
          {:ok, terms} ->
            Logger.debug("LLM alternative for '#{original_query}' → '#{terms}'")
            {:ok, terms}
          {:error, _} ->
            # Fallback to manual extraction
            fallback_terms = OracleSage.StackOverflowAPI.extract_key_terms(original_query)
            Logger.warning("LLM alternative JSON parsing failed, using fallback: '#{fallback_terms}'")
            {:ok, fallback_terms}
        end
      
      {:error, reason} ->
        Logger.error("LLM alternative generation failed: #{reason}")
        {:error, reason}
    end
  end

  # Parse JSON response to extract search terms
  defp parse_json_terms(response) do
    # Try to extract JSON from response, handling malformed responses
    cleaned_response = response
    |> String.trim()
    |> String.replace(~r/^[^{]*/, "")  # Remove text before first {
    |> String.replace(~r/}[^}]*$/, "}") # Remove text after last }
    
    case Jason.decode(cleaned_response) do
      {:ok, %{"terms" => terms}} when is_binary(terms) ->
        clean_terms = terms
        |> String.trim()
        |> String.downcase()
        |> String.slice(0, 50)  # Limit length
        |> String.trim()
        
        if String.length(clean_terms) >= 3 do
          {:ok, clean_terms}
        else
          {:error, "Terms too short"}
        end
      
      {:ok, _data} ->
        {:error, "Invalid JSON structure"}
      
      {:error, _reason} ->
        {:error, "JSON decode failed"}
    end
  rescue
    _error ->
      {:error, "JSON parsing exception"}
  end

  def detect_programming_language(query, options \\ []) do
    base_url = get_base_url(options)
    model = get_model(options)
    
    payload = %{
      model: model,
      messages: [
        %{
          role: "user",
          content: "Detect programming language. Return ONLY valid JSON, no explanations.\n\nQuery: \"#{query}\"\n\nReturn this exact format:\n{\"language\": \"language_name\"}"
        }
      ],
      temperature: 0.1,
      max_tokens: 20
    }
    
    case make_request(base_url, payload) do
      {:ok, response} ->
        case parse_json_language(response) do
          {:ok, language} ->
            Logger.debug("LLM detected language: '#{language}' from '#{query}'")
            {:ok, language}
          {:error, _} ->
            Logger.warning("LLM language detection JSON parsing failed, using fallback")
            {:error, "Language detection failed"}
        end
      
      {:error, reason} ->
        Logger.error("LLM language detection failed: #{reason}")
        {:error, reason}
    end
  end

  # Parse JSON response to extract programming language
  defp parse_json_language(response) do
    cleaned_response = response
    |> String.trim()
    |> String.replace(~r/^[^{]*/, "")  # Remove text before first {
    |> String.replace(~r/}[^}]*$/, "}") # Remove text after last }
    
    case Jason.decode(cleaned_response) do
      {:ok, %{"language" => language}} when is_binary(language) ->
        clean_language = language
        |> String.trim()
        |> String.downcase()
        |> String.replace(~r/[^a-z]/, "")
        |> String.slice(0, 20)
        
        # Validate it's a real programming language
        valid_languages = ~w(javascript python java elixir ruby go rust php swift kotlin scala typescript c cpp)
        
        if clean_language in valid_languages do
          {:ok, clean_language}
        else
          {:error, "Invalid language"}
        end
      
      {:ok, _data} ->
        {:error, "Invalid JSON structure"}
      
      {:error, _reason} ->
        {:error, "JSON decode failed"}
    end
  rescue
    _ ->
      {:error, "Language JSON parsing exception"}
  end

  defp retry_simple_related_questions(question, base_url, model) do
    simple_prompt = "Generate 4 related questions about: #{question["title"]}"
    
    payload = %{
      model: model,
      messages: [
        %{
          role: "user",
          content: simple_prompt
        }
      ],
      temperature: 0.5,
      max_tokens: 200
    }

    case make_request(base_url, payload) do
      {:ok, response} ->
        Logger.debug("Simple LLM Response: #{response}")
        parse_related_questions(response)
      
      {:error, reason} ->
        Logger.error("Simple LLM also failed: #{reason}")
        {:ok, ["Related question 1", "Related question 2", "Related question 3", "Related question 4"]}
    end
  end

end