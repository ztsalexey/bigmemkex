import React, { useState } from 'react'
import { useAppStore } from '../store'
import { Plus, Trash2, Play, Square } from 'lucide-react'

export function Sidebar() {
  const { 
    sessions, 
    currentSession, 
    setCurrentSession, 
    createNewSession, 
    deleteSession,
    proxyConfig,
    setProxyConfig
  } = useAppStore()
  
  const [showNewSession, setShowNewSession] = useState(false)
  const [newSessionName, setNewSessionName] = useState('')
  const [targetUrl, setTargetUrl] = useState(proxyConfig.targetUrl)

  const handleCreateSession = () => {
    if (newSessionName.trim()) {
      createNewSession(newSessionName.trim(), {
        ...proxyConfig,
        targetUrl
      })
      setNewSessionName('')
      setTargetUrl('')
      setShowNewSession(false)
    }
  }

  const handleSessionSelect = (session: any) => {
    setCurrentSession(session)
    setProxyConfig(session.proxyConfig)
  }

  return (
    <div className="w-80 bg-white border-r border-gray-200 flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">Sessions</h2>
          <button 
            onClick={() => setShowNewSession(true)}
            className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg"
            title="New Session"
          >
            <Plus size={20} />
          </button>
        </div>
      </div>

      {/* New Session Form */}
      {showNewSession && (
        <div className="p-4 border-b border-gray-200 bg-gray-50">
          <div className="space-y-3">
            <input
              type="text"
              placeholder="Session name"
              value={newSessionName}
              onChange={(e) => setNewSessionName(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
            />
            <input
              type="text"
              placeholder="Target URL (e.g., https://api.example.com)"
              value={targetUrl}
              onChange={(e) => setTargetUrl(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
            />
            <div className="flex gap-2">
              <button
                onClick={handleCreateSession}
                className="flex-1 px-3 py-2 bg-blue-600 text-white rounded-md text-sm hover:bg-blue-700"
              >
                Create
              </button>
              <button
                onClick={() => setShowNewSession(false)}
                className="flex-1 px-3 py-2 bg-gray-200 text-gray-700 rounded-md text-sm hover:bg-gray-300"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Sessions List */}
      <div className="flex-1 overflow-y-auto">
        {sessions.length === 0 ? (
          <div className="p-4 text-center text-gray-500">
            <p className="text-sm">No sessions yet</p>
            <p className="text-xs mt-1">Create your first debugging session</p>
          </div>
        ) : (
          sessions.map((session) => (
            <div
              key={session.id}
              className={`p-4 border-b border-gray-100 cursor-pointer hover:bg-gray-50 ${
                currentSession?.id === session.id ? 'bg-blue-50 border-blue-200' : ''
              }`}
              onClick={() => handleSessionSelect(session)}
            >
              <div className="flex items-center justify-between">
                <div className="flex-1">
                  <h3 className="font-medium text-gray-900 text-sm">{session.name}</h3>
                  <p className="text-xs text-gray-500 mt-1">{session.proxyConfig.targetUrl}</p>
                  <p className="text-xs text-gray-400">
                    Port {session.proxyConfig.port} • {session.createdAt.toLocaleDateString()}
                  </p>
                </div>
                <button
                  onClick={(e) => {
                    e.stopPropagation()
                    deleteSession(session.id)
                  }}
                  className="p-1 text-red-500 hover:bg-red-50 rounded"
                  title="Delete Session"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Footer */}
      <div className="p-4 border-t border-gray-200 bg-gray-50">
        <div className="text-xs text-gray-500 text-center">
          <p>WebhookLens v0.1.0</p>
          <p className="mt-1">Visual API debugging tool</p>
        </div>
      </div>
    </div>
  )
}