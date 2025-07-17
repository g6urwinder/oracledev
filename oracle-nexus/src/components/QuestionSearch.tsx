import React, { useState } from 'react';

interface QuestionSearchProps {
  onSearch: (query: string, useReranking: boolean, searchMode?: 'strict' | 'loose') => void;
  loading: boolean;
}

const QuestionSearch: React.FC<QuestionSearchProps> = ({ onSearch, loading }) => {
  const [query, setQuery] = useState('');
  const [searchMode, setSearchMode] = useState<'strict' | 'loose'>('strict');

  // Popular programming questions for quick access
  const popularQuestions = [
    "How to reverse array in javascript using lodash",
    "Best way to sort array of objects in python",
    "How to remove duplicates from array in javascript", 
    "Convert string to array in python",
    "How to merge two arrays in javascript",
    "Python list comprehension with conditions",
    "How to find element in array javascript",
    "Remove item from array by value javascript"
  ];

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (query.trim()) {
      onSearch(query.trim(), true, searchMode);
    }
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  const handleQuickSearch = (question: string) => {
    setQuery(question);
    onSearch(question, true, searchMode);
  };

  return (
    <div className="search-form">
      <h2>Ask a Question</h2>
      
      {/* Popular Questions Section */}
      <div className="popular-questions">
        <h3>🔥 Popular Questions</h3>
        <div className="popular-questions-grid">
          {popularQuestions.map((question, index) => (
            <button
              key={index}
              className="popular-question-btn"
              onClick={() => handleQuickSearch(question)}
              disabled={loading}
              title={`Click to search: ${question}`}
            >
              {question}
            </button>
          ))}
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="search-input-group">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyPress={handleKeyPress}
            placeholder="Search for programming questions... (e.g., 'javascript array methods', 'python loops')"
            className="search-input"
            disabled={loading}
          />
          
          <div className="search-controls">
            <button 
              type="submit" 
              className="search-button"
              disabled={loading || !query.trim()}
            >
              {loading ? (
                <>
                  <span className="loading-spinner"></span>
                  Searching...
                </>
              ) : (
                'Search Questions'
              )}
            </button>
            
            <div className="search-options">
              <div className="search-mode-section">
                <label className="search-mode-label">Search Mode:</label>
                <div className="search-mode-options">
                  <label className="search-mode-option">
                    <input
                      type="radio"
                      name="searchMode"
                      value="strict"
                      checked={searchMode === 'strict'}
                      onChange={(e) => setSearchMode(e.target.value as 'strict' | 'loose')}
                      disabled={loading}
                    />
                    <span className="option-text">
                      <strong>Strict</strong> - Exact title match
                    </span>
                  </label>
                  <label className="search-mode-option">
                    <input
                      type="radio"
                      name="searchMode"
                      value="loose"
                      checked={searchMode === 'loose'}
                      onChange={(e) => setSearchMode(e.target.value as 'strict' | 'loose')}
                      disabled={loading}
                    />
                    <span className="option-text">
                      <strong>Loose</strong> - Broader search
                    </span>
                  </label>
                </div>
              </div>
              
            </div>
          </div>
        </div>
      </form>
      
      {/* Search Mode Explanation */}
      <div className="search-mode-explanation">
        <div className="explanation-section">
          <h4>🎯 Search Modes</h4>
          <div className="mode-explanations">
            <div className="mode-explanation">
              <strong>Strict Mode (Default):</strong> 
              <span>Searches for exact phrase matches in question titles. More precise but may return fewer results.</span>
            </div>
            <div className="mode-explanation">
              <strong>Loose Mode:</strong> 
              <span>Uses partial title matching for broader results. Enable this if strict mode finds too few questions.</span>
            </div>
          </div>
        </div>
      </div>

    </div>
  );
};

export default QuestionSearch;