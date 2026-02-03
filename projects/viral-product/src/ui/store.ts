import { create } from 'zustand'
import { RequestResponsePair, Session, ProxyConfig, RequestData, ResponseData } from '../types'

interface AppState {
  // Sessions
  sessions: Session[]
  currentSession?: Session
  
  // Requests and responses
  requests: RequestResponsePair[]
  selectedRequest?: string
  
  // Proxy state
  proxyStatus: 'stopped' | 'starting' | 'running' | 'error'
  proxyConfig: ProxyConfig
  
  // UI state
  sidebarOpen: boolean
  
  // Actions
  setSessions: (sessions: Session[]) => void
  setCurrentSession: (session: Session) => void
  createNewSession: (name: string, config: ProxyConfig) => void
  deleteSession: (sessionId: string) => void
  
  setRequests: (requests: RequestResponsePair[]) => void
  addRequest: (request: RequestData) => void
  updateResponse: (response: ResponseData) => void
  setSelectedRequest: (requestId?: string) => void
  
  setProxyStatus: (status: 'stopped' | 'starting' | 'running' | 'error') => void
  setProxyConfig: (config: ProxyConfig) => void
  
  setSidebarOpen: (open: boolean) => void
}

export const useAppStore = create<AppState>((set, get) => ({
  // Initial state
  sessions: [],
  currentSession: undefined,
  requests: [],
  selectedRequest: undefined,
  proxyStatus: 'stopped',
  proxyConfig: {
    port: 8080,
    targetUrl: 'https://httpbin.org/post',
    httpsEnabled: false
  },
  sidebarOpen: true,

  // Session actions
  setSessions: (sessions) => set({ sessions }),
  
  setCurrentSession: (session) => set({ currentSession: session }),
  
  createNewSession: (name, config) => {
    const newSession: Session = {
      id: crypto.randomUUID(),
      name,
      createdAt: new Date(),
      proxyConfig: config
    }
    
    // Create session in database
    window.electronAPI.createSession(newSession).then(() => {
      set(state => ({ 
        sessions: [newSession, ...state.sessions],
        currentSession: newSession,
        requests: [],
        proxyConfig: config
      }))
    })
  },
  
  deleteSession: (sessionId) => {
    window.electronAPI.deleteSession(sessionId).then(() => {
      set(state => {
        const sessions = state.sessions.filter(s => s.id !== sessionId)
        const currentSession = state.currentSession?.id === sessionId ? undefined : state.currentSession
        return { 
          sessions, 
          currentSession,
          requests: currentSession ? state.requests : []
        }
      })
    })
  },

  // Request/response actions
  setRequests: (requests) => set({ requests }),
  
  addRequest: (request) => set(state => ({
    requests: [{ request }, ...state.requests]
  })),
  
  updateResponse: (response) => set(state => ({
    requests: state.requests.map(pair => 
      pair.request.id === response.requestId 
        ? { ...pair, response }
        : pair
    )
  })),
  
  setSelectedRequest: (requestId) => set({ selectedRequest: requestId }),

  // Proxy actions  
  setProxyStatus: (status) => set({ proxyStatus: status }),
  setProxyConfig: (config) => set({ proxyConfig: config }),

  // UI actions
  setSidebarOpen: (open) => set({ sidebarOpen: open })
}))