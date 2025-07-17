import React, { useState, useEffect } from 'react';

interface RecentQuestion {
  id: number;
  question: string;
  searched_at: string;
  user_id: string;
  inserted_at: string;
  updated_at: string;
}

interface RecentQuestionsProps {
  userId: string;
  onQuestionSelect: (question: string) => void;
}

const RecentQuestions: React.FC<RecentQuestionsProps> = ({ userId, onQuestionSelect }) => {
  const [questions, setQuestions] = useState<RecentQuestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRecentQuestions = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await fetch(`http://localhost:4000/api/recent_questions/${userId}`);
      
      if (!response.ok) {
        throw new Error('Failed to fetch recent questions');
      }
      
      const data = await response.json();
      
      if (data.success) {
        setQuestions(data.questions || []);
      } else {
        setError('Failed to load recent questions');
      }
    } catch (err) {
      setError('Unable to connect to server');
      console.error('Error fetching recent questions:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRecentQuestions();
  }, [userId]);

  const formatDate = (dateString: string): string => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMinutes = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMinutes < 1) return 'Just now';
    if (diffMinutes < 60) return `${diffMinutes}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    
    return date.toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric' 
    });
  };

  const truncateQuestion = (question: string, maxLength: number = 60): string => {
    if (question.length <= maxLength) return question;
    return question.substring(0, maxLength) + '...';
  };

  const handleQuestionClick = (question: string) => {
    onQuestionSelect(question);
  };

  if (loading) {
    return (
      <div className="recent-questions">
        <h3>Recent Questions</h3>
        <div className="loading" style={{ padding: '20px' }}>
          <span className="loading-spinner"></span>
          Loading...
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="recent-questions">
        <h3>Recent Questions</h3>
        <div className="error" style={{ fontSize: '0.9rem', padding: '12px' }}>
          {error}
        </div>
        <button 
          onClick={fetchRecentQuestions}
          style={{
            background: '#f48024',
            color: 'white',
            border: 'none',
            padding: '8px 16px',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '0.9rem'
          }}
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="recent-questions">
      <h3>Recent Questions</h3>
      
      {questions.length === 0 ? (
        <div style={{ 
          textAlign: 'center', 
          padding: '20px', 
          color: '#6a737c',
          fontSize: '0.9rem' 
        }}>
          <p>No recent questions yet.</p>
          <p>Search for a question to get started!</p>
        </div>
      ) : (
        <ul className="recent-list">
          {questions.map((question) => (
            <li key={question.id} className="recent-item">
              <div 
                className="recent-question clickable"
                onClick={() => handleQuestionClick(question.question)}
                title={`Click to search: ${question.question}`}
              >
                🔍 {truncateQuestion(question.question)}
              </div>
              <div className="recent-date">
                {formatDate(question.searched_at)}
              </div>
            </li>
          ))}
        </ul>
      )}
      
      <div style={{ 
        marginTop: '20px', 
        padding: '12px', 
        backgroundColor: '#f8f9fa', 
        borderRadius: '6px',
        fontSize: '0.8rem',
        color: '#6a737c'
      }}>
        <strong>💡 Tip:</strong> Your last {questions.length} questions are cached for quick access.
      </div>
    </div>
  );
};

export default RecentQuestions;