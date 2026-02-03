import React, { useState } from 'react'
import { useAppStore } from '../store'
import { Copy, Download, RefreshCw, Code, FileText } from 'lucide-react'

export function RequestDetails() {
  const { requests, selectedRequest } = useAppStore()
  const [activeTab, setActiveTab] = useState<'request' | 'response'>('request')
  const [requestView, setRequestView] = useState<'headers' | 'body' | 'params'>('headers')
  const [responseView, setResponseView] = useState<'headers' | 'body'>('headers')

  const selectedPair = requests.find(pair => pair.request.id === selectedRequest)

  if (!selectedPair) {
    return (
      <div className="h-full flex items-center justify-center text-gray-500">
        <div className="text-center">
          <FileText size={48} className="mx-auto mb-4 opacity-50" />
          <p className="text-lg mb-2">No request selected</p>
          <p className="text-sm">Select a request from the timeline to view details</p>
        </div>
      </div>
    )
  }

  const { request, response } = selectedPair

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text)
    // TODO: Show toast notification
  }

  const exportAsCurl = () => {
    let curl = `curl -X ${request.method} '${request.url}'`
    
    Object.entries(request.headers).forEach(([key, value]) => {
      curl += ` \\\n  -H '${key}: ${value}'`
    })
    
    if (request.body) {
      curl += ` \\\n  -d '${request.body}'`
    }
    
    copyToClipboard(curl)
  }

  const formatJson = (jsonString: string) => {
    try {
      return JSON.stringify(JSON.parse(jsonString), null, 2)
    } catch {
      return jsonString
    }
  }

  const isJsonContent = (headers: Record<string, string>) => {
    const contentType = Object.entries(headers).find(
      ([key]) => key.toLowerCase() === 'content-type'
    )?.[1] || ''
    return contentType.includes('application/json')
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="p-4 border-b border-gray-200">
        <div className="flex items-center justify-between mb-2">
          <h3 className="font-semibold text-gray-900">Request Details</h3>
          <div className="flex space-x-2">
            <button
              onClick={exportAsCurl}
              className="p-2 text-gray-600 hover:bg-gray-100 rounded"
              title="Copy as cURL"
            >
              <Copy size={16} />
            </button>
            <button
              className="p-2 text-gray-600 hover:bg-gray-100 rounded"
              title="Replay Request"
            >
              <RefreshCw size={16} />
            </button>
          </div>
        </div>
        
        {/* Method and URL */}
        <div className="flex items-center space-x-3">
          <span className={`px-2 py-1 rounded text-xs font-medium ${
            request.method === 'GET' ? 'text-blue-700 bg-blue-100' :
            request.method === 'POST' ? 'text-green-700 bg-green-100' :
            request.method === 'PUT' ? 'text-orange-700 bg-orange-100' :
            request.method === 'DELETE' ? 'text-red-700 bg-red-100' :
            'text-gray-700 bg-gray-100'
          }`}>
            {request.method}
          </span>
          <span className="text-sm font-mono text-gray-700 flex-1 truncate">
            {request.url}
          </span>
          {response && (
            <span className={`px-2 py-1 rounded text-xs font-medium ${
              response.statusCode >= 200 && response.statusCode < 300 ? 'text-green-700 bg-green-100' :
              response.statusCode >= 400 ? 'text-red-700 bg-red-100' :
              'text-yellow-700 bg-yellow-100'
            }`}>
              {response.statusCode}
            </span>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-gray-200">
        <button
          className={`px-4 py-3 text-sm font-medium ${
            activeTab === 'request' 
              ? 'border-b-2 border-blue-500 text-blue-600' 
              : 'text-gray-500 hover:text-gray-700'
          }`}
          onClick={() => setActiveTab('request')}
        >
          Request
        </button>
        <button
          className={`px-4 py-3 text-sm font-medium ${
            activeTab === 'response' 
              ? 'border-b-2 border-blue-500 text-blue-600' 
              : 'text-gray-500 hover:text-gray-700'
          }`}
          onClick={() => setActiveTab('response')}
          disabled={!response}
        >
          Response {response && `(${response.duration}ms)`}
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'request' && (
          <div className="h-full flex flex-col">
            {/* Request Sub-tabs */}
            <div className="flex border-b border-gray-100">
              <button
                className={`px-3 py-2 text-sm ${
                  requestView === 'headers' ? 'bg-gray-100 text-gray-900' : 'text-gray-600'
                }`}
                onClick={() => setRequestView('headers')}
              >
                Headers ({Object.keys(request.headers).length})
              </button>
              {Object.keys(request.queryParams).length > 0 && (
                <button
                  className={`px-3 py-2 text-sm ${
                    requestView === 'params' ? 'bg-gray-100 text-gray-900' : 'text-gray-600'
                  }`}
                  onClick={() => setRequestView('params')}
                >
                  Params ({Object.keys(request.queryParams).length})
                </button>
              )}
              {request.body && (
                <button
                  className={`px-3 py-2 text-sm ${
                    requestView === 'body' ? 'bg-gray-100 text-gray-900' : 'text-gray-600'
                  }`}
                  onClick={() => setRequestView('body')}
                >
                  Body ({request.body.length} bytes)
                </button>
              )}
            </div>

            {/* Request Content */}
            <div className="flex-1 overflow-y-auto p-4">
              {requestView === 'headers' && (
                <div className="space-y-2">
                  {Object.entries(request.headers).map(([key, value]) => (
                    <div key={key} className="flex">
                      <span className="text-sm font-medium text-gray-600 w-1/3">{key}:</span>
                      <span className="text-sm text-gray-900 flex-1 font-mono break-all">{value}</span>
                    </div>
                  ))}
                </div>
              )}

              {requestView === 'params' && (
                <div className="space-y-2">
                  {Object.entries(request.queryParams).map(([key, value]) => (
                    <div key={key} className="flex">
                      <span className="text-sm font-medium text-gray-600 w-1/3">{key}:</span>
                      <span className="text-sm text-gray-900 flex-1 font-mono break-all">{value}</span>
                    </div>
                  ))}
                </div>
              )}

              {requestView === 'body' && request.body && (
                <div>
                  <pre className="text-sm font-mono bg-gray-50 p-3 rounded border overflow-x-auto">
                    {isJsonContent(request.headers) ? formatJson(request.body) : request.body}
                  </pre>
                </div>
              )}
            </div>
          </div>
        )}

        {activeTab === 'response' && response && (
          <div className="h-full flex flex-col">
            {/* Response Sub-tabs */}
            <div className="flex border-b border-gray-100">
              <button
                className={`px-3 py-2 text-sm ${
                  responseView === 'headers' ? 'bg-gray-100 text-gray-900' : 'text-gray-600'
                }`}
                onClick={() => setResponseView('headers')}
              >
                Headers ({Object.keys(response.headers).length})
              </button>
              {response.body && (
                <button
                  className={`px-3 py-2 text-sm ${
                    responseView === 'body' ? 'bg-gray-100 text-gray-900' : 'text-gray-600'
                  }`}
                  onClick={() => setResponseView('body')}
                >
                  Body ({response.body.length} bytes)
                </button>
              )}
            </div>

            {/* Response Content */}
            <div className="flex-1 overflow-y-auto p-4">
              {responseView === 'headers' && (
                <div className="space-y-2">
                  {Object.entries(response.headers).map(([key, value]) => (
                    <div key={key} className="flex">
                      <span className="text-sm font-medium text-gray-600 w-1/3">{key}:</span>
                      <span className="text-sm text-gray-900 flex-1 font-mono break-all">{value}</span>
                    </div>
                  ))}
                </div>
              )}

              {responseView === 'body' && response.body && (
                <div>
                  <pre className="text-sm font-mono bg-gray-50 p-3 rounded border overflow-x-auto">
                    {isJsonContent(response.headers) ? formatJson(response.body) : response.body}
                  </pre>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}