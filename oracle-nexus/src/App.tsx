import React, { useState } from 'react';
import QuestionSearch from './components/QuestionSearch';
import AnswerDisplay from './components/AnswerDisplay';
import RecentQuestions from './components/RecentQuestions';
import SearchProgress from './components/SearchProgress';
import { useSearchProgress } from './hooks/useSearchProgress';
import './App.css';

export interface Question {
  question_id: number;
  title: string;
  body: string;
  score: number;
  view_count: number;
  answer_count: number;
  creation_date: number;
  last_activity_date: number;
  tags: string[];
  owner: {
    display_name: string;
    reputation: number;
  };
}

export interface Answer {
  answer_id: number;
  score: number;
  is_accepted: boolean;
  body: string;
  creation_date: number;
  last_activity_date: number;
  owner: {
    display_name: string;
    reputation: number;
  };
  ai_explanation?: string;
}

export interface SearchResult {
  success: boolean;
  question: Question;
  original_answers: Answer[];
  reranked_answers: Answer[];
  total_answers: number;
  warning?: string;
  related_questions?: string[];
  search_info?: string;
}

function App() {
  const [searchResult, setSearchResult] = useState<SearchResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [userId] = useState('demo_user'); // In real app, this would come from auth
  const { updates, isConnected, clearUpdates } = useSearchProgress(userId);

  const handleSearch = async (query: string, useReranking: boolean = false, searchMode: 'strict' | 'loose' = 'strict') => {
    setLoading(true);
    clearUpdates(); // Clear previous search progress
    
    try {
      const endpoint = useReranking ? '/api/search_rerank' : '/api/search';
      const response = await fetch(`http://localhost:4000${endpoint}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          q: query,
          user_id: userId,
          search_mode: searchMode,
        }),
      });

      const data = await response.json();
      setSearchResult(data);
    } catch (error) {
      console.error('Search failed:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleQuestionSelect = (question: string) => {
    // Auto-search when recent question is selected
    handleSearch(question, true); // Default to using AI reranking
  };

  return (
    <div className="App">
      <header className="header">
        <div className="container">
          <div className="header-content">
            <h1 className="logo">
              <span className="logo-text">Oracle</span>
              <span className="logo-accent">Nexus</span>
            </h1>
            <p className="tagline">Where developers find their answers</p>
          </div>
        </div>
      </header>

      <main className="main">
        <div className="container">
          <div className="layout">
            <aside className="sidebar">
              <RecentQuestions 
                userId={userId} 
                onQuestionSelect={handleQuestionSelect}
              />
            </aside>
            
            <div className="content">
              <QuestionSearch 
                onSearch={handleSearch}
                loading={loading}
              />
              
              <SearchProgress
                updates={updates}
                isConnected={isConnected}
                isVisible={loading || updates.length > 0}
              />
              
              {/* Bottom loader when searching and no results yet */}
              {loading && !searchResult && (
                <div className="search-progress">
                  <div className="bottom-loader">
                    <div className="loading">
                      <span className="loading-spinner"></span>
                      <div className="loading-text">
                        <p>🔍 AI is searching Stack Overflow...</p>
                        <p style={{ fontSize: '0.9rem', marginTop: '8px' }}>
                          Trying different search strategies to find the best answers
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              )}
              
              {searchResult && (
                <AnswerDisplay 
                  result={searchResult}
                  loading={loading}
                  onRelatedQuestionClick={handleQuestionSelect}
                />
              )}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App;