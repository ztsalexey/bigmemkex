import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import { createServer } from 'http'
import WebSocket from 'ws'
import path from 'path'
import { DatabaseStore } from '../store/database'
import { ProxyServer } from '../proxy/server'
import { Session, ProxyConfig } from '../types'
import { v4 as uuidv4 } from 'uuid'

class MainProcess {
  private mainWindow?: BrowserWindow
  private database: DatabaseStore
  private proxyServer: ProxyServer
  private wsServer?: WebSocket.Server

  constructor() {
    this.database = new DatabaseStore()
    this.proxyServer = new ProxyServer(this.database)
  }

  async initialize() {
    // Initialize database
    const dbPath = path.join(app.getPath('userData'), 'webhooklens.db')
    await this.database.initialize(dbPath)

    // Create main window
    this.createWindow()

    // Set up IPC handlers
    this.setupIpcHandlers()

    // Set up WebSocket server for real-time updates
    this.setupWebSocketServer()
  }

  private createWindow() {
    this.mainWindow = new BrowserWindow({
      width: 1200,
      height: 800,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        preload: path.join(__dirname, 'preload.js')
      },
      titleBarStyle: 'hiddenInset',
      show: false
    })

    // Load the React app
    const isDev = process.env.NODE_ENV === 'development'
    if (isDev) {
      this.mainWindow.loadURL('http://localhost:3000')
      this.mainWindow.webContents.openDevTools()
    } else {
      this.mainWindow.loadFile(path.join(__dirname, '../build/index.html'))
    }

    this.mainWindow.once('ready-to-show', () => {
      this.mainWindow?.show()
    })

    this.mainWindow.on('closed', () => {
      this.mainWindow = undefined
    })
  }

  private setupWebSocketServer() {
    const server = createServer()
    this.wsServer = new WebSocket.Server({ server })

    this.wsServer.on('connection', (ws: WebSocket) => {
      console.log('WebSocket client connected')
      this.proxyServer.addWebSocketClient(ws)

      ws.on('close', () => {
        console.log('WebSocket client disconnected')
        this.proxyServer.removeWebSocketClient(ws)
      })
    })

    server.listen(3001, () => {
      console.log('WebSocket server listening on port 3001')
    })
  }

  private setupIpcHandlers() {
    // Start proxy server
    ipcMain.handle('proxy:start', async (_, config: ProxyConfig, sessionId: string) => {
      try {
        await this.proxyServer.start(config, sessionId)
        return { success: true }
      } catch (error: any) {
        return { success: false, error: error.message }
      }
    })

    // Stop proxy server
    ipcMain.handle('proxy:stop', async () => {
      try {
        await this.proxyServer.stop()
        return { success: true }
      } catch (error: any) {
        return { success: false, error: error.message }
      }
    })

    // Get proxy status
    ipcMain.handle('proxy:status', () => {
      return this.proxyServer.getStatus()
    })

    // Database operations
    ipcMain.handle('db:createSession', async (_, session: Session) => {
      await this.database.createSession(session)
      return { success: true }
    })

    ipcMain.handle('db:getSessions', async () => {
      return await this.database.getSessions()
    })

    ipcMain.handle('db:getSessionRequests', async (_, sessionId: string) => {
      return await this.database.getSessionRequests(sessionId)
    })

    ipcMain.handle('db:getResponse', async (_, requestId: string) => {
      return await this.database.getResponse(requestId)
    })

    ipcMain.handle('db:deleteSession', async (_, sessionId: string) => {
      await this.database.deleteSession(sessionId)
      return { success: true }
    })

    // File operations
    ipcMain.handle('file:showSaveDialog', async (_, options) => {
      const result = await dialog.showSaveDialog(this.mainWindow!, options)
      return result
    })

    ipcMain.handle('file:showOpenDialog', async (_, options) => {
      const result = await dialog.showOpenDialog(this.mainWindow!, options)
      return result
    })
  }
}

// App event handlers
app.whenReady().then(async () => {
  const mainProcess = new MainProcess()
  await mainProcess.initialize()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    const mainProcess = new MainProcess()
    mainProcess.initialize()
  }
})