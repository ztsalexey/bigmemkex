# Enhanced News Intelligence System - Plan

## Problem Analysis

Current setup has good foundations but key gaps:
- **Manual news monitoring**: Only heartbeat-based checks of trends24.in
- **No semantic search**: Memory is just daily text files  
- **Limited trend analysis**: No systematic pattern tracking
- **Information loss**: Important context gets buried in daily logs
- **No persistent knowledge base**: Can't build on past insights

## Solution: News Intelligence Hub

A comprehensive system that enhances Kex's ability to:
1. Aggregate news from multiple sources automatically
2. Provide semantic search across all collected information
3. Track trends and patterns over time
4. Build persistent knowledge base of important events
5. Generate intelligent briefings with context

## Architecture

```
news-intelligence/
├── collectors/           # News source scrapers
│   ├── rss_collector.py    # RSS feeds from major sources
│   ├── trends_collector.py # trends24.in scraper  
│   └── twitter_collector.py # Public Twitter monitoring
├── storage/              # Data management
│   ├── news_db.py         # SQLite database for structured storage
│   └── vector_store.py    # Local vector search (sentence-transformers)
├── analysis/             # Intelligence features
│   ├── trend_analyzer.py  # Pattern detection over time
│   ├── summarizer.py      # Intelligent summarization
│   └── classifier.py      # Category/importance scoring
├── api/                  # Interface
│   ├── search.py          # Semantic search interface
│   └── briefing.py        # Automated briefing generation
├── config/
│   ├── sources.yaml       # RSS feeds and data sources
│   └── keywords.yaml      # Monitoring keywords/topics
└── scripts/
    ├── collect.py         # Data collection runner
    ├── search_cli.py      # CLI search interface
    └── brief_cli.py       # Generate briefing
```

## Key Features

1. **Multi-Source Aggregation**
   - RSS feeds from major news outlets
   - trends24.in trending topic monitoring
   - Public Twitter timeline scraping (no auth needed)
   - Configurable keyword tracking

2. **Semantic Search & Storage**
   - Local vector search using sentence-transformers
   - SQLite database for structured metadata
   - Full-text search with context relevance
   - Time-based and topic-based filtering

3. **Trend Analysis**
   - Track story evolution over time
   - Identify emerging patterns
   - Score importance/urgency
   - Connect related events across sources

4. **Intelligent Briefings**  
   - Auto-generate morning/evening briefings
   - Prioritize by relevance and impact
   - Include trend context and background
   - Customizable focus areas (markets, AI, politics, etc.)

5. **Integration with Existing System**
   - Enhance HEARTBEAT.md checks with structured data
   - Feed insights into daily memory files
   - CLI tools for manual queries
   - Export briefings for sharing

## Implementation Plan

### Phase 1: Core Data Pipeline (2 hours)
- [x] Project structure
- [ ] RSS collector for major news sources
- [ ] SQLite database schema  
- [ ] Basic storage/retrieval

### Phase 2: Search & Analysis (1 hour)
- [ ] Local vector search setup
- [ ] Trend analysis engine
- [ ] CLI search interface

### Phase 3: Intelligence Features (1 hour)  
- [ ] Automated briefing generation
- [ ] Integration with heartbeat system
- [ ] Testing with real data

## Success Metrics

- Can aggregate 100+ news items per hour from multiple sources
- Search responds in <2 seconds for semantic queries  
- Briefings highlight 5-10 key stories with context
- System runs autonomously with minimal token usage
- Clear improvement in news awareness and response speed

## Next Steps

Start with Phase 1 - build the core data pipeline.