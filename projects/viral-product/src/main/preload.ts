import { contextBridge, ipcRenderer } from 'electron'
import { ProxyConfig, Session } from '../types'

// Expose protected methods that allow the renderer process to use
// the ipcRenderer without exposing the entire object
contextBridge.exposeInMainWorld('electronAPI', {
  // Proxy operations
  proxyStart: (config: ProxyConfig, sessionId: string) => 
    ipcRenderer.invoke('proxy:start', config, sessionId),
  proxyStop: () => 
    ipcRenderer.invoke('proxy:stop'),
  proxyStatus: () => 
    ipcRenderer.invoke('proxy:status'),

  // Database operations
  createSession: (session: Session) => 
    ipcRenderer.invoke('db:createSession', session),
  getSessions: () => 
    ipcRenderer.invoke('db:getSessions'),
  getSessionRequests: (sessionId: string) => 
    ipcRenderer.invoke('db:getSessionRequests', sessionId),
  getResponse: (requestId: string) => 
    ipcRenderer.invoke('db:getResponse', requestId),
  deleteSession: (sessionId: string) => 
    ipcRenderer.invoke('db:deleteSession', sessionId),

  // File operations
  showSaveDialog: (options: any) => 
    ipcRenderer.invoke('file:showSaveDialog', options),
  showOpenDialog: (options: any) => 
    ipcRenderer.invoke('file:showOpenDialog', options),

  // WebSocket connection
  connectWebSocket: () => {
    const ws = new WebSocket('ws://localhost:3001')
    return ws
  }
})

// Type definitions for the exposed API
export interface ElectronAPI {
  proxyStart: (config: ProxyConfig, sessionId: string) => Promise<{ success: boolean; error?: string }>
  proxyStop: () => Promise<{ success: boolean; error?: string }>
  proxyStatus: () => Promise<any>
  createSession: (session: Session) => Promise<{ success: boolean }>
  getSessions: () => Promise<Session[]>
  getSessionRequests: (sessionId: string) => Promise<any[]>
  getResponse: (requestId: string) => Promise<any>
  deleteSession: (sessionId: string) => Promise<{ success: boolean }>
  showSaveDialog: (options: any) => Promise<any>
  showOpenDialog: (options: any) => Promise<any>
  connectWebSocket: () => WebSocket
}

declare global {
  interface Window {
    electronAPI: ElectronAPI
  }
}