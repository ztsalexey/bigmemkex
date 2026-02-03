#!/usr/bin/env python3
"""
News Database - SQLite storage for structured news data
"""

import sqlite3
import json
import hashlib
from datetime import datetime, timezone
from typing import List, Dict, Optional, Any
from dataclasses import dataclass, asdict
import logging

@dataclass
class NewsItem:
    """Structured news item"""
    title: str
    url: str
    content: str
    source: str
    category: str
    published_at: datetime
    collected_at: datetime
    importance_score: float = 0.0
    keywords: List[str] = None
    metadata: Dict[str, Any] = None
    content_hash: str = ""
    
    def __post_init__(self):
        if self.keywords is None:
            self.keywords = []
        if self.metadata is None:
            self.metadata = {}
        if not self.content_hash:
            self.content_hash = self.generate_hash()
    
    def generate_hash(self) -> str:
        """Generate unique hash for deduplication"""
        content = f"{self.title}|{self.url}|{self.source}"
        return hashlib.md5(content.encode()).hexdigest()

class NewsDatabase:
    """SQLite database for news storage and retrieval"""
    
    def __init__(self, db_path: str = "data/news.db"):
        self.db_path = db_path
        self.logger = logging.getLogger(__name__)
        self._init_database()
    
    def _init_database(self):
        """Initialize database schema"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS news_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL,
                    content TEXT NOT NULL,
                    source TEXT NOT NULL,
                    category TEXT NOT NULL,
                    published_at TIMESTAMP NOT NULL,
                    collected_at TIMESTAMP NOT NULL,
                    importance_score REAL DEFAULT 0.0,
                    keywords TEXT,  -- JSON array
                    metadata TEXT,  -- JSON object
                    content_hash TEXT UNIQUE NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS trends (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    topic TEXT NOT NULL,
                    source TEXT NOT NULL,
                    rank INTEGER,
                    volume INTEGER DEFAULT 0,
                    detected_at TIMESTAMP NOT NULL,
                    metadata TEXT,  -- JSON object
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS collections (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    collection_date DATE NOT NULL,
                    source_type TEXT NOT NULL,
                    source_name TEXT NOT NULL,
                    items_collected INTEGER DEFAULT 0,
                    status TEXT DEFAULT 'success',
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Create indexes for performance
            conn.execute("CREATE INDEX IF NOT EXISTS idx_news_published ON news_items(published_at)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_news_category ON news_items(category)")  
            conn.execute("CREATE INDEX IF NOT EXISTS idx_news_importance ON news_items(importance_score)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_news_source ON news_items(source)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_trends_detected ON trends(detected_at)")
    
    def store_news_item(self, item: NewsItem) -> bool:
        """Store news item, return True if new item, False if duplicate"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    INSERT OR IGNORE INTO news_items 
                    (title, url, content, source, category, published_at, 
                     collected_at, importance_score, keywords, metadata, content_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    item.title, item.url, item.content, item.source, item.category,
                    item.published_at, item.collected_at, item.importance_score,
                    json.dumps(item.keywords), json.dumps(item.metadata), 
                    item.content_hash
                ))
                return conn.total_changes > 0
        except Exception as e:
            self.logger.error(f"Error storing news item: {e}")
            return False
    
    def store_trend(self, topic: str, source: str, rank: int = None, 
                   volume: int = 0, metadata: Dict = None) -> bool:
        """Store trending topic"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    INSERT INTO trends (topic, source, rank, volume, detected_at, metadata)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    topic, source, rank, volume, 
                    datetime.now(timezone.utc), 
                    json.dumps(metadata or {})
                ))
                return True
        except Exception as e:
            self.logger.error(f"Error storing trend: {e}")
            return False
    
    def log_collection(self, source_type: str, source_name: str, 
                      items_collected: int, error: str = None):
        """Log collection run for monitoring"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO collections 
                (collection_date, source_type, source_name, items_collected, status, error_message)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                datetime.now().date(), source_type, source_name, 
                items_collected, 'error' if error else 'success', error
            ))
    
    def get_recent_news(self, hours: int = 24, category: str = None, 
                       min_importance: float = 0.0, limit: int = 50) -> List[Dict]:
        """Retrieve recent news items"""
        query = """
            SELECT title, url, content, source, category, published_at, 
                   importance_score, keywords, metadata
            FROM news_items 
            WHERE published_at > datetime('now', '-{} hours')
        """.format(hours)
        
        params = []
        if category:
            query += " AND category = ?"
            params.append(category)
        if min_importance > 0:
            query += " AND importance_score >= ?"
            params.append(min_importance)
            
        query += " ORDER BY importance_score DESC, published_at DESC LIMIT ?"
        params.append(limit)
        
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            results = conn.execute(query, params).fetchall()
            
        return [dict(row) for row in results]
    
    def get_trending_topics(self, hours: int = 24, source: str = None) -> List[Dict]:
        """Get recent trending topics"""
        query = """
            SELECT topic, source, rank, volume, detected_at, metadata
            FROM trends 
            WHERE detected_at > datetime('now', '-{} hours')
        """.format(hours)
        
        params = []
        if source:
            query += " AND source = ?"
            params.append(source)
            
        query += " ORDER BY detected_at DESC, rank ASC"
        
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            results = conn.execute(query, params).fetchall()
            
        return [dict(row) for row in results]
    
    def search_news(self, query: str, category: str = None, 
                   days: int = 30, limit: int = 20) -> List[Dict]:
        """Basic text search in news content"""
        search_query = """
            SELECT title, url, content, source, category, published_at,
                   importance_score, keywords, metadata
            FROM news_items 
            WHERE (title LIKE ? OR content LIKE ?)
            AND published_at > datetime('now', '-{} days')
        """.format(days)
        
        search_term = f"%{query}%"
        params = [search_term, search_term]
        
        if category:
            search_query += " AND category = ?"
            params.append(category)
            
        search_query += " ORDER BY importance_score DESC, published_at DESC LIMIT ?"
        params.append(limit)
        
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            results = conn.execute(search_query, params).fetchall()
            
        return [dict(row) for row in results]
    
    def get_stats(self) -> Dict:
        """Get database statistics"""
        with sqlite3.connect(self.db_path) as conn:
            stats = {}
            
            # News items stats
            result = conn.execute("SELECT COUNT(*) FROM news_items").fetchone()
            stats['total_news_items'] = result[0]
            
            result = conn.execute("""
                SELECT COUNT(*) FROM news_items 
                WHERE published_at > datetime('now', '-24 hours')
            """).fetchone()
            stats['news_items_24h'] = result[0]
            
            # Category breakdown
            results = conn.execute("""
                SELECT category, COUNT(*) 
                FROM news_items 
                GROUP BY category 
                ORDER BY COUNT(*) DESC
            """).fetchall()
            stats['by_category'] = dict(results)
            
            # Trends stats
            result = conn.execute("SELECT COUNT(*) FROM trends").fetchone() 
            stats['total_trends'] = result[0]
            
            result = conn.execute("""
                SELECT COUNT(*) FROM trends 
                WHERE detected_at > datetime('now', '-24 hours')
            """).fetchone()
            stats['trends_24h'] = result[0]
            
        return stats

if __name__ == "__main__":
    # Test the database
    import os
    os.makedirs("data", exist_ok=True)
    
    db = NewsDatabase()
    
    # Test storing a news item
    test_item = NewsItem(
        title="Test Article",
        url="https://example.com/test",
        content="This is test content for the news database.",
        source="Test Source", 
        category="tech",
        published_at=datetime.now(timezone.utc),
        collected_at=datetime.now(timezone.utc),
        importance_score=5.0,
        keywords=["test", "database"],
        metadata={"test": True}
    )
    
    success = db.store_news_item(test_item)
    print(f"Stored test item: {success}")
    
    # Test retrieving recent news
    recent = db.get_recent_news(hours=1)
    print(f"Found {len(recent)} recent items")
    
    # Test storing a trend
    db.store_trend("AI Revolution", "test", rank=1, volume=1000)
    trends = db.get_trending_topics(hours=1)
    print(f"Found {len(trends)} recent trends")
    
    # Show stats
    stats = db.get_stats()
    print("Database stats:", stats)