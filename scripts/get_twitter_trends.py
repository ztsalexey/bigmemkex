#!/usr/bin/env python3
"""Get Twitter/X trends without login using trends24.in"""
import subprocess
import os
import sys

def get_trends(country='united-states', limit=20):
    """Fetch trending topics from trends24.in"""
    
    script = f'''
from camoufox.sync_api import Camoufox
import os

with Camoufox(headless=False, os='linux', humanize=True, persistent_context=True, 
              user_data_dir=os.path.expanduser('~/.openclaw/camoufox-profile')) as browser:
    page = browser.new_page()
    page.goto('https://trends24.in/{country}/', timeout=30000)
    page.wait_for_timeout(3000)
    
    trends = page.query_selector_all('.trend-card__list li a')
    seen = set()
    for t in trends[:{limit * 2}]:
        text = t.inner_text().strip()
        if text and text not in seen:
            seen.add(text)
            print(text)
            if len(seen) >= {limit}:
                break
'''
    
    env = os.environ.copy()
    result = subprocess.run(
        ['bash', '-c', f'''
source ~/.openclaw/workspace/camoufox-env/bin/activate
xvfb-run -a --server-args="-screen 0 1920x1080x24" python3 -c '{script}'
'''],
        capture_output=True, text=True, timeout=60, env=env
    )
    
    if result.returncode != 0:
        print(f"Error: {result.stderr}", file=sys.stderr)
        return []
    
    return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

if __name__ == '__main__':
    country = sys.argv[1] if len(sys.argv) > 1 else 'united-states'
    trends = get_trends(country)
    for i, t in enumerate(trends, 1):
        print(f"{i}. {t}")
