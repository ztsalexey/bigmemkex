// Core data types for WebhookLens

export interface RequestData {
  id: string
  timestamp: Date
  method: string
  url: string
  headers: Record<string, string>
  body: string
  queryParams: Record<string, string>
  sessionId: string
}

export interface ResponseData {
  id: string
  requestId: string
  statusCode: number
  headers: Record<string, string>
  body: string
  duration: number // milliseconds
}

export interface Session {
  id: string
  name: string
  createdAt: Date
  proxyConfig: ProxyConfig
}

export interface ProxyConfig {
  port: number
  targetUrl: string
  httpsEnabled: boolean
}

export interface RequestResponsePair {
  request: RequestData
  response?: ResponseData
}

// WebSocket message types
export interface WSMessage {
  type: 'request' | 'response' | 'error'
  data: RequestData | ResponseData | string
}

// Store types
export interface AppState {
  sessions: Session[]
  currentSession?: Session
  requests: RequestResponsePair[]
  proxyStatus: 'stopped' | 'starting' | 'running' | 'error'
  selectedRequest?: string
}

export interface ProxyServerState {
  isRunning: boolean
  port: number
  targetUrl: string
  requestCount: number
}