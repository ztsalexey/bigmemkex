import React, { useEffect } from 'react'
import { useAppStore } from '../store'
import { Play, Square, Settings, AlertCircle, CheckCircle } from 'lucide-react'

export function ProxyControls() {
  const { 
    currentSession,
    proxyStatus,
    proxyConfig,
    setProxyStatus,
    setProxyConfig
  } = useAppStore()

  useEffect(() => {
    // Check proxy status on mount
    checkProxyStatus()
  }, [])

  const checkProxyStatus = async () => {
    try {
      const status = await window.electronAPI.proxyStatus()
      setProxyStatus(status.isRunning ? 'running' : 'stopped')
    } catch (error) {
      console.error('Failed to check proxy status:', error)
      setProxyStatus('error')
    }
  }

  const startProxy = async () => {
    if (!currentSession) {
      alert('Please select a session first')
      return
    }

    setProxyStatus('starting')
    
    try {
      const result = await window.electronAPI.proxyStart(proxyConfig, currentSession.id)
      if (result.success) {
        setProxyStatus('running')
      } else {
        setProxyStatus('error')
        alert(`Failed to start proxy: ${result.error}`)
      }
    } catch (error) {
      setProxyStatus('error')
      alert(`Failed to start proxy: ${error}`)
    }
  }

  const stopProxy = async () => {
    try {
      const result = await window.electronAPI.proxyStop()
      if (result.success) {
        setProxyStatus('stopped')
      } else {
        alert(`Failed to stop proxy: ${result.error}`)
      }
    } catch (error) {
      alert(`Failed to stop proxy: ${error}`)
    }
  }

  const getStatusColor = () => {
    switch (proxyStatus) {
      case 'running': return 'text-green-600'
      case 'starting': return 'text-yellow-600'
      case 'error': return 'text-red-600'
      default: return 'text-gray-600'
    }
  }

  const getStatusIcon = () => {
    switch (proxyStatus) {
      case 'running': return <CheckCircle size={20} />
      case 'error': return <AlertCircle size={20} />
      default: return null
    }
  }

  const getProxyUrl = () => {
    if (proxyStatus === 'running') {
      return `http://localhost:${proxyConfig.port}`
    }
    return null
  }

  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center space-x-4">
        {/* Status Indicator */}
        <div className="flex items-center space-x-2">
          <div className={`flex items-center space-x-2 ${getStatusColor()}`}>
            {getStatusIcon()}
            <span className="font-medium capitalize">{proxyStatus}</span>
          </div>
        </div>

        {/* Proxy URL */}
        {getProxyUrl() && (
          <div className="bg-gray-100 px-3 py-1 rounded-md">
            <span className="text-sm font-mono text-gray-700">{getProxyUrl()}</span>
          </div>
        )}

        {/* Target URL */}
        {currentSession && (
          <div className="text-sm text-gray-600">
            → <span className="font-mono">{currentSession.proxyConfig.targetUrl}</span>
          </div>
        )}
      </div>

      <div className="flex items-center space-x-2">
        {/* Configuration */}
        <div className="flex items-center space-x-2 text-sm">
          <label className="text-gray-600">Port:</label>
          <input
            type="number"
            value={proxyConfig.port}
            onChange={(e) => setProxyConfig({ ...proxyConfig, port: parseInt(e.target.value) || 8080 })}
            disabled={proxyStatus === 'running'}
            className="w-20 px-2 py-1 border border-gray-300 rounded text-sm disabled:bg-gray-100"
          />
        </div>

        {/* Control Buttons */}
        {proxyStatus === 'running' ? (
          <button
            onClick={stopProxy}
            className="flex items-center space-x-2 px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
          >
            <Square size={16} />
            <span>Stop Proxy</span>
          </button>
        ) : (
          <button
            onClick={startProxy}
            disabled={!currentSession || proxyStatus === 'starting'}
            className="flex items-center space-x-2 px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 disabled:bg-gray-400"
          >
            <Play size={16} />
            <span>{proxyStatus === 'starting' ? 'Starting...' : 'Start Proxy'}</span>
          </button>
        )}
      </div>
    </div>
  )
}