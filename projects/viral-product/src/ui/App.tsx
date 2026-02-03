import React, { useEffect } from 'react'
import { useAppStore } from './store'
import { Sidebar } from './components/Sidebar'
import { Timeline } from './components/Timeline'
import { RequestDetails } from './components/RequestDetails'
import { ProxyControls } from './components/ProxyControls'
import { WSMessage } from '../types'

function App() {
  const { 
    currentSession, 
    addRequest, 
    updateResponse, 
    setSessions,
    setRequests
  } = useAppStore()

  useEffect(() => {
    // Load sessions on app start
    loadSessions()
    
    // Set up WebSocket connection for real-time updates
    const ws = window.electronAPI.connectWebSocket()
    
    ws.onmessage = (event) => {
      const message: WSMessage = JSON.parse(event.data)
      
      if (message.type === 'request') {
        addRequest(message.data as any)
      } else if (message.type === 'response') {
        updateResponse(message.data as any)
      }
    }

    return () => {
      ws.close()
    }
  }, [])

  useEffect(() => {
    // Load requests for current session
    if (currentSession) {
      loadSessionRequests(currentSession.id)
    }
  }, [currentSession])

  const loadSessions = async () => {
    try {
      const sessions = await window.electronAPI.getSessions()
      setSessions(sessions)
    } catch (error) {
      console.error('Failed to load sessions:', error)
    }
  }

  const loadSessionRequests = async (sessionId: string) => {
    try {
      const requests = await window.electronAPI.getSessionRequests(sessionId)
      
      // Load responses for each request
      const requestsWithResponses = await Promise.all(
        requests.map(async (request) => {
          const response = await window.electronAPI.getResponse(request.id)
          return { request, response }
        })
      )
      
      setRequests(requestsWithResponses)
    } catch (error) {
      console.error('Failed to load session requests:', error)
    }
  }

  return (
    <div className="flex h-screen bg-gray-50">
      {/* Sidebar */}
      <Sidebar />
      
      {/* Main Content */}
      <div className="flex-1 flex flex-col">
        {/* Header with Proxy Controls */}
        <div className="bg-white border-b border-gray-200 p-4">
          <ProxyControls />
        </div>
        
        {/* Content Area */}
        <div className="flex-1 flex">
          {/* Timeline */}
          <div className="flex-1 border-r border-gray-200">
            <Timeline />
          </div>
          
          {/* Request Details */}
          <div className="w-1/3 bg-white">
            <RequestDetails />
          </div>
        </div>
      </div>
    </div>
  )
}

export default App