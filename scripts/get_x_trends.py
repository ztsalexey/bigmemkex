#!/usr/bin/env python3
"""Get X/Twitter trends directly from X sidebar (no login needed)"""
import os
import sys

def get_trends_from_x(limit=10):
    """Extract trends from X sidebar using Camoufox"""
    try:
        from camoufox.sync_api import Camoufox
    except ImportError:
        print("Error: camoufox not installed", file=sys.stderr)
        return []
    
    try:
        with Camoufox(headless=False, os='linux', humanize=True) as browser:
            page = browser.new_page()
            page.set_viewport_size({'width': 1920, 'height': 1080})
            page.goto('https://x.com/x', timeout=45000)
            page.wait_for_timeout(5000)
            text = page.inner_text('body')
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return []
    
    # Parse trends from the text
    trends = []
    lines = text.split('\n')
    
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Look for trend patterns
        if line in ['Sports · Trending', 'Trending', 'Entertainment · Trending', 
                    'Politics · Trending', 'Business · Trending', 'Technology · Trending']:
            if i + 1 < len(lines):
                trend = lines[i + 1].strip()
                if trend and trend not in ['Show more', "What's happening", 'Trending now']:
                    context = ''
                    if i + 2 < len(lines) and lines[i + 2].strip().startswith('Trending with'):
                        context = lines[i + 2].strip().replace('Trending with ', '')
                    trends.append({'name': trend, 'context': context})
                    i += 2
                    continue
        
        # Also catch "Trending in United States" pattern
        if line.startswith('Trending in'):
            if i + 1 < len(lines):
                trend = lines[i + 1].strip()
                if trend and trend not in ['Show more']:
                    context = ''
                    if i + 2 < len(lines) and lines[i + 2].strip().startswith('Trending with'):
                        context = lines[i + 2].strip().replace('Trending with ', '')
                    trends.append({'name': trend, 'context': context, 'location': line})
                    i += 2
                    continue
        
        i += 1
    
    return trends[:limit]

if __name__ == '__main__':
    trends = get_trends_from_x()
    if not trends:
        print("No trends found")
        sys.exit(1)
    for i, t in enumerate(trends, 1):
        ctx = f" ({t['context']})" if t.get('context') else ""
        print(f"{i}. {t['name']}{ctx}")
