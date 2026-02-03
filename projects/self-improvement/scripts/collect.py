#!/usr/bin/env python3
"""
News Collection Script - Orchestrates data collection from all sources
"""

import sys
import os
import logging
import argparse
from datetime import datetime
import time
from typing import Dict

# Add parent directories to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from collectors.rss_collector import RSSCollector
from collectors.trends_collector import TrendsCollector
from storage.vector_store import VectorStore
from storage.news_db import NewsDatabase

class NewsCollectionOrchestrator:
    """Orchestrates news collection from all sources"""
    
    def __init__(self, db_path: str = "data/news.db"):
        self.logger = logging.getLogger(__name__)
        self.db = NewsDatabase(db_path)
        self.rss_collector = RSSCollector(db_path=db_path)
        self.trends_collector = TrendsCollector(db_path=db_path)
        self.vector_store = VectorStore(db_path=db_path)
    
    def collect_all(self, index_vectors: bool = True) -> Dict:
        """Run full collection cycle"""
        results = {
            'started_at': datetime.now().isoformat(),
            'rss': {},
            'trends': {},
            'vectors_indexed': 0,
            'total_items': 0,
            'errors': []
        }
        
        self.logger.info("Starting full news collection cycle")
        
        # Collect RSS feeds
        try:
            self.logger.info("Collecting RSS feeds...")
            rss_results = self.rss_collector.collect_all_feeds()
            results['rss'] = rss_results
            results['total_items'] += sum(rss_results.values())
            self.logger.info(f"RSS collection complete: {sum(rss_results.values())} items")
        except Exception as e:
            error_msg = f"RSS collection failed: {e}"
            self.logger.error(error_msg)
            results['errors'].append(error_msg)
        
        # Brief pause between collections
        time.sleep(2)
        
        # Collect trends
        try:
            self.logger.info("Collecting trends...")
            trends_results = self.trends_collector.collect_all_trends()
            results['trends'] = trends_results
            results['total_items'] += sum(trends_results.values())
            self.logger.info(f"Trends collection complete: {sum(trends_results.values())} items")
        except Exception as e:
            error_msg = f"Trends collection failed: {e}"
            self.logger.error(error_msg)
            results['errors'].append(error_msg)
        
        # Index vectors for semantic search
        if index_vectors:
            try:
                self.logger.info("Indexing vectors for semantic search...")
                indexed = self.vector_store.index_news_items(hours=2)  # Index last 2 hours
                results['vectors_indexed'] = indexed
                self.logger.info(f"Vector indexing complete: {indexed} items")
            except Exception as e:
                error_msg = f"Vector indexing failed: {e}"
                self.logger.error(error_msg)
                results['errors'].append(error_msg)
        
        results['completed_at'] = datetime.now().isoformat()
        self.logger.info(f"Collection cycle complete. Total items: {results['total_items']}")
        
        return results
    
    def collect_rss_only(self, category: str = None) -> Dict:
        """Collect only RSS feeds"""
        if category:
            collected = self.rss_collector.collect_category(category)
            return {category: collected}
        else:
            return self.rss_collector.collect_all_feeds()
    
    def collect_trends_only(self) -> Dict:
        """Collect only trends"""
        return self.trends_collector.collect_all_trends()
    
    def get_collection_summary(self, hours: int = 24) -> Dict:
        """Get summary of recent collection activity"""
        # Get database stats
        db_stats = self.db.get_stats()
        
        # Get recent news
        recent_news = self.db.get_recent_news(hours=hours, limit=10)
        
        # Get trending topics
        trends = self.trends_collector.get_trending_summary(hours=hours)
        
        # Get vector store stats
        vector_stats = self.vector_store.get_stats()
        
        return {
            'period_hours': hours,
            'database_stats': db_stats,
            'recent_top_news': [
                {
                    'title': item['title'],
                    'source': item['source'],
                    'category': item['category'],
                    'importance_score': item['importance_score'],
                    'published_at': item['published_at']
                }
                for item in recent_news
            ],
            'trending_summary': trends,
            'vector_store_stats': vector_stats,
            'generated_at': datetime.now().isoformat()
        }

def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

def main():
    parser = argparse.ArgumentParser(description='News Collection Orchestrator')
    parser.add_argument('--action', choices=['all', 'rss', 'trends', 'summary'], 
                       default='all', help='Collection action to perform')
    parser.add_argument('--category', help='RSS category to collect (if action=rss)')
    parser.add_argument('--no-vectors', action='store_true', 
                       help='Skip vector indexing (faster)')
    parser.add_argument('--hours', type=int, default=24,
                       help='Hours for summary reports')
    parser.add_argument('--db', default='data/news.db', help='Database path')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--quiet', '-q', action='store_true', help='Minimal output')
    
    args = parser.parse_args()
    
    setup_logging(args.verbose)
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    orchestrator = NewsCollectionOrchestrator(args.db)
    
    if args.action == 'all':
        results = orchestrator.collect_all(index_vectors=not args.no_vectors)
        
        if not args.quiet:
            print(f"Collection complete at {results['completed_at']}")
            print(f"Total items collected: {results['total_items']}")
            
            if results['rss']:
                print("\nRSS Collection:")
                for source, count in results['rss'].items():
                    print(f"  {source}: {count} items")
            
            if results['trends']:
                print("\nTrends Collection:")
                for source, count in results['trends'].items():
                    print(f"  {source}: {count} trends")
            
            if results['vectors_indexed']:
                print(f"\nVectors indexed: {results['vectors_indexed']}")
            
            if results['errors']:
                print("\nErrors encountered:")
                for error in results['errors']:
                    print(f"  {error}")
        else:
            # Quiet mode - just print summary
            print(f"{results['total_items']} items collected")
    
    elif args.action == 'rss':
        results = orchestrator.collect_rss_only(args.category)
        total = sum(results.values())
        print(f"RSS collection complete: {total} items")
        
        if not args.quiet:
            for source, count in results.items():
                print(f"  {source}: {count} items")
    
    elif args.action == 'trends':
        results = orchestrator.collect_trends_only()
        total = sum(results.values())
        print(f"Trends collection complete: {total} trends")
        
        if not args.quiet:
            for source, count in results.items():
                print(f"  {source}: {count} trends")
    
    elif args.action == 'summary':
        summary = orchestrator.get_collection_summary(hours=args.hours)
        
        print(f"Collection Summary (last {args.hours} hours)")
        print("=" * 50)
        
        db_stats = summary['database_stats']
        print(f"Total news items: {db_stats['total_news_items']}")
        print(f"News items (24h): {db_stats['news_items_24h']}")
        print(f"Total trends: {db_stats['total_trends']}")
        print(f"Trends (24h): {db_stats['trends_24h']}")
        
        print(f"\nBy category:")
        for category, count in db_stats['by_category'].items():
            print(f"  {category}: {count}")
        
        vector_stats = summary['vector_store_stats']
        print(f"\nVector store: {vector_stats['total_vectors']} items indexed")
        
        print(f"\nTop recent news:")
        for item in summary['recent_top_news'][:5]:
            print(f"  {item['title']} ({item['source']}) - {item['importance_score']:.1f}")
        
        trending = summary['trending_summary']
        print(f"\nTop trending topics:")
        for topic in trending['top_topics'][:5]:
            print(f"  {topic['topic']} ({topic['source']})")

if __name__ == "__main__":
    main()