import { useState, useEffect, useRef } from 'react';

export interface SearchProgressUpdate {
  step: string;
  message: string;
  details: any;
  timestamp: string;
}

export const useSearchProgress = (userId: string) => {
  const [updates, setUpdates] = useState<SearchProgressUpdate[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const socketRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    // Create WebSocket connection
    const wsUrl = `ws://localhost:4000/socket/websocket`;
    const socket = new WebSocket(wsUrl);
    socketRef.current = socket;

    socket.onopen = () => {
      console.log('WebSocket connected');
      setIsConnected(true);
      
      // Join the search channel
      const joinMessage = {
        topic: `search:${userId}`,
        event: 'phx_join',
        payload: {},
        ref: 'search_join'
      };
      socket.send(JSON.stringify(joinMessage));
    };

    socket.onclose = () => {
      console.log('WebSocket disconnected');
      setIsConnected(false);
    };

    socket.onerror = (error) => {
      console.error('WebSocket error:', error);
      setIsConnected(false);
    };

    socket.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        
        if (message.event === 'search_update' && message.topic === `search:${userId}`) {
          const update: SearchProgressUpdate = message.payload;
          console.log('Search update:', update);
          setUpdates(prev => [...prev, update]);
        }
      } catch (error) {
        console.error('Error parsing WebSocket message:', error);
      }
    };

    return () => {
      if (socketRef.current) {
        socketRef.current.close();
      }
    };
  }, [userId]);

  const clearUpdates = () => {
    setUpdates([]);
  };

  return {
    updates,
    isConnected,
    clearUpdates
  };
};