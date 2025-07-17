import React, { useState } from 'react';
import { SearchResult, Answer } from '../App';

interface AnswerDisplayProps {
  result: SearchResult;
  loading: boolean;
  onRelatedQuestionClick: (question: string) => void;
}

const AnswerDisplay: React.FC<AnswerDisplayProps> = ({ result, loading, onRelatedQuestionClick }) => {
  const [activeTab, setActiveTab] = useState<'original' | 'reranked'>('reranked');

  const formatDate = (timestamp: number): string => {
    const date = new Date(timestamp * 1000);
    return date.toLocaleDateString('en-US', { 
      year: 'numeric', 
      month: 'short', 
      day: 'numeric' 
    });
  };

  const formatScore = (score: number): string => {
    if (score > 0) return `+${score}`;
    return score.toString();
  };

  const stripHtml = (html: string): string => {
    const tmp = document.createElement('DIV');
    tmp.innerHTML = html;
    return tmp.textContent || tmp.innerText || '';
  };

  const formatAnswerBody = (body: string): string => {
    // Simple HTML to text conversion for display with better code formatting
    let formatted = stripHtml(body);
    
    // Improve code formatting
    formatted = formatted
      .replace(/\n\n/g, '\n')
      .replace(/::(\w+)/g, '::$1')  // Keep namespace separators clear
      .replace(/(['"])(.*?)\1/g, '$1$2$1')  // Preserve quotes
      .replace(/`([^`]+)`/g, '`$1`');  // Preserve inline code
    
    return formatted.substring(0, 500) + (body.length > 500 ? '...' : '');
  };

  const renderAnswer = (answer: Answer, index: number) => {
    const scoreClass = answer.score > 0 ? 'positive' : answer.score < 0 ? 'negative' : '';
    
    return (
      <div key={answer.answer_id} className="answer-card">
        <div className="answer-header">
          <div className="answer-score">
            <span className={`score-value ${scoreClass}`}>
              {formatScore(answer.score)}
            </span>
            <span>votes</span>
          </div>
          
          <div className="answer-meta">
            <span>#{index + 1}</span>
            {answer.is_accepted && (
              <span className="accepted-badge">✓ Accepted</span>
            )}
            <span>answered {formatDate(answer.creation_date)}</span>
          </div>
        </div>

        {answer.ai_explanation && activeTab === 'reranked' && (
          <div className="ai-explanation">
            <span className="ai-badge">🤖 AI Insight:</span>
            <span className="ai-text">{answer.ai_explanation}</span>
          </div>
        )}
        
        <div className="answer-content">
          <div className="answer-body">
            <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit' }}>
              {formatAnswerBody(answer.body)}
            </pre>
          </div>
          
          <div className="answer-owner">
            <span className="owner-name">{answer.owner.display_name}</span>
            <span className="owner-reputation">
              {answer.owner.reputation?.toLocaleString() || 'N/A'} reputation
            </span>
          </div>
        </div>
      </div>
    );
  };

  if (loading) {
    return (
      <div className="answer-display">
        <div className="loading">
          <span className="loading-spinner"></span>
          Searching for answers...
        </div>
      </div>
    );
  }

  if (!result.success) {
    return (
      <div className="answer-display">
        <div className="error">
          Failed to fetch results. Please try again.
        </div>
        {loading && (
          <div className="bottom-loader">
            <div className="loading">
              <span className="loading-spinner"></span>
              Still searching...
            </div>
          </div>
        )}
      </div>
    );
  }

  const currentAnswers = activeTab === 'original' ? (result.original_answers || []) : (result.reranked_answers || []);
  const hasRerankedAnswers = result.reranked_answers && result.reranked_answers.length > 0;

  return (
    <div className="answer-display">
      <div className="question-header">
        <h1 className="question-title">{result.question?.title || 'Question'}</h1>
        
        <div className="question-meta">
          <span>
            <strong>{result.question?.score || 0}</strong> score
          </span>
          <span>
            <strong>{result.question?.view_count?.toLocaleString() || 'N/A'}</strong> views
          </span>
          <span>
            <strong>{result.total_answers || 0}</strong> answers
          </span>
        </div>
        
        {result.question?.tags && result.question.tags.length > 0 && (
          <div className="question-tags">
            {result.question.tags.map(tag => (
              <span key={tag} className="tag">{tag}</span>
            ))}
          </div>
        )}
      </div>

      {hasRerankedAnswers && (
        <div className="answer-tabs">
          <button
            className={`tab-button ${activeTab === 'reranked' ? 'active' : ''}`}
            onClick={() => setActiveTab('reranked')}
          >
            ✨ AI Re-ranked ({result.reranked_answers?.length || 0})
          </button>
          <button
            className={`tab-button ${activeTab === 'original' ? 'active' : ''}`}
            onClick={() => setActiveTab('original')}
          >
            📋 Original Order ({result.original_answers?.length || 0})
          </button>
        </div>
      )}

      {result.search_info && (
        <div style={{ margin: '16px 24px', padding: '12px', background: '#e8f5e8', color: '#2d5a2d', borderRadius: '6px', fontSize: '0.9rem' }}>
          🔍 {result.search_info}
        </div>
      )}

      {result.warning && (
        <div className="error" style={{ margin: '16px 24px', background: '#fff3cd', color: '#856404', borderColor: '#ffeaa7' }}>
          ⚠️ {result.warning}
        </div>
      )}

      <div className="answers-container">
        {currentAnswers.length === 0 ? (
          <>
            <div style={{ textAlign: 'center', padding: '40px', color: '#6a737c' }}>
              <h3>No answers found</h3>
              <p>This question doesn't have any answers yet.</p>
            </div>
            {loading && (
              <div className="bottom-loader">
                <div className="loading">
                  <span className="loading-spinner"></span>
                  <div className="loading-text">
                    <p>🔍 AI is trying different search strategies...</p>
                    <p style={{ fontSize: '0.9rem', marginTop: '8px' }}>
                      We're searching with alternative terms to find relevant answers
                    </p>
                  </div>
                </div>
              </div>
            )}
          </>
        ) : (
          <>
            <div style={{ marginBottom: '24px', color: '#6a737c' }}>
              <strong>{currentAnswers.length}</strong> answer{currentAnswers.length !== 1 ? 's' : ''} 
              {activeTab === 'reranked' && hasRerankedAnswers && (
                <span style={{ marginLeft: '8px' }}>
                  (reordered by AI for relevance)
                </span>
              )}
            </div>
            
            {currentAnswers.map((answer, index) => renderAnswer(answer, index))}
            
            {/* Related Questions Section */}
            {result.related_questions && result.related_questions.length > 0 && (
              <div className="related-questions-section">
                <h3>💡 Related Questions You Might Ask</h3>
                <div className="related-questions-grid">
                  {result.related_questions.map((question, index) => (
                    <div 
                      key={index}
                      className="related-question-card"
                      onClick={() => onRelatedQuestionClick(question)}
                      title={`Click to search: ${question}`}
                    >
                      <span className="question-icon">❓</span>
                      <span className="question-text">{question}</span>
                      <span className="click-hint">→</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Bottom loader for ongoing search while showing partial results */}
            {loading && (
              <div className="bottom-loader">
                <div className="loading">
                  <span className="loading-spinner"></span>
                  <span>Refining search results...</span>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
};

export default AnswerDisplay;