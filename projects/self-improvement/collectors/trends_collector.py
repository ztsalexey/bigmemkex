#!/usr/bin/env python3
"""
Trends Collector - Monitor trending topics from various sources
"""

import requests
import json
import logging
from datetime import datetime, timezone
from typing import List, Dict, Optional
import time
import sys
import os
from urllib.parse import urljoin

# Add parent directories to path for imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.news_db import NewsDatabase

class TrendsCollector:
    """Collect trending topics from various sources"""
    
    def __init__(self, db_path: str = "data/news.db"):
        self.logger = logging.getLogger(__name__)
        self.db = NewsDatabase(db_path)
        
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (compatible; NewsCollector/1.0; +http://openclaw.ai)'
        })
    
    def collect_trends24(self) -> int:
        """Collect trending topics from trends24.in"""
        try:
            self.logger.info("Collecting trends from trends24.in")
            
            # Get trends24.in homepage
            response = self.session.get('https://trends24.in', timeout=30)
            response.raise_for_status()
            
            # Parse trending topics (simplified parsing)
            trends = self._parse_trends24_html(response.text)
            
            collected = 0
            for trend in trends:
                if self.db.store_trend(
                    topic=trend['topic'],
                    source='trends24',
                    rank=trend.get('rank'),
                    volume=trend.get('volume', 0),
                    metadata=trend.get('metadata', {})
                ):
                    collected += 1
            
            self.logger.info(f"Collected {collected} trends from trends24.in")
            self.db.log_collection("trends", "trends24", collected)
            return collected
            
        except Exception as e:
            error_msg = f"Error collecting from trends24.in: {e}"
            self.logger.error(error_msg)
            self.db.log_collection("trends", "trends24", 0, str(e))
            return 0
    
    def _parse_trends24_html(self, html: str) -> List[Dict]:
        """Parse trends24.in HTML to extract trending topics"""
        trends = []
        
        try:
            # Basic HTML parsing - looking for trending hashtags/topics
            import re
            
            # Find hashtag patterns
            hashtag_pattern = r'#([a-zA-Z0-9_]+)'
            hashtags = re.findall(hashtag_pattern, html)
            
            # Remove duplicates and take top trends
            unique_hashtags = list(dict.fromkeys(hashtags))[:20]
            
            for i, hashtag in enumerate(unique_hashtags):
                trends.append({
                    'topic': f"#{hashtag}",
                    'rank': i + 1,
                    'volume': 0,  # trends24.in doesn't provide volume easily
                    'metadata': {
                        'source_type': 'twitter_trending',
                        'detected_via': 'trends24'
                    }
                })
                
        except Exception as e:
            self.logger.error(f"Error parsing trends24.in HTML: {e}")
        
        return trends
    
    def collect_google_trends_rss(self) -> int:
        """Collect from Google Trends RSS feed"""
        try:
            self.logger.info("Collecting from Google Trends RSS")
            
            import feedparser
            
            # Google Trends daily RSS
            feed_url = "https://trends.google.com/trends/trendingsearches/daily/rss?geo=US"
            feed = feedparser.parse(feed_url)
            
            collected = 0
            for entry in feed.entries:
                topic = entry.title
                if self.db.store_trend(
                    topic=topic,
                    source='google_trends',
                    rank=None,
                    volume=0,
                    metadata={
                        'description': getattr(entry, 'description', ''),
                        'link': getattr(entry, 'link', ''),
                        'source_type': 'google_trending_searches'
                    }
                ):
                    collected += 1
            
            self.logger.info(f"Collected {collected} trends from Google Trends")
            self.db.log_collection("trends", "google_trends", collected)
            return collected
            
        except Exception as e:
            error_msg = f"Error collecting Google Trends: {e}"
            self.logger.error(error_msg)
            self.db.log_collection("trends", "google_trends", 0, str(e))
            return 0
    
    def collect_hackernews_trends(self) -> int:
        """Collect trending topics from Hacker News front page"""
        try:
            self.logger.info("Collecting from Hacker News front page")
            
            # Get HN front page stories
            response = self.session.get('https://hacker-news.firebaseio.com/v0/topstories.json')
            response.raise_for_status()
            
            story_ids = response.json()[:20]  # Top 20 stories
            
            collected = 0
            for i, story_id in enumerate(story_ids):
                try:
                    # Get story details
                    story_response = self.session.get(f'https://hacker-news.firebaseio.com/v0/item/{story_id}.json')
                    story_response.raise_for_status()
                    story = story_response.json()
                    
                    if story and story.get('title'):
                        if self.db.store_trend(
                            topic=story['title'],
                            source='hackernews',
                            rank=i + 1,
                            volume=story.get('score', 0),
                            metadata={
                                'url': story.get('url', ''),
                                'by': story.get('by', ''),
                                'comments': story.get('descendants', 0),
                                'source_type': 'tech_news'
                            }
                        ):
                            collected += 1
                    
                    # Rate limiting
                    time.sleep(0.1)
                    
                except Exception as e:
                    self.logger.error(f"Error processing HN story {story_id}: {e}")
                    continue
            
            self.logger.info(f"Collected {collected} trends from Hacker News")
            self.db.log_collection("trends", "hackernews", collected)
            return collected
            
        except Exception as e:
            error_msg = f"Error collecting from Hacker News: {e}"
            self.logger.error(error_msg)
            self.db.log_collection("trends", "hackernews", 0, str(e))
            return 0
    
    def collect_reddit_trending(self) -> int:
        """Collect trending topics from Reddit (via public JSON API)"""
        try:
            self.logger.info("Collecting from Reddit trending")
            
            # Get Reddit front page
            headers = {'User-Agent': 'NewsCollector/1.0'}
            response = self.session.get('https://www.reddit.com/hot.json?limit=25', headers=headers)
            response.raise_for_status()
            
            data = response.json()
            posts = data['data']['children']
            
            collected = 0
            for i, post_data in enumerate(posts):
                post = post_data['data']
                title = post.get('title', '')
                
                if title and not post.get('stickied', False):
                    if self.db.store_trend(
                        topic=title,
                        source='reddit',
                        rank=i + 1,
                        volume=post.get('score', 0),
                        metadata={
                            'subreddit': post.get('subreddit', ''),
                            'url': f"https://reddit.com{post.get('permalink', '')}",
                            'comments': post.get('num_comments', 0),
                            'source_type': 'social_trending'
                        }
                    ):
                        collected += 1
            
            self.logger.info(f"Collected {collected} trends from Reddit")
            self.db.log_collection("trends", "reddit", collected)
            return collected
            
        except Exception as e:
            error_msg = f"Error collecting from Reddit: {e}"
            self.logger.error(error_msg)
            self.db.log_collection("trends", "reddit", 0, str(e))
            return 0
    
    def collect_all_trends(self) -> Dict[str, int]:
        """Collect trends from all sources"""
        results = {}
        total_collected = 0
        
        # Collect from each source
        sources = [
            ('trends24', self.collect_trends24),
            ('google_trends', self.collect_google_trends_rss),
            ('hackernews', self.collect_hackernews_trends),
            ('reddit', self.collect_reddit_trending),
        ]
        
        for source_name, collect_func in sources:
            try:
                collected = collect_func()
                results[source_name] = collected
                total_collected += collected
                
                # Rate limiting between sources
                time.sleep(2)
                
            except Exception as e:
                self.logger.error(f"Error collecting from {source_name}: {e}")
                results[source_name] = 0
        
        self.logger.info(f"Total trends collected: {total_collected}")
        return results
    
    def get_trending_summary(self, hours: int = 6) -> Dict:
        """Get summary of recent trending topics"""
        trends = self.db.get_trending_topics(hours=hours)
        
        # Group by source
        by_source = {}
        for trend in trends:
            source = trend['source']
            if source not in by_source:
                by_source[source] = []
            by_source[source].append(trend)
        
        # Get top trending topics overall
        top_topics = sorted(trends, key=lambda x: x.get('volume', 0), reverse=True)[:10]
        
        return {
            'total_trends': len(trends),
            'by_source': {source: len(items) for source, items in by_source.items()},
            'top_topics': [{'topic': t['topic'], 'source': t['source'], 'volume': t.get('volume', 0)} 
                          for t in top_topics],
            'period_hours': hours
        }

def setup_logging():
    """Setup basic logging"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Trends Collector')
    parser.add_argument('--source', choices=['trends24', 'google', 'hackernews', 'reddit', 'all'], 
                       default='all', help='Specific source to collect from')
    parser.add_argument('--db', default='data/news.db', help='Database path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--summary', action='store_true', help='Show trending summary')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        setup_logging()
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    collector = TrendsCollector(args.db)
    
    if args.summary:
        summary = collector.get_trending_summary(hours=6)
        print("Trending Topics Summary (last 6 hours):")
        print(f"Total trends: {summary['total_trends']}")
        print("By source:", summary['by_source'])
        print("\nTop topics:")
        for topic in summary['top_topics'][:5]:
            print(f"  {topic['topic']} ({topic['source']}) - {topic['volume']} points")
    else:
        if args.source == 'all':
            results = collector.collect_all_trends()
            total = sum(results.values())
            print(f"Collection complete. Total trends: {total}")
            for source, count in results.items():
                print(f"  {source}: {count} trends")
        elif args.source == 'trends24':
            collected = collector.collect_trends24()
            print(f"Collected {collected} trends from trends24.in")
        elif args.source == 'google':
            collected = collector.collect_google_trends_rss()
            print(f"Collected {collected} trends from Google Trends")
        elif args.source == 'hackernews':
            collected = collector.collect_hackernews_trends()
            print(f"Collected {collected} trends from Hacker News")
        elif args.source == 'reddit':
            collected = collector.collect_reddit_trending()
            print(f"Collected {collected} trends from Reddit")