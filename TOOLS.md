# TOOLS.md - Your Setup

## Server Environment

- **OS:** Debian Linux (Trixie) on x86_64
- **Host:** 204598.example.us
- **User:** root
- **Node:** v22.22.0

## Models

- **Primary:** Claude Opus 4.5 (Anthropic) — via auth token
- **Fallback:** OpenAI — via API key in .env

## Active Channels

- **Telegram** — bot token configured, primary communication channel

## Browser Rules

- **Status:** WORKING — Playwright installed and functional
- **Stop when idle** — shut down after tasks (saves ~200MB RAM)
- **Start on-demand** — spin up only when needed
- **Profile:** `openclaw` (headless Chromium, no sandbox)
- **Capabilities:** Full page automation, screenshots, snapshots, form filling

## Voice

- **Engine:** ElevenLabs
- **Voice:** Daniel (ID: `onwK4e9ZLuTAKqWW03F9`)
- **Style:** JARVIS - British, calm, refined AI assistant
- **Settings:** stability=0.7, similarity_boost=0.75
- **Language:** ALWAYS ENGLISH — I'm British, I speak English. No exceptions.

### Voice Message Workflow (CRITICAL)
1. **Generate**: Call ElevenLabs API directly with voice ID `onwK4e9ZLuTAKqWW03F9`
   ```bash
   curl -s "https://api.elevenlabs.io/v1/text-to-speech/onwK4e9ZLuTAKqWW03F9" \
     -H "xi-api-key: $(cat ~/.openclaw/secrets/elevenlabs-api-key.txt)" \
     -H "Content-Type: application/json" \
     -d '{"text": "...", "model_id": "eleven_multilingual_v2", "voice_settings": {"stability": 0.7, "similarity_boost": 0.75}}' \
     --output /tmp/voice.mp3
   ```
2. **Convert** to Telegram-compatible voice format:
   ```bash
   ffmpeg -y -i /tmp/voice.mp3 -c:a libopus -b:a 32k -vbr on -application voip /tmp/voice.ogg
   ```
3. **Send** via message tool:
   ```
   message(action=send, channel=telegram, target=CHAT_ID, filePath=/tmp/voice.ogg, asVoice=true)
   ```

**DO NOT** just output `MEDIA:/path` — use the message tool explicitly.

## Accounts

- **Twitter/X:** @llmtrade — news scraping, monitoring (credentials in secrets/)
- **Proton Mail:** bigmemkex@proton.me (credentials in secrets/)
- **Claw2Claw:** Bot "Kex" — P2P crypto trading with other AI agents (API key in secrets/claw2claw-api-key.txt)

## Git Setup

- **Repo:** `github.com/ztsalexey/bigmemkex`
- **Committer:** Kex (bigmemkex@proton.me)
- **Co-author:** ztsalexey (alexthebuildr@gmail.com) — added to all commits
- **Structure:** `projects/` folder for each project

## Available Tools

### Always Available
- File operations (read, write, move, organize)
- Shell commands (system admin, git, scripts)
- Brave Search (web_search — use freshness='pd' for news)
- Browser automation (browser tool — USE FOR NEWS, more reliable than web_search)
- OpenClaw memory (persistent recall across sessions)
- Cron scheduling (openclaw cron)
- Weather lookups (no API key needed)
- LangExtract (Python) — structured extraction from big texts

### Ready Skills
- Coding agent (Claude Code / Codex via background process)
- OpenAI image generation
- OpenAI Whisper API (audio transcription)
- Skill creator (for building new skills)
- Weather

### Data Fetching Priority
1. **Prices** — CoinGecko API via curl (NEVER web_search)
2. **News** — browser snapshots (cointelegraph, theverge, apnews)
3. **Trending** — browser snapshot trends24.in
4. **Research** — web_search with freshness='pd' as fallback
5. **Big texts** — LangExtract for structured extraction

### Cloudflare Markdown Mode (ALWAYS USE)
```bash
curl -H "Accept: text/markdown" https://example.com/article
```
Returns clean Markdown instead of HTML — fewer tokens, no parsing needed.

### Not Installed (available if needed)
- GitHub CLI (gh)
- Gmail/Calendar (gog)
- Himalaya (email via IMAP)
- Notion, Trello, Obsidian
- Slack, Discord, WhatsApp, Signal
- Various TTS options (sag/ElevenLabs, sherpa-onnx)

Install with: `openclaw plugins enable {id}` or `npx clawhub search {query}`

## Task Patterns

- **Files:** List → backup → act → report
- **Research:** Search → save to `~/research/{topic}_{date}.md` → cite URLs → stop at 3 iterations
- **Code:** Commit → change → test → report → never push without approval

## Platform Formatting

- **Telegram:** Supports markdown, 4096 char limit
- **Discord/WhatsApp:** No markdown tables — use bullet lists
- **Discord links:** Wrap in `<>` to suppress embeds: `<https://example.com>`
- **WhatsApp:** No headers — use **bold** or CAPS for emphasis

## Self-Improvement System

**Logging:** Tasks to `memory/task-outcomes.jsonl`, errors to `memory/errors.jsonl`

**Error Recovery:**
1. Browser timeout → retry → curl with markdown header
2. Web search stale → browser snapshot  
3. API failure → retry 3x → notify
4. Token budget tight → summarize, drop COLD files

**Context:** Use `memory/context-map.json` for keyword-based activation

**Security:** clawdex scans skills before install

## Cost Optimization

### Model Tiers

| Tier | Model | Cost | Use For |
|------|-------|------|---------|
| FREE | `google/gemini-2.0-flash-lite` | $0 | Cron jobs, simple monitoring |
| Cheap | `anthropic/claude-sonnet-4-20250514` | ~$3/M | Default sub-agents, code review |
| Standard | `openai/gpt-4o` | ~$5/M | Image analysis, fallback |
| Premium | `anthropic/claude-opus-4-5` | ~$15/M | Main session, complex work |
| Max | `anthropic/claude-opus-4-6` | ~$20/M | Architecture, deep reasoning |

### Model Allowlist (CRITICAL)

`agents.defaults.models` is an **ALLOWLIST**. Any model you want to use MUST be listed there.
If you add aliases for some models, you must add ALL models you plan to use.

### Sub-Agent Model Selection

| Task Type | Model | Alias |
|-----------|-------|-------|
| Cron jobs, monitoring | `google/gemini-2.0-flash-lite` | gemini |
| Bulk file processing | `google/gemini-2.0-flash-lite` | gemini |
| Web research, scraping | `anthropic/claude-sonnet-4-20250514` | sonnet |
| Code review, refactoring | `anthropic/claude-sonnet-4-20250514` | sonnet |
| Architecture, complex debug | `anthropic/claude-opus-4-6` | opus46 |

### Token Burn Prevention

- Heartbeats: minimal context, quick checks
- Don't re-read large files unnecessarily
- Use `memory_search` before full file reads
- Batch similar operations
- Stop web search at 3 iterations unless asked
