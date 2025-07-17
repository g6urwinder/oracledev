defmodule OracleSage.Instrumentation do
  @moduledoc """
  OpenTelemetry instrumentation for Oracle Sage application.
  Provides tracing for critical operations like search and LLM requests.
  """
  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  @tracer_id __MODULE__

  @doc """
  Wraps a function call with OpenTelemetry tracing.
  """
  def with_span(span_name, attributes \\ %{}, func) do
    Tracer.with_span @tracer_id, span_name, attributes do
      try do
        result = func.()
        Tracer.set_attribute("operation.success", true)
        result
      rescue
        error ->
          Tracer.set_attribute("operation.success", false)
          Tracer.set_attribute("error.type", error.__struct__)
          Tracer.set_attribute("error.message", Exception.message(error))
          Tracer.record_exception(error)
          Logger.error("Operation failed in span #{span_name}: #{Exception.message(error)}")
          reraise error, __STACKTRACE__
      end
    end
  end

  @doc """
  Traces a Stack Overflow API call
  """
  def trace_stackoverflow_api(operation, search_terms, func) do
    attributes = %{
      "stackoverflow.operation" => operation,
      "stackoverflow.search_terms" => search_terms,
      "http.client" => "httpoison"
    }
    
    with_span("stackoverflow.api.#{operation}", attributes, func)
  end

  @doc """
  Traces an LLM operation
  """
  def trace_llm_operation(operation, model, query \\ nil, func) do
    attributes = %{
      "llm.operation" => operation,
      "llm.model" => model,
      "llm.query_length" => if(query, do: String.length(query), else: 0)
    }
    
    with_span("llm.#{operation}", attributes, func)
  end

  @doc """
  Traces a search strategy attempt
  """
  def trace_search_strategy(strategy_name, attempt_number, search_terms, func) do
    attributes = %{
      "search.strategy" => strategy_name,
      "search.attempt" => attempt_number,
      "search.terms" => search_terms
    }
    
    with_span("search.strategy.#{String.downcase(strategy_name)}", attributes, func)
  end

  @doc """
  Traces database operations
  """
  def trace_database_operation(operation, table \\ nil, func) do
    attributes = %{
      "db.operation" => operation,
      "db.table" => table || "unknown"
    }
    
    with_span("db.#{operation}", attributes, func)
  end

  @doc """
  Add user context to current span
  """
  def add_user_context(user_id) when is_binary(user_id) do
    Tracer.set_attribute("user.id", user_id)
  end
  def add_user_context(_), do: :ok

  @doc """
  Add search context to current span
  """
  def add_search_context(query, search_mode) do
    Tracer.set_attribute("search.query", query)
    Tracer.set_attribute("search.mode", search_mode)
    Tracer.set_attribute("search.query_length", String.length(query))
  end

  @doc """
  Record search results metrics
  """
  def record_search_results(question_count, answer_count, strategy_used) do
    Tracer.set_attribute("search.questions_found", question_count)
    Tracer.set_attribute("search.answers_found", answer_count)
    Tracer.set_attribute("search.final_strategy", strategy_used)
  end
end