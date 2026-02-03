#!/usr/bin/env python3
"""
News Search CLI - Command line interface for searching news and trends
"""

import sys
import os
import logging
import argparse
from datetime import datetime, timedelta
import json
from typing import List, Dict

# Add parent directories to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.news_db import NewsDatabase
from storage.vector_store import VectorStore

class NewsSearchCLI:
    """Command line interface for news search"""
    
    def __init__(self, db_path: str = "data/news.db"):
        self.db = NewsDatabase(db_path)
        self.vector_store = VectorStore(db_path=db_path)
        self.logger = logging.getLogger(__name__)
    
    def search_text(self, query: str, category: str = None, days: int = 30, limit: int = 10) -> List[Dict]:
        """Basic text search"""
        results = self.db.search_news(query=query, category=category, days=days, limit=limit)
        return results
    
    def search_semantic(self, query: str, category: str = None, top_k: int = 10, min_score: float = 0.2) -> List[Dict]:
        """Semantic search using vectors"""
        results = self.vector_store.search(query=query, category=category, top_k=top_k, min_score=min_score)
        return results
    
    def search_trends(self, query: str = None, hours: int = 24, source: str = None) -> List[Dict]:
        """Search trending topics"""
        trends = self.db.get_trending_topics(hours=hours, source=source)
        
        if query:
            # Filter trends by query
            query_lower = query.lower()
            trends = [t for t in trends if query_lower in t['topic'].lower()]
        
        return trends
    
    def get_recent_news(self, hours: int = 24, category: str = None, min_importance: float = 0.0, limit: int = 20):
        """Get recent news items"""
        return self.db.get_recent_news(hours=hours, category=category, min_importance=min_importance, limit=limit)
    
    def get_top_stories(self, hours: int = 24, limit: int = 10):
        """Get top stories by importance score"""
        return self.db.get_recent_news(hours=hours, min_importance=5.0, limit=limit)
    
    def find_related_stories(self, url: str, limit: int = 5):
        """Find stories related to a specific URL"""
        # First find the story by URL
        results = self.db.search_news(url, limit=1)
        if not results:
            return []
        
        # Get content hash from metadata
        metadata_str = results[0].get('metadata', '{}')
        try:
            metadata = json.loads(metadata_str)
            content_hash = metadata.get('content_hash')
            if content_hash:
                return self.vector_store.find_similar(content_hash, top_k=limit)
        except:
            pass
        
        return []
    
    def get_category_summary(self, category: str, hours: int = 24):
        """Get summary for specific category"""
        recent_news = self.get_recent_news(hours=hours, category=category, limit=50)
        
        if not recent_news:
            return {
                'category': category,
                'period_hours': hours,
                'total_items': 0,
                'top_stories': [],
                'sources': {},
                'avg_importance': 0.0
            }
        
        # Calculate statistics
        sources = {}
        importance_scores = []
        
        for item in recent_news:
            source = item['source']
            sources[source] = sources.get(source, 0) + 1
            importance_scores.append(item['importance_score'])
        
        return {
            'category': category,
            'period_hours': hours,
            'total_items': len(recent_news),
            'top_stories': recent_news[:10],  # Top 10 by importance
            'sources': sources,
            'avg_importance': sum(importance_scores) / len(importance_scores),
            'max_importance': max(importance_scores),
            'generated_at': datetime.now().isoformat()
        }

def format_news_item(item: Dict, show_content: bool = False, show_url: bool = True):
    """Format news item for display"""
    title = item['title']
    source = item['source']
    category = item.get('category', '')
    importance = item.get('importance_score', 0)
    published = item.get('published_at', '')
    
    # Parse published date for display
    try:
        if isinstance(published, str):
            pub_date = datetime.fromisoformat(published.replace('Z', '+00:00'))
            pub_str = pub_date.strftime('%m/%d %H:%M')
        else:
            pub_str = str(published)
    except:
        pub_str = str(published)
    
    result = f"[{category.upper()}] {title}"
    result += f"\n  Source: {source} | Importance: {importance:.1f} | {pub_str}"
    
    if show_url and item.get('url'):
        result += f"\n  URL: {item['url']}"
    
    if show_content and item.get('content'):
        content = item['content'][:200] + "..." if len(item['content']) > 200 else item['content']
        result += f"\n  Content: {content}"
    
    return result

def format_trend_item(trend: Dict):
    """Format trending topic for display"""
    topic = trend['topic']
    source = trend['source']
    rank = trend.get('rank')
    volume = trend.get('volume', 0)
    detected = trend.get('detected_at', '')
    
    # Parse detected date
    try:
        if isinstance(detected, str):
            det_date = datetime.fromisoformat(detected.replace('Z', '+00:00'))
            det_str = det_date.strftime('%m/%d %H:%M')
        else:
            det_str = str(detected)
    except:
        det_str = str(detected)
    
    result = f"{topic}"
    result += f"\n  Source: {source}"
    if rank:
        result += f" | Rank: #{rank}"
    if volume:
        result += f" | Volume: {volume}"
    result += f" | {det_str}"
    
    return result

def main():
    parser = argparse.ArgumentParser(description='News Search CLI')
    parser.add_argument('query', nargs='?', help='Search query')
    
    # Search type
    search_group = parser.add_mutually_exclusive_group()
    search_group.add_argument('--text', action='store_true', help='Text search (default)')
    search_group.add_argument('--semantic', action='store_true', help='Semantic search')
    search_group.add_argument('--trends', action='store_true', help='Search trends')
    search_group.add_argument('--recent', action='store_true', help='Recent news')
    search_group.add_argument('--top', action='store_true', help='Top stories')
    search_group.add_argument('--related', type=str, help='Find related stories to URL')
    search_group.add_argument('--category-summary', type=str, help='Category summary')
    
    # Filters
    parser.add_argument('--category', help='Filter by category')
    parser.add_argument('--source', help='Filter by source (trends only)')
    parser.add_argument('--hours', type=int, default=24, help='Hours to search back')
    parser.add_argument('--days', type=int, default=7, help='Days to search back (text search)')
    parser.add_argument('--limit', type=int, default=10, help='Number of results')
    parser.add_argument('--min-importance', type=float, default=0.0, help='Minimum importance score')
    parser.add_argument('--min-score', type=float, default=0.2, help='Minimum similarity score (semantic)')
    
    # Output options
    parser.add_argument('--show-content', action='store_true', help='Show content snippets')
    parser.add_argument('--show-url', action='store_true', default=True, help='Show URLs')
    parser.add_argument('--json', action='store_true', help='JSON output')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # Setup logging
    level = logging.DEBUG if args.verbose else logging.WARNING
    logging.basicConfig(level=level, format='%(levelname)s: %(message)s')
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    cli = NewsSearchCLI()
    
    results = []
    
    # Determine search type and execute
    if args.recent:
        results = cli.get_recent_news(
            hours=args.hours,
            category=args.category,
            min_importance=args.min_importance,
            limit=args.limit
        )
        result_type = "recent_news"
    
    elif args.top:
        results = cli.get_top_stories(hours=args.hours, limit=args.limit)
        result_type = "top_stories"
    
    elif args.trends:
        results = cli.search_trends(
            query=args.query,
            hours=args.hours,
            source=args.source
        )
        result_type = "trends"
    
    elif args.semantic:
        if not args.query:
            print("Error: Semantic search requires a query")
            return
        results = cli.search_semantic(
            query=args.query,
            category=args.category,
            top_k=args.limit,
            min_score=args.min_score
        )
        result_type = "semantic_search"
    
    elif args.related:
        results = cli.find_related_stories(url=args.related, limit=args.limit)
        result_type = "related_stories"
    
    elif args.category_summary:
        summary = cli.get_category_summary(category=args.category_summary, hours=args.hours)
        
        if args.json:
            print(json.dumps(summary, indent=2))
        else:
            print(f"Category Summary: {summary['category']} (last {summary['period_hours']} hours)")
            print("=" * 60)
            print(f"Total items: {summary['total_items']}")
            print(f"Average importance: {summary['avg_importance']:.1f}")
            print(f"Max importance: {summary['max_importance']:.1f}")
            
            print(f"\nTop sources:")
            for source, count in sorted(summary['sources'].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"  {source}: {count} items")
            
            print(f"\nTop stories:")
            for item in summary['top_stories'][:5]:
                print(f"  {format_news_item(item, show_content=args.show_content, show_url=args.show_url)}")
                print()
        return
    
    else:
        # Default to text search if query provided
        if args.query:
            results = cli.search_text(
                query=args.query,
                category=args.category,
                days=args.days,
                limit=args.limit
            )
            result_type = "text_search"
        else:
            # Show recent news if no query
            results = cli.get_recent_news(hours=args.hours, limit=args.limit)
            result_type = "recent_news"
    
    # Output results
    if args.json:
        output = {
            'query': args.query,
            'result_type': result_type,
            'total_results': len(results),
            'results': results
        }
        print(json.dumps(output, indent=2, default=str))
    else:
        if not results:
            print("No results found.")
            return
        
        print(f"Found {len(results)} results:")
        print("=" * 60)
        
        for i, result in enumerate(results, 1):
            if result_type == "trends":
                print(f"{i}. {format_trend_item(result)}")
            else:
                print(f"{i}. {format_news_item(result, show_content=args.show_content, show_url=args.show_url)}")
                
                # Show similarity score for semantic search
                if result_type == "semantic_search" and 'similarity' in result:
                    print(f"    Similarity: {result['similarity']:.3f}")
            
            print()

if __name__ == "__main__":
    main()