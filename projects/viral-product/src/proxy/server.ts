import http from 'http'
import https from 'https'
import { URL } from 'url'
import { v4 as uuidv4 } from 'uuid'
import { RequestData, ResponseData, ProxyConfig } from '../types'
import { DatabaseStore } from '../store/database'

export class ProxyServer {
  private server?: http.Server
  private config?: ProxyConfig
  private db: DatabaseStore
  private wsClients: Set<any> = new Set()
  private currentSessionId?: string

  constructor(database: DatabaseStore) {
    this.db = database
  }

  async start(config: ProxyConfig, sessionId: string): Promise<void> {
    this.config = config
    this.currentSessionId = sessionId

    this.server = http.createServer((req, res) => {
      this.handleRequest(req, res)
    })

    return new Promise((resolve, reject) => {
      this.server!.listen(config.port, () => {
        console.log(`Proxy server running on port ${config.port}`)
        console.log(`Forwarding to: ${config.targetUrl}`)
        resolve()
      })

      this.server!.on('error', (error) => {
        reject(error)
      })
    })
  }

  async stop(): Promise<void> {
    if (this.server) {
      return new Promise((resolve) => {
        this.server!.close(() => {
          console.log('Proxy server stopped')
          resolve()
        })
      })
    }
  }

  private async handleRequest(req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    if (!this.config || !this.currentSessionId) {
      res.statusCode = 500
      res.end('Proxy not properly configured')
      return
    }

    const requestId = uuidv4()
    const startTime = Date.now()

    try {
      // Capture incoming request
      const body = await this.readRequestBody(req)
      const url = new URL(req.url || '/', this.config.targetUrl)
      
      const requestData: RequestData = {
        id: requestId,
        timestamp: new Date(),
        method: req.method || 'GET',
        url: url.href,
        headers: req.headers as Record<string, string>,
        body,
        queryParams: Object.fromEntries(url.searchParams),
        sessionId: this.currentSessionId
      }

      // Save request to database
      await this.db.saveRequest(requestData)
      this.broadcastToClients({ type: 'request', data: requestData })

      // Forward request to target
      const response = await this.forwardRequest(requestData)
      const endTime = Date.now()

      const responseData: ResponseData = {
        id: uuidv4(),
        requestId,
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.body,
        duration: endTime - startTime
      }

      // Save response to database
      await this.db.saveResponse(responseData)
      this.broadcastToClients({ type: 'response', data: responseData })

      // Send response back to client
      res.statusCode = response.statusCode
      Object.entries(response.headers).forEach(([key, value]) => {
        res.setHeader(key, value)
      })
      res.end(response.body)

    } catch (error) {
      console.error('Proxy error:', error)
      
      // Send error response
      res.statusCode = 500
      res.end(JSON.stringify({ error: 'Proxy forwarding failed' }))
      
      this.broadcastToClients({ 
        type: 'error', 
        data: `Request ${requestId} failed: ${(error as any).message}` 
      })
    }
  }

  private async readRequestBody(req: http.IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
      let body = ''
      req.on('data', chunk => {
        body += chunk.toString()
      })
      req.on('end', () => {
        resolve(body)
      })
      req.on('error', reject)
    })
  }

  private async forwardRequest(request: RequestData): Promise<{ statusCode: number, headers: Record<string, string>, body: string }> {
    const url = new URL(request.url)
    const isHttps = url.protocol === 'https:'
    const httpModule = isHttps ? https : http

    return new Promise((resolve, reject) => {
      const options = {
        hostname: url.hostname,
        port: url.port || (isHttps ? 443 : 80),
        path: url.pathname + url.search,
        method: request.method,
        headers: { ...request.headers }
      }

      // Remove proxy-specific headers
      delete options.headers['host']
      
      const proxyReq = httpModule.request(options, (proxyRes) => {
        let body = ''
        
        proxyRes.on('data', chunk => {
          body += chunk.toString()
        })
        
        proxyRes.on('end', () => {
          resolve({
            statusCode: proxyRes.statusCode || 200,
            headers: proxyRes.headers as Record<string, string>,
            body
          })
        })
      })

      proxyReq.on('error', reject)

      // Send request body if present
      if (request.body) {
        proxyReq.write(request.body)
      }
      
      proxyReq.end()
    })
  }

  addWebSocketClient(client: any): void {
    this.wsClients.add(client)
  }

  removeWebSocketClient(client: any): void {
    this.wsClients.delete(client)
  }

  private broadcastToClients(message: any): void {
    this.wsClients.forEach(client => {
      try {
        client.send(JSON.stringify(message))
      } catch (error) {
        console.error('Failed to send message to WebSocket client:', error)
        this.wsClients.delete(client)
      }
    })
  }

  getStatus() {
    return {
      isRunning: !!this.server,
      port: this.config?.port || 0,
      targetUrl: this.config?.targetUrl || '',
      requestCount: 0 // TODO: implement request counting
    }
  }
}