#!/usr/bin/env python3
"""
News Briefing CLI - Generate intelligent news briefings
"""

import sys
import os
import logging
import argparse
from datetime import datetime, timedelta
import json
from collections import defaultdict, Counter
from typing import List, Dict

# Add parent directories to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.news_db import NewsDatabase
from storage.vector_store import VectorStore
from collectors.trends_collector import TrendsCollector

class NewsBriefingGenerator:
    """Generate intelligent news briefings"""
    
    def __init__(self, db_path: str = "data/news.db"):
        self.db = NewsDatabase(db_path)
        self.vector_store = VectorStore(db_path=db_path)
        self.trends_collector = TrendsCollector(db_path=db_path)
        self.logger = logging.getLogger(__name__)
    
    def generate_morning_briefing(self, hours: int = 18) -> Dict:
        """Generate morning briefing (news since yesterday evening)"""
        return self._generate_briefing(
            title="Morning News Briefing",
            hours=hours,
            focus_categories=['markets', 'crypto', 'politics', 'tech'],
            max_items_per_category=3,
            include_trends=True,
            min_importance=3.0
        )
    
    def generate_evening_briefing(self, hours: int = 12) -> Dict:
        """Generate evening briefing (news since morning)"""
        return self._generate_briefing(
            title="Evening News Briefing", 
            hours=hours,
            focus_categories=['markets', 'crypto', 'politics', 'tech', 'security'],
            max_items_per_category=3,
            include_trends=True,
            min_importance=2.0
        )
    
    def generate_category_briefing(self, category: str, hours: int = 24) -> Dict:
        """Generate briefing for specific category"""
        return self._generate_briefing(
            title=f"{category.title()} News Briefing",
            hours=hours,
            focus_categories=[category],
            max_items_per_category=10,
            include_trends=True,
            min_importance=1.0
        )
    
    def generate_breaking_news_alert(self, min_importance: float = 8.0, hours: int = 2) -> Dict:
        """Generate breaking news alert for high-importance items"""
        recent_news = self.db.get_recent_news(
            hours=hours,
            min_importance=min_importance,
            limit=10
        )
        
        if not recent_news:
            return {
                'type': 'breaking_news_alert',
                'has_breaking_news': False,
                'generated_at': datetime.now().isoformat()
            }
        
        # Group by category
        by_category = defaultdict(list)
        for item in recent_news:
            by_category[item['category']].append(item)
        
        return {
            'type': 'breaking_news_alert',
            'has_breaking_news': True,
            'total_breaking_items': len(recent_news),
            'categories': {cat: len(items) for cat, items in by_category.items()},
            'top_stories': recent_news[:5],
            'generated_at': datetime.now().isoformat(),
            'period_hours': hours,
            'min_importance_threshold': min_importance
        }
    
    def _generate_briefing(self, title: str, hours: int, focus_categories: List[str],
                          max_items_per_category: int, include_trends: bool = True,
                          min_importance: float = 0.0) -> Dict:
        """Generate a comprehensive briefing"""
        
        briefing = {
            'title': title,
            'generated_at': datetime.now().isoformat(),
            'period_hours': hours,
            'categories': {},
            'summary': {},
            'trends': {} if include_trends else None
        }
        
        total_items = 0
        
        # Collect news by category
        for category in focus_categories:
            category_news = self.db.get_recent_news(
                hours=hours,
                category=category,
                min_importance=min_importance,
                limit=max_items_per_category * 2  # Get extra to filter
            )
            
            if category_news:
                # Take top items by importance
                top_items = category_news[:max_items_per_category]
                
                # Calculate category stats
                importance_scores = [item['importance_score'] for item in category_news]
                sources = Counter([item['source'] for item in category_news])
                
                briefing['categories'][category] = {
                    'total_items': len(category_news),
                    'top_stories': top_items,
                    'avg_importance': sum(importance_scores) / len(importance_scores),
                    'max_importance': max(importance_scores),
                    'top_sources': dict(sources.most_common(3))
                }
                
                total_items += len(category_news)
        
        # Generate summary statistics
        briefing['summary'] = {
            'total_items_analyzed': total_items,
            'categories_with_news': len([cat for cat in briefing['categories'] if briefing['categories'][cat]['total_items'] > 0]),
            'highest_importance_category': max(
                (cat for cat in briefing['categories'] if briefing['categories'][cat]['total_items'] > 0),
                key=lambda cat: briefing['categories'][cat]['max_importance'],
                default=None
            ) if total_items > 0 else None,
        }
        
        # Add trending topics
        if include_trends:
            trends_summary = self.trends_collector.get_trending_summary(hours=hours)
            briefing['trends'] = {
                'total_trends': trends_summary['total_trends'],
                'by_source': trends_summary['by_source'],
                'top_topics': trends_summary['top_topics'][:10]
            }
        
        # Add key themes (simple keyword analysis)
        briefing['key_themes'] = self._extract_key_themes(briefing['categories'])
        
        return briefing
    
    def _extract_key_themes(self, categories: Dict) -> List[Dict]:
        """Extract key themes from news titles"""
        all_titles = []
        
        for category_data in categories.values():
            for item in category_data.get('top_stories', []):
                all_titles.append(item['title'].lower())
        
        # Simple keyword extraction
        import re
        words = []
        for title in all_titles:
            # Extract meaningful words (skip common words)
            title_words = re.findall(r'\b[a-zA-Z]{4,}\b', title)
            words.extend(title_words)
        
        # Count word frequency
        word_counts = Counter(words)
        
        # Remove common news words
        stop_words = {
            'news', 'report', 'reports', 'says', 'said', 'company', 'companies',
            'market', 'stock', 'stocks', 'price', 'prices', 'will', 'new',
            'first', 'year', 'years', 'time', 'could', 'would', 'should'
        }
        
        themes = []
        for word, count in word_counts.most_common(15):
            if word.lower() not in stop_words and count > 1:
                themes.append({
                    'theme': word,
                    'frequency': count,
                    'relevance': count / len(all_titles) if all_titles else 0
                })
        
        return themes[:10]
    
    def format_briefing_text(self, briefing: Dict) -> str:
        """Format briefing as readable text"""
        lines = []
        
        # Title and timestamp
        lines.append(briefing['title'])
        lines.append("=" * len(briefing['title']))
        
        gen_time = datetime.fromisoformat(briefing['generated_at'].replace('Z', '+00:00'))
        lines.append(f"Generated: {gen_time.strftime('%Y-%m-%d %H:%M UTC')}")
        lines.append(f"Period: Last {briefing['period_hours']} hours")
        lines.append("")
        
        # Summary
        summary = briefing['summary']
        lines.append("OVERVIEW")
        lines.append("-" * 20)
        lines.append(f"• {summary['total_items_analyzed']} news items analyzed")
        lines.append(f"• {summary['categories_with_news']} categories with news")
        
        if summary.get('highest_importance_category'):
            lines.append(f"• Highest activity: {summary['highest_importance_category']}")
        lines.append("")
        
        # Key themes
        if briefing.get('key_themes'):
            lines.append("KEY THEMES")
            lines.append("-" * 20)
            for theme in briefing['key_themes'][:5]:
                lines.append(f"• {theme['theme'].title()} ({theme['frequency']} mentions)")
            lines.append("")
        
        # Categories
        for category, data in briefing['categories'].items():
            if data['total_items'] == 0:
                continue
                
            lines.append(f"{category.upper()} ({data['total_items']} items)")
            lines.append("-" * (len(category) + 15))
            
            # Top sources
            top_sources = list(data['top_sources'].keys())[:3]
            lines.append(f"Top sources: {', '.join(top_sources)}")
            lines.append(f"Avg importance: {data['avg_importance']:.1f}")
            lines.append("")
            
            # Top stories
            for i, story in enumerate(data['top_stories'], 1):
                importance = story['importance_score']
                pub_time = story.get('published_at', '')
                try:
                    if isinstance(pub_time, str):
                        pub_date = datetime.fromisoformat(pub_time.replace('Z', '+00:00'))
                        time_str = pub_date.strftime('%m/%d %H:%M')
                    else:
                        time_str = str(pub_time)
                except:
                    time_str = str(pub_time)
                
                lines.append(f"{i}. {story['title']}")
                lines.append(f"   {story['source']} | {time_str} | Importance: {importance:.1f}")
                if story.get('url'):
                    lines.append(f"   {story['url']}")
                lines.append("")
        
        # Trending topics
        if briefing.get('trends') and briefing['trends']['total_trends'] > 0:
            lines.append("TRENDING TOPICS")
            lines.append("-" * 20)
            
            for topic in briefing['trends']['top_topics'][:8]:
                source = topic['source']
                volume = topic.get('volume', 0)
                volume_str = f" ({volume} pts)" if volume > 0 else ""
                lines.append(f"• {topic['topic']} [{source}]{volume_str}")
            lines.append("")
        
        return "\n".join(lines)
    
    def format_briefing_markdown(self, briefing: Dict) -> str:
        """Format briefing as Markdown"""
        lines = []
        
        # Title and metadata
        lines.append(f"# {briefing['title']}")
        lines.append("")
        
        gen_time = datetime.fromisoformat(briefing['generated_at'].replace('Z', '+00:00'))
        lines.append(f"**Generated:** {gen_time.strftime('%Y-%m-%d %H:%M UTC')}  ")
        lines.append(f"**Period:** Last {briefing['period_hours']} hours  ")
        lines.append("")
        
        # Summary
        summary = briefing['summary']
        lines.append("## Overview")
        lines.append("")
        lines.append(f"- **{summary['total_items_analyzed']}** news items analyzed")
        lines.append(f"- **{summary['categories_with_news']}** categories with news")
        
        if summary.get('highest_importance_category'):
            lines.append(f"- **Highest activity:** {summary['highest_importance_category']}")
        lines.append("")
        
        # Key themes
        if briefing.get('key_themes'):
            lines.append("## Key Themes")
            lines.append("")
            for theme in briefing['key_themes'][:5]:
                lines.append(f"- **{theme['theme'].title()}** ({theme['frequency']} mentions)")
            lines.append("")
        
        # Categories
        for category, data in briefing['categories'].items():
            if data['total_items'] == 0:
                continue
                
            lines.append(f"## {category.title()} ({data['total_items']} items)")
            lines.append("")
            
            # Top sources
            top_sources = list(data['top_sources'].keys())[:3]
            lines.append(f"**Top sources:** {', '.join(top_sources)}  ")
            lines.append(f"**Avg importance:** {data['avg_importance']:.1f}  ")
            lines.append("")
            
            # Top stories
            for i, story in enumerate(data['top_stories'], 1):
                importance = story['importance_score']
                pub_time = story.get('published_at', '')
                try:
                    if isinstance(pub_time, str):
                        pub_date = datetime.fromisoformat(pub_time.replace('Z', '+00:00'))
                        time_str = pub_date.strftime('%m/%d %H:%M')
                    else:
                        time_str = str(pub_time)
                except:
                    time_str = str(pub_time)
                
                lines.append(f"### {i}. {story['title']}")
                lines.append("")
                lines.append(f"**Source:** {story['source']} | **Time:** {time_str} | **Importance:** {importance:.1f}")
                
                if story.get('url'):
                    lines.append(f"**URL:** {story['url']}")
                
                lines.append("")
        
        # Trending topics
        if briefing.get('trends') and briefing['trends']['total_trends'] > 0:
            lines.append("## Trending Topics")
            lines.append("")
            
            for topic in briefing['trends']['top_topics'][:8]:
                source = topic['source']
                volume = topic.get('volume', 0)
                volume_str = f" ({volume} pts)" if volume > 0 else ""
                lines.append(f"- **{topic['topic']}** [{source}]{volume_str}")
            lines.append("")
        
        return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description='News Briefing Generator')
    parser.add_argument('--type', choices=['morning', 'evening', 'category', 'breaking'], 
                       default='morning', help='Type of briefing')
    parser.add_argument('--category', help='Category for category briefing')
    parser.add_argument('--hours', type=int, help='Hours to look back (default varies by type)')
    parser.add_argument('--min-importance', type=float, help='Minimum importance threshold')
    
    # Output format
    parser.add_argument('--format', choices=['text', 'markdown', 'json'], 
                       default='text', help='Output format')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    # Setup logging
    level = logging.DEBUG if args.verbose else logging.WARNING
    logging.basicConfig(level=level, format='%(levelname)s: %(message)s')
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    generator = NewsBriefingGenerator()
    
    # Generate briefing
    if args.type == 'morning':
        hours = args.hours or 18
        briefing = generator.generate_morning_briefing(hours=hours)
    
    elif args.type == 'evening':
        hours = args.hours or 12
        briefing = generator.generate_evening_briefing(hours=hours)
    
    elif args.type == 'category':
        if not args.category:
            print("Error: --category required for category briefing")
            return
        hours = args.hours or 24
        briefing = generator.generate_category_briefing(category=args.category, hours=hours)
    
    elif args.type == 'breaking':
        hours = args.hours or 2
        min_importance = args.min_importance or 8.0
        briefing = generator.generate_breaking_news_alert(
            min_importance=min_importance,
            hours=hours
        )
        
        # Handle breaking news alert differently
        if args.format == 'json':
            output = json.dumps(briefing, indent=2, default=str)
        else:
            if briefing['has_breaking_news']:
                output = f"🚨 BREAKING NEWS ALERT 🚨\n\n"
                output += f"{briefing['total_breaking_items']} high-importance items in last {briefing['period_hours']} hours\n\n"
                
                for i, story in enumerate(briefing['top_stories'], 1):
                    output += f"{i}. {story['title']}\n"
                    output += f"   {story['source']} | Importance: {story['importance_score']:.1f}\n"
                    if story.get('url'):
                        output += f"   {story['url']}\n"
                    output += "\n"
            else:
                output = "No breaking news at this time."
        
        # Output breaking news alert
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output)
        else:
            print(output)
        return
    
    # Format regular briefing
    if args.format == 'json':
        output = json.dumps(briefing, indent=2, default=str)
    elif args.format == 'markdown':
        output = generator.format_briefing_markdown(briefing)
    else:
        output = generator.format_briefing_text(briefing)
    
    # Output
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Briefing saved to {args.output}")
    else:
        print(output)

if __name__ == "__main__":
    main()