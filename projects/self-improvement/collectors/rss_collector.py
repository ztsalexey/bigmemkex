#!/usr/bin/env python3
"""
RSS Collector - Gather news from RSS feeds
"""

import feedparser
import requests
import yaml
import logging
from datetime import datetime, timezone
from typing import List, Dict
import time
import re
from urllib.parse import urlparse
import sys
import os

# Add parent directories to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.news_db import NewsDatabase, NewsItem

class RSSCollector:
    """Collect news from RSS feeds"""
    
    def __init__(self, config_path: str = "config/sources.yaml", db_path: str = "data/news.db"):
        self.logger = logging.getLogger(__name__)
        self.db = NewsDatabase(db_path)
        
        # Load RSS feed configuration
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (compatible; NewsCollector/1.0; +http://openclaw.ai)'
        })
    
    def collect_from_feed(self, feed_config: Dict) -> int:
        """Collect news from a single RSS feed"""
        feed_name = feed_config['name']
        feed_url = feed_config['url']
        category = feed_config['category']
        
        try:
            self.logger.info(f"Collecting from {feed_name} ({feed_url})")
            
            # Parse RSS feed
            feed = feedparser.parse(feed_url)
            
            if not feed.entries:
                self.logger.warning(f"No entries found in feed: {feed_name}")
                self.db.log_collection("rss", feed_name, 0, "No entries found")
                return 0
                
            collected = 0
            for entry in feed.entries:
                try:
                    news_item = self._parse_rss_entry(entry, feed_name, category)
                    if news_item and self.db.store_news_item(news_item):
                        collected += 1
                except Exception as e:
                    self.logger.error(f"Error parsing entry from {feed_name}: {e}")
                    continue
            
            self.logger.info(f"Collected {collected} new items from {feed_name}")
            self.db.log_collection("rss", feed_name, collected)
            return collected
            
        except Exception as e:
            error_msg = f"Error collecting from {feed_name}: {e}"
            self.logger.error(error_msg)
            self.db.log_collection("rss", feed_name, 0, str(e))
            return 0
    
    def _parse_rss_entry(self, entry, source: str, category: str) -> NewsItem:
        """Parse RSS entry into NewsItem"""
        # Extract title
        title = getattr(entry, 'title', 'No title')
        
        # Extract URL
        url = getattr(entry, 'link', '')
        
        # Extract content (try multiple fields)
        content = ""
        if hasattr(entry, 'content'):
            content = entry.content[0].value if entry.content else ""
        elif hasattr(entry, 'summary'):
            content = entry.summary
        elif hasattr(entry, 'description'):
            content = entry.description
        
        # Clean HTML tags from content
        content = self._clean_html(content)
        
        # Extract published date
        published_at = datetime.now(timezone.utc)
        if hasattr(entry, 'published_parsed') and entry.published_parsed:
            published_at = datetime(*entry.published_parsed[:6], tzinfo=timezone.utc)
        elif hasattr(entry, 'updated_parsed') and entry.updated_parsed:
            published_at = datetime(*entry.updated_parsed[:6], tzinfo=timezone.utc)
        
        # Extract keywords/tags
        keywords = []
        if hasattr(entry, 'tags'):
            keywords = [tag.term for tag in entry.tags if hasattr(tag, 'term')]
        
        # Calculate basic importance score
        importance_score = self._calculate_importance(title, content, keywords, source)
        
        # Build metadata
        metadata = {
            'rss_id': getattr(entry, 'id', url),
            'author': getattr(entry, 'author', ''),
            'source_url': url
        }
        
        return NewsItem(
            title=title,
            url=url,
            content=content,
            source=source,
            category=category,
            published_at=published_at,
            collected_at=datetime.now(timezone.utc),
            importance_score=importance_score,
            keywords=keywords,
            metadata=metadata
        )
    
    def _clean_html(self, text: str) -> str:
        """Remove HTML tags and clean up text"""
        if not text:
            return ""
        
        # Remove HTML tags
        text = re.sub(r'<[^>]+>', '', text)
        
        # Decode HTML entities
        import html
        text = html.unescape(text)
        
        # Clean up whitespace
        text = ' '.join(text.split())
        
        return text
    
    def _calculate_importance(self, title: str, content: str, keywords: List[str], source: str) -> float:
        """Calculate basic importance score for news item"""
        score = 0.0
        text = f"{title} {content}".lower()
        
        # Load keyword configuration
        try:
            with open("config/keywords.yaml", 'r') as f:
                keyword_config = yaml.safe_load(f)
                
            # Check for urgent keywords
            for category, urgent_keywords in keyword_config.get('urgent_keywords', {}).items():
                for keyword in urgent_keywords:
                    if keyword.lower() in text:
                        score += keyword_config['importance_weights']['keyword_match_urgent']
            
            # Check for trending keywords  
            for category, trending_keywords in keyword_config.get('trending_keywords', {}).items():
                for keyword in trending_keywords:
                    if keyword.lower() in text:
                        score += keyword_config['importance_weights']['keyword_match_trending']
            
            # Source tier weighting
            if source.lower() in ['reuters', 'ap', 'bloomberg']:
                score += keyword_config['importance_weights']['source_tier_1']
            elif source.lower() in ['techcrunch', 'coindesk', 'the verge']:
                score += keyword_config['importance_weights']['source_tier_2'] 
            else:
                score += keyword_config['importance_weights']['source_tier_3']
                
            # Freshness bonus (recent = more important)
            score += keyword_config['importance_weights']['freshness_bonus']
            
        except Exception as e:
            self.logger.error(f"Error calculating importance score: {e}")
            score = 1.0  # Default score
        
        return score
    
    def collect_all_feeds(self) -> Dict[str, int]:
        """Collect from all configured RSS feeds"""
        results = {}
        total_collected = 0
        
        for category, feeds in self.config.get('rss_feeds', {}).items():
            self.logger.info(f"Processing {category} feeds...")
            
            for feed_config in feeds:
                collected = self.collect_from_feed(feed_config)
                results[feed_config['name']] = collected
                total_collected += collected
                
                # Be nice to servers
                time.sleep(1)
        
        self.logger.info(f"Total collected: {total_collected} items")
        return results
    
    def collect_category(self, category: str) -> int:
        """Collect from feeds in specific category only"""
        if category not in self.config.get('rss_feeds', {}):
            self.logger.error(f"Category '{category}' not found in configuration")
            return 0
        
        total_collected = 0
        feeds = self.config['rss_feeds'][category]
        
        for feed_config in feeds:
            collected = self.collect_from_feed(feed_config)
            total_collected += collected
            time.sleep(1)
            
        return total_collected

def setup_logging():
    """Setup basic logging"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='RSS News Collector')
    parser.add_argument('--category', help='Collect from specific category only')
    parser.add_argument('--config', default='config/sources.yaml', help='Config file path')
    parser.add_argument('--db', default='data/news.db', help='Database path') 
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        setup_logging()
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    collector = RSSCollector(args.config, args.db)
    
    if args.category:
        collected = collector.collect_category(args.category)
        print(f"Collected {collected} items from {args.category} category")
    else:
        results = collector.collect_all_feeds()
        total = sum(results.values())
        print(f"Collection complete. Total items: {total}")
        
        # Show breakdown by source
        for source, count in results.items():
            print(f"  {source}: {count} items")