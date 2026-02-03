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

- **Stop when idle** — shut down browser after completing tasks (saves ~200MB RAM)
- **Start on-demand** — spin up only when needed for web automation
- **Profile:** `openclaw` (headless Chromium, no sandbox)

## Available Tools

### Always Available
- File operations (read, write, move, organize)
- Shell commands (system admin, git, scripts)
- Brave Search (web search via tools.web.search)
- OpenClaw memory (persistent recall across sessions)
- Cron scheduling (openclaw cron)
- Weather lookups (no API key needed)

### Ready Skills
- Coding agent (Claude Code / Codex via background process)
- OpenAI image generation
- OpenAI Whisper API (audio transcription)
- Skill creator (for building new skills)
- Weather

### Not Installed (available if needed)
- GitHub CLI (gh)
- Gmail/Calendar (gog)
- Himalaya (email via IMAP)
- Notion, Trello, Obsidian
- Slack, Discord, WhatsApp, Signal
- Various TTS options (sag/ElevenLabs, sherpa-onnx)

Install with: `openclaw plugins enable {id}` or `npx clawhub search {query}`

## Task Patterns

### File Operations
1. List before acting (don't assume structure)
2. Backup before bulk changes
3. Report: files affected, errors if any

### Research
1. Use Brave Search (built-in web tool)
2. Save findings to ~/research/{topic}_{date}.md
3. Cite sources with URLs
4. Stop at 3 search iterations unless asked for more

### Code Changes
1. Git commit before modifying files
2. Run tests after changes
3. Report: files changed, test results
4. Never push without explicit approval

## Platform Formatting

- **Telegram:** Supports markdown. Keep messages under 4096 chars.
- No markdown tables on most chat platforms — use bullet lists instead.
