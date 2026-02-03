import sqlite3 from 'sqlite3'
import { open, Database } from 'sqlite'
import { RequestData, ResponseData, Session } from '../types'

export class DatabaseStore {
  private db: Database | null = null

  async initialize(dbPath: string) {
    this.db = await open({
      filename: dbPath,
      driver: sqlite3.Database
    })

    await this.createTables()
  }

  private async createTables() {
    if (!this.db) throw new Error('Database not initialized')

    // Create sessions table
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        proxy_config TEXT NOT NULL
      )
    `)

    // Create requests table  
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS requests (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        method TEXT NOT NULL,
        url TEXT NOT NULL,
        headers TEXT NOT NULL,
        body TEXT,
        query_params TEXT,
        session_id TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id)
      )
    `)

    // Create responses table
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS responses (
        id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        status_code INTEGER NOT NULL,
        headers TEXT NOT NULL,
        body TEXT,
        duration INTEGER NOT NULL,
        FOREIGN KEY (request_id) REFERENCES requests (id)
      )
    `)

    // Create indexes for better query performance
    await this.db.exec(`
      CREATE INDEX IF NOT EXISTS idx_requests_session ON requests (session_id);
      CREATE INDEX IF NOT EXISTS idx_requests_timestamp ON requests (timestamp);
      CREATE INDEX IF NOT EXISTS idx_responses_request ON responses (request_id);
    `)
  }

  async createSession(session: Session): Promise<void> {
    if (!this.db) throw new Error('Database not initialized')
    
    await this.db.run(
      'INSERT INTO sessions (id, name, created_at, proxy_config) VALUES (?, ?, ?, ?)',
      [session.id, session.name, session.createdAt.getTime(), JSON.stringify(session.proxyConfig)]
    )
  }

  async getSessions(): Promise<Session[]> {
    if (!this.db) throw new Error('Database not initialized')
    
    const rows = await this.db.all('SELECT * FROM sessions ORDER BY created_at DESC')
    return rows.map((row: any) => ({
      id: row.id,
      name: row.name,
      createdAt: new Date(row.created_at),
      proxyConfig: JSON.parse(row.proxy_config)
    }))
  }

  async saveRequest(request: RequestData): Promise<void> {
    if (!this.db) throw new Error('Database not initialized')
    
    await this.db.run(
      `INSERT INTO requests (id, timestamp, method, url, headers, body, query_params, session_id) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        request.id,
        request.timestamp.getTime(),
        request.method,
        request.url,
        JSON.stringify(request.headers),
        request.body,
        JSON.stringify(request.queryParams),
        request.sessionId
      ]
    )
  }

  async saveResponse(response: ResponseData): Promise<void> {
    if (!this.db) throw new Error('Database not initialized')
    
    await this.db.run(
      'INSERT INTO responses (id, request_id, status_code, headers, body, duration) VALUES (?, ?, ?, ?, ?, ?)',
      [
        response.id,
        response.requestId,
        response.statusCode,
        JSON.stringify(response.headers),
        response.body,
        response.duration
      ]
    )
  }

  async getSessionRequests(sessionId: string): Promise<RequestData[]> {
    if (!this.db) throw new Error('Database not initialized')
    
    const rows = await this.db.all(
      'SELECT * FROM requests WHERE session_id = ? ORDER BY timestamp DESC',
      [sessionId]
    )
    
    return rows.map((row: any) => ({
      id: row.id,
      timestamp: new Date(row.timestamp),
      method: row.method,
      url: row.url,
      headers: JSON.parse(row.headers),
      body: row.body,
      queryParams: JSON.parse(row.query_params || '{}'),
      sessionId: row.session_id
    }))
  }

  async getResponse(requestId: string): Promise<ResponseData | null> {
    if (!this.db) throw new Error('Database not initialized')
    
    const row = await this.db.get(
      'SELECT * FROM responses WHERE request_id = ?',
      [requestId]
    )
    
    if (!row) return null
    
    return {
      id: row.id,
      requestId: row.request_id,
      statusCode: row.status_code,
      headers: JSON.parse(row.headers),
      body: row.body,
      duration: row.duration
    }
  }

  async deleteSession(sessionId: string): Promise<void> {
    if (!this.db) throw new Error('Database not initialized')
    
    // Delete in order: responses, requests, session
    await this.db.run(
      'DELETE FROM responses WHERE request_id IN (SELECT id FROM requests WHERE session_id = ?)',
      [sessionId]
    )
    await this.db.run('DELETE FROM requests WHERE session_id = ?', [sessionId])
    await this.db.run('DELETE FROM sessions WHERE id = ?', [sessionId])
  }

  async close(): Promise<void> {
    if (this.db) {
      await this.db.close()
      this.db = null
    }
  }
}