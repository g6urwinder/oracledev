import React from 'react';
import { SearchProgressUpdate } from '../hooks/useSearchProgress';

interface SearchProgressProps {
  updates: SearchProgressUpdate[];
  isConnected: boolean;
  isVisible: boolean;
}

const SearchProgress: React.FC<SearchProgressProps> = ({ updates, isConnected, isVisible }) => {
  if (!isVisible || updates.length === 0) {
    return null;
  }

  const getStepIcon = (step: string) => {
    switch (step) {
      case 'start': return '🚀';
      case 'strategy_attempt': return '🔍';
      case 'strategy_result': return '📊';
      case 'llm_request': return '🤖';
      case 'llm_response': return '✨';
      case 'stackoverflow_request': return '📚';
      case 'stackoverflow_response': return '📖';
      case 'complete': return '✅';
      case 'error': return '❌';
      default: return '🔄';
    }
  };

  const getUpdateStyle = (step: string) => {
    switch (step) {
      case 'start':
        return 'progress-start';
      case 'strategy_result':
        return 'progress-strategy';
      case 'llm_request':
      case 'llm_response':
        return 'progress-llm';
      case 'complete':
        return 'progress-complete';
      case 'error':
        return 'progress-error';
      default:
        return 'progress-default';
    }
  };

  return (
    <div className="search-progress">
      <div className="progress-header">
        <h3>🔍 Search Progress</h3>
        <div className={`connection-status ${isConnected ? 'connected' : 'disconnected'}`}>
          {isConnected ? '🟢 Connected' : '🔴 Disconnected'}
        </div>
      </div>
      
      <div className="progress-timeline">
        {updates.map((update, index) => (
          <div key={index} className={`progress-item ${getUpdateStyle(update.step)}`}>
            <div className="progress-icon">
              {getStepIcon(update.step)}
            </div>
            <div className="progress-content">
              <div className="progress-message">{update.message}</div>
              
              {/* Show search terms */}
              {update.details?.search_terms && (
                <div className="progress-details">
                  Search Terms: "{update.details.search_terms}"
                </div>
              )}
              
              {/* Show AI transformation results */}
              {update.details?.result && update.step === 'llm_response' && (
                <div className="progress-details ai-transformation">
                  AI Result: "{update.details.result}"
                </div>
              )}
              
              {/* Show Stack Overflow API URL */}
              {update.details?.api_url && (
                <div className="progress-details api-url">
                  <details>
                    <summary>Stack Overflow API Request</summary>
                    <a href={update.details.api_url} target="_blank" rel="noopener noreferrer">
                      {update.details.api_url}
                    </a>
                  </details>
                </div>
              )}
              
              {/* Show attempt number */}
              {update.details?.attempt && (
                <div className="progress-details">
                  Attempt #{update.details.attempt} - {update.details?.strategy}
                </div>
              )}
              
              {/* Show result count */}
              {update.details?.count !== undefined && (
                <div className="progress-details">
                  Results: {update.details.count}
                </div>
              )}
              
              <div className="progress-timestamp">
                {new Date(update.timestamp).toLocaleTimeString()}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default SearchProgress;