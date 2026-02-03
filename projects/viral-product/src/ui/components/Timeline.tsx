import React from 'react'
import { useAppStore } from '../store'
import { Clock, RefreshCw, CheckCircle, XCircle, AlertTriangle } from 'lucide-react'

export function Timeline() {
  const { 
    requests, 
    selectedRequest, 
    setSelectedRequest,
    currentSession 
  } = useAppStore()

  if (!currentSession) {
    return (
      <div className="flex items-center justify-center h-full text-gray-500">
        <div className="text-center">
          <p className="text-lg mb-2">No session selected</p>
          <p className="text-sm">Create or select a session to start debugging</p>
        </div>
      </div>
    )
  }

  if (requests.length === 0) {
    return (
      <div className="flex items-center justify-center h-full text-gray-500">
        <div className="text-center">
          <RefreshCw size={48} className="mx-auto mb-4 opacity-50" />
          <p className="text-lg mb-2">Waiting for requests</p>
          <p className="text-sm">Send a request to your proxy URL to see it here</p>
          <div className="mt-4 bg-gray-100 px-4 py-2 rounded-md text-sm font-mono">
            http://localhost:{currentSession.proxyConfig.port}
          </div>
        </div>
      </div>
    )
  }

  const getStatusIcon = (statusCode?: number) => {
    if (!statusCode) return <Clock size={16} className="text-gray-400" />
    
    if (statusCode >= 200 && statusCode < 300) {
      return <CheckCircle size={16} className="text-green-500" />
    } else if (statusCode >= 400) {
      return <XCircle size={16} className="text-red-500" />
    } else {
      return <AlertTriangle size={16} className="text-yellow-500" />
    }
  }

  const getStatusColor = (statusCode?: number) => {
    if (!statusCode) return 'text-gray-600 bg-gray-100'
    
    if (statusCode >= 200 && statusCode < 300) {
      return 'text-green-700 bg-green-100'
    } else if (statusCode >= 400) {
      return 'text-red-700 bg-red-100'
    } else {
      return 'text-yellow-700 bg-yellow-100'
    }
  }

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', { 
      hour12: false, 
      hour: '2-digit', 
      minute: '2-digit', 
      second: '2-digit' 
    })
  }

  const getMethodColor = (method: string) => {
    switch (method.toUpperCase()) {
      case 'GET': return 'text-blue-700 bg-blue-100'
      case 'POST': return 'text-green-700 bg-green-100'
      case 'PUT': return 'text-orange-700 bg-orange-100'
      case 'DELETE': return 'text-red-700 bg-red-100'
      case 'PATCH': return 'text-purple-700 bg-purple-100'
      default: return 'text-gray-700 bg-gray-100'
    }
  }

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-gray-200 bg-white">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold text-gray-900">Request Timeline</h3>
          <div className="text-sm text-gray-500">
            {requests.length} request{requests.length !== 1 ? 's' : ''}
          </div>
        </div>
      </div>

      {/* Request List */}
      <div className="flex-1 overflow-y-auto">
        {requests.map((pair) => {
          const { request, response } = pair
          const isSelected = selectedRequest === request.id
          
          return (
            <div
              key={request.id}
              className={`border-b border-gray-100 cursor-pointer hover:bg-gray-50 ${
                isSelected ? 'bg-blue-50 border-blue-200' : ''
              }`}
              onClick={() => setSelectedRequest(request.id)}
            >
              <div className="p-4">
                {/* Request Line */}
                <div className="flex items-center space-x-3 mb-2">
                  {/* Status Icon */}
                  {getStatusIcon(response?.statusCode)}
                  
                  {/* Method */}
                  <span className={`px-2 py-1 rounded text-xs font-medium ${getMethodColor(request.method)}`}>
                    {request.method}
                  </span>
                  
                  {/* Status Code */}
                  {response && (
                    <span className={`px-2 py-1 rounded text-xs font-medium ${getStatusColor(response.statusCode)}`}>
                      {response.statusCode}
                    </span>
                  )}
                  
                  {/* Duration */}
                  {response && (
                    <span className="text-xs text-gray-500">
                      {response.duration}ms
                    </span>
                  )}
                  
                  {/* Time */}
                  <span className="text-xs text-gray-500 ml-auto">
                    {formatTime(request.timestamp)}
                  </span>
                </div>
                
                {/* URL */}
                <div className="text-sm font-mono text-gray-700 truncate">
                  {request.url}
                </div>
                
                {/* Additional Info */}
                {Object.keys(request.queryParams).length > 0 && (
                  <div className="text-xs text-gray-500 mt-1">
                    {Object.keys(request.queryParams).length} query param{Object.keys(request.queryParams).length !== 1 ? 's' : ''}
                  </div>
                )}
                
                {request.body && (
                  <div className="text-xs text-gray-500 mt-1">
                    Body: {request.body.length} bytes
                  </div>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}