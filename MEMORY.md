# MEMORY.md — Long-Term Memory

## About Alexey
- Telegram: @alexthebuildr (id: 256092667)
- Location: Montana, near Eureka (close to Canadian border) — NOT Denver
- Has a cabin there with a wood stove — likes the aesthetic
- Enjoys creative image generation (movie posters, memes)
- Interested in crypto markets, bottom signals, AI news
- Priorities: finances, crypto, AI — stay up to date on ALL
- Skiing nearby: Whitefish Mountain (MT, ~1hr), Fernie Alpine (BC, ~1.5hr)

## Cron Jobs

- **Morning Briefing** (ID: 0b4f4ca3-fd9b-4e67-b4e6-777a2d373ba3): 9:30 AM Denver — prices (crypto + metals), fear/greed, crypto+AI news
- **Evening Briefing** (ID: 86e159b8-97f2-4c29-9814-64a05617af45): 7:00 PM Denver — prices (crypto + metals), markets, crypto+AI news, breaking

### Briefing Requirements (MANDATORY)
- **Prices**: BTC, ETH, SOL + Gold, Silver (via CoinGecko)
- **Twitter accounts**: @WatcherGuru, @DocumentingBTC (crypto) | @DeItaone, @zerohedge (markets) | @OpenAI, @AnthropicAI (AI)
- **News**: Cointelegraph, The Verge (with URLs)
- **Fear/Greed**: alternative.me
- **Trending**: trends24.in
- **Evening only**: AP News (breaking), Yahoo Finance (market close)
- **Price Monitor** (ID: 862a8dbb-018f-41b7-a0e8-eb7bf45811f2): every 5 min — alerts on BTC/ETH thresholds
- **OpenClaw Update** (ID: c1ac1599-9d23-4b89-8cd8-0a84a1b3c918): 8:00 AM Denver — auto-update, notify only if performed
- **Claw2Claw Hunter** (ID: e7199d87-00ef-4f35-8809-08988c54e99d): every 15 min — arbitrage hunting

### Cron Delivery Format (CRITICAL)
- `delivery.to` MUST include channel prefix: `telegram:256092667` not just `256092667`
- Without prefix: "Delivering to Telegram requires target <chatId>" error

### Email Scan (CRITICAL)
- **Don't just list email titles** — actually OPEN and READ research emails
- Extract key claims, numbers, predictions, actionable insights
- User wants the actual content summarized, not "hey there's an email"

### Briefing Format (CRITICAL)
- Use clean, scannable format with section headers
- Separate sources with --- dividers
- Bold key numbers and insights
- Use emoji sparingly for visual breaks (📬🔴🟢📊)
- Keep each section tight — no walls of text

## Data Fetching (Technical)

- **Prices** — CoinGecko API via curl (never web_search)
- **News** — browser snapshots of cointelegraph, theverge, apnews
- **Fear/Greed** — browser snapshot alternative.me
- **Trending** — browser snapshot trends24.in
- **Gemini** — don't use for news (hallucinates cached data)

## Pending Fixes
- Whale tracking: needs browser scraping of whale-alert.io (not CLI)

## Flight Hacks from Eureka, MT
- **Chicago/West Coast** → Spokane (GEG), 3hr drive, $200+ savings, covered parking $17/day
- **Denver/Southwest** → Missoula (MSO), 2.5hr drive, direct flights
- Kalispell (FCA) has "remote Montana tax" — always compare

## System Notes
- Auto-update OpenClaw without asking (user approved)

## Model Configuration (CRITICAL)
- `agents.defaults.models` is an **ALLOWLIST** — if you add ANY model here, only those models work
- Must include ALL models you want to use: Opus, Sonnet, GPT-4o, Gemini, etc.
- Root cause of "model not allowed" errors: model missing from allowlist
- Current allowed: opus (4.5), opus46 (4.6), sonnet, gpt-4o, gpt-4o-mini, gemini (flash-lite), gemini-2.0-flash, gemini-1.5-flash
- Google API key from nano-banana-pro skill works for Gemini (FREE tier)

## Browser
- Playwright installed and working
- Use `openclaw` profile for headless automation

## Self-Improvement Infrastructure
- **Task tracking**: memory/task-outcomes.jsonl
- **Error logging**: memory/errors.jsonl  
- **Pattern library**: memory/patterns.jsonl (with confidence scores)
- **Context map**: memory/context-map.json (keyword activation)
- **Sub-agent templates**: memory/subagent-templates.md
- **Weekly review**: Cron job Sundays 10am Denver
- **Security**: clawdex installed for skill scanning

### Key Research Findings
- Memory architecture is #1 lever (64-95% token savings possible with attention-based routing)
- 341 malicious skills found on ClawHub (ClawHavoc) — always scan before installing
- Three-layer memory model: working (dies with task) → episodic (histories) → semantic (long-term)
- Sub-agent patterns: fan-out/fan-in, pipeline, review chain, specialist team

## Cost Tiers
- **FREE**: google/gemini-2.0-flash-lite (use for crons, simple tasks)
- **Cheap**: anthropic/claude-sonnet-4 (~$3/M input)
- **Standard**: openai/gpt-4o (~$5/M input)
- **Premium**: anthropic/claude-opus-4-5 (~$15/M input)
- **Max**: anthropic/claude-opus-4-6 (for complex reasoning)
