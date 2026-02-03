# WebhookLens

**Visual API/Webhook debugging tool that captures, analyzes, and replays HTTP requests in real-time.**

![WebhookLens Demo](docs/demo.gif)

## 🎯 Problem Solved

Debugging webhooks and API integrations is painful:
- Failed webhook calls with no visibility into what went wrong
- Complex setup with ngrok or similar tools for local testing
- Switching between multiple tools to see request/response data
- No easy way to replay and modify requests for testing

**WebhookLens solves this** by providing a beautiful, local-first visual debugging experience.

## ✨ Key Features

### 🔍 **Visual Request Timeline**
- Real-time capture of all HTTP requests
- Beautiful timeline view with status codes and timing
- Color-coded success/error states
- Instant search and filtering

### 🎯 **Zero-Setup Proxy**
- Local HTTP proxy server (no cloud required)
- Automatic request forwarding to your target API
- Captures complete request/response data
- Works with any language or framework

### 🔄 **Request Replay System**
- One-click request replay
- Modify headers, body, or URL before replaying
- Compare original vs replayed responses
- Export to Postman/cURL format

### 📊 **Detailed Analysis**
- Complete headers and body inspection
- JSON formatting and syntax highlighting
- Performance timing analysis
- Session-based organization

### 🔒 **Privacy-First**
- All data stays local on your machine
- SQLite database for fast querying
- Optional team sharing via export
- No cloud dependencies

## 🚀 Quick Start

### Installation

1. **Download the latest release** for your platform:
   - [macOS (Apple Silicon)](releases/WebhookLens-0.1.0-arm64.dmg)
   - [macOS (Intel)](releases/WebhookLens-0.1.0-x64.dmg) 
   - [Windows](releases/WebhookLens-0.1.0.exe)
   - [Linux](releases/WebhookLens-0.1.0.AppImage)

2. **Install and launch** WebhookLens

### Basic Usage

1. **Create a session**
   - Click "+" in the sidebar
   - Name your session (e.g., "Payment Webhook Testing")
   - Set target URL (where requests should be forwarded)

2. **Start the proxy**
   - Configure the port (default: 8080)
   - Click "Start Proxy"
   - Note the proxy URL: `http://localhost:8080`

3. **Point your webhook URL** to the proxy:
   ```
   # Instead of:
   https://api.yourapp.com/webhooks/stripe
   
   # Use:
   http://localhost:8080/webhooks/stripe
   ```

4. **Send requests** and watch them appear in real-time!

## 📖 Use Cases

### 🎳 **Webhook Development**
Perfect for testing payment webhooks (Stripe, PayPal), GitHub webhooks, or any API callbacks.

```bash
# Test Stripe webhook locally
curl -X POST http://localhost:8080/webhooks/stripe \
  -H "Content-Type: application/json" \
  -d '{"type": "payment_intent.succeeded", "data": {...}}'
```

### 🔧 **API Integration Debugging**
Debug third-party API integrations by intercepting requests.

### 🧪 **Load Testing Analysis**
Capture and analyze requests during load testing to identify patterns.

### 📚 **API Documentation**
Generate real API documentation from captured requests.

## 🛠 Development Setup

### Prerequisites
- Node.js 18+ 
- npm 8+

### Build from Source

```bash
# Clone the repository
git clone https://github.com/your-username/webhook-lens
cd webhook-lens

# Install dependencies
npm install

# Run in development mode
npm run dev

# Build for production
npm run build

# Package as desktop app
npm run build:electron
```

### Project Structure
```
src/
├── main/           # Electron main process
│   ├── main.ts     # App initialization and IPC
│   └── preload.ts  # Secure bridge to renderer
├── proxy/          # HTTP proxy server
│   └── server.ts   # Request capture and forwarding
├── store/          # Data persistence
│   └── database.ts # SQLite operations
├── ui/             # React frontend
│   ├── App.tsx     # Main application component
│   ├── store.ts    # Zustand state management
│   └── components/ # UI components
└── types/          # TypeScript definitions
```

## 🚢 Deployment & Distribution

### Desktop App Packaging
```bash
# Build for all platforms
npm run build:electron

# Platform-specific builds
npm run build:mac
npm run build:win  
npm run build:linux
```

### Web Version (Optional)
```bash
# Deploy as web app (no proxy features)
npm run build
npm run preview
```

## 🎯 Roadmap

### v0.2.0 - Enhanced Features
- [ ] Request modification and custom headers
- [ ] Webhook signature validation (Stripe, GitHub, etc.)
- [ ] Dark mode and custom themes
- [ ] Performance metrics and analytics

### v0.3.0 - Team Features  
- [ ] Cloud sync for team collaboration
- [ ] Shared debugging sessions
- [ ] Slack/Discord integrations
- [ ] Team workspace management

### v1.0.0 - Enterprise Ready
- [ ] SSO integration and user management
- [ ] Audit logs and compliance features
- [ ] On-premise deployment options
- [ ] Advanced filtering and search

## 📊 Business Model

### Freemium SaaS
- **Free**: Local debugging, unlimited requests, basic export
- **Pro ($29/month)**: Team sharing, cloud sync, integrations
- **Enterprise ($99/month)**: SSO, compliance, on-premise

### Target Market
- Individual developers and small teams
- API-first companies and SaaS platforms
- DevOps and QA teams
- Enterprise development teams

## 🏆 Competitive Advantages

| Feature | WebhookLens | Postman | ngrok | Insomnia |
|---------|-------------|---------|-------|----------|
| Real-time capture | ✅ | ❌ | ❌ | ❌ |
| Visual timeline | ✅ | ❌ | ❌ | ❌ |
| Local-first | ✅ | ❌ | ❌ | ✅ |
| Zero setup | ✅ | ❌ | ❌ | ✅ |
| Request replay | ✅ | ✅ | ❌ | ✅ |
| Beautiful UI | ✅ | ✅ | ❌ | ✅ |

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Process
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 📞 Support

- **Documentation**: [docs.webhooklens.com](https://docs.webhooklens.com)
- **Issues**: [GitHub Issues](https://github.com/your-username/webhook-lens/issues)
- **Discord**: [Join our community](https://discord.gg/webhooklens)
- **Email**: support@webhooklens.com

---

**Built with ❤️ by developers, for developers.**

*WebhookLens makes API debugging visual, fast, and actually enjoyable.*