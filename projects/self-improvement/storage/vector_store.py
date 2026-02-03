#!/usr/bin/env python3
"""
Vector Store - Local semantic search using sentence transformers
"""

import numpy as np
import json
import pickle
import logging
from datetime import datetime, timezone
from typing import List, Dict, Tuple, Optional
import os
import sys

# Add parent directories to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.news_db import NewsDatabase

class VectorStore:
    """Local vector store for semantic search over news content"""
    
    def __init__(self, db_path: str = "data/news.db", 
                 vector_path: str = "data/vectors.pkl",
                 model_name: str = "all-MiniLM-L6-v2"):
        self.logger = logging.getLogger(__name__)
        self.db = NewsDatabase(db_path)
        self.vector_path = vector_path
        self.model_name = model_name
        
        # Initialize sentence transformer model
        self.model = None
        self.vectors = {}  # content_hash -> vector
        self.metadata = {}  # content_hash -> metadata
        
        self._load_model()
        self._load_vectors()
    
    def _load_model(self):
        """Load sentence transformer model"""
        try:
            from sentence_transformers import SentenceTransformer
            self.logger.info(f"Loading sentence transformer model: {self.model_name}")
            self.model = SentenceTransformer(self.model_name)
            self.logger.info("Model loaded successfully")
        except ImportError:
            self.logger.warning("sentence-transformers not available. Install with: pip install sentence-transformers")
            self.model = None
        except Exception as e:
            self.logger.error(f"Error loading sentence transformer model: {e}")
            self.model = None
    
    def _load_vectors(self):
        """Load existing vectors from disk"""
        if os.path.exists(self.vector_path):
            try:
                with open(self.vector_path, 'rb') as f:
                    data = pickle.load(f)
                    self.vectors = data.get('vectors', {})
                    self.metadata = data.get('metadata', {})
                self.logger.info(f"Loaded {len(self.vectors)} existing vectors")
            except Exception as e:
                self.logger.error(f"Error loading vectors: {e}")
                self.vectors = {}
                self.metadata = {}
    
    def _save_vectors(self):
        """Save vectors to disk"""
        try:
            os.makedirs(os.path.dirname(self.vector_path), exist_ok=True)
            with open(self.vector_path, 'wb') as f:
                pickle.dump({
                    'vectors': self.vectors,
                    'metadata': self.metadata
                }, f)
            self.logger.info(f"Saved {len(self.vectors)} vectors to disk")
        except Exception as e:
            self.logger.error(f"Error saving vectors: {e}")
    
    def index_news_items(self, hours: int = 24, force_reindex: bool = False) -> int:
        """Index recent news items for semantic search"""
        if not self.model:
            self.logger.warning("No sentence transformer model available")
            return 0
        
        # Get recent news items from database
        news_items = self.db.get_recent_news(hours=hours, limit=1000)
        
        indexed = 0
        texts_to_encode = []
        metadata_to_store = []
        
        for item in news_items:
            content_hash = item.get('metadata', {}).get('content_hash')
            if not content_hash:
                # Generate hash if missing
                import hashlib
                content = f"{item['title']}|{item['url']}|{item['source']}"
                content_hash = hashlib.md5(content.encode()).hexdigest()
            
            # Skip if already indexed
            if content_hash in self.vectors and not force_reindex:
                continue
            
            # Prepare text for encoding
            text = f"{item['title']} {item['content']}"
            texts_to_encode.append(text)
            
            # Store metadata
            metadata_to_store.append({
                'content_hash': content_hash,
                'title': item['title'],
                'url': item['url'],
                'source': item['source'],
                'category': item['category'],
                'published_at': item['published_at'],
                'importance_score': item['importance_score']
            })
        
        if not texts_to_encode:
            self.logger.info("No new items to index")
            return 0
        
        try:
            # Encode texts in batch
            self.logger.info(f"Encoding {len(texts_to_encode)} texts...")
            vectors = self.model.encode(texts_to_encode, convert_to_numpy=True)
            
            # Store vectors and metadata
            for vector, metadata in zip(vectors, metadata_to_store):
                content_hash = metadata['content_hash']
                self.vectors[content_hash] = vector
                self.metadata[content_hash] = metadata
                indexed += 1
            
            # Save to disk
            self._save_vectors()
            self.logger.info(f"Indexed {indexed} new items")
            
        except Exception as e:
            self.logger.error(f"Error encoding texts: {e}")
        
        return indexed
    
    def search(self, query: str, top_k: int = 10, 
               category: str = None, min_score: float = 0.0) -> List[Dict]:
        """Semantic search for news items"""
        if not self.model or not self.vectors:
            self.logger.warning("No model or vectors available for search")
            return []
        
        try:
            # Encode query
            query_vector = self.model.encode([query], convert_to_numpy=True)[0]
            
            # Calculate similarities
            similarities = []
            for content_hash, vector in self.vectors.items():
                # Cosine similarity
                similarity = np.dot(query_vector, vector) / (np.linalg.norm(query_vector) * np.linalg.norm(vector))
                
                metadata = self.metadata.get(content_hash, {})
                
                # Filter by category if specified
                if category and metadata.get('category') != category:
                    continue
                
                # Filter by minimum score
                if similarity < min_score:
                    continue
                
                similarities.append({
                    'content_hash': content_hash,
                    'similarity': float(similarity),
                    **metadata
                })
            
            # Sort by similarity and return top results
            similarities.sort(key=lambda x: x['similarity'], reverse=True)
            return similarities[:top_k]
            
        except Exception as e:
            self.logger.error(f"Error during search: {e}")
            return []
    
    def find_similar(self, content_hash: str, top_k: int = 5) -> List[Dict]:
        """Find items similar to a specific news item"""
        if content_hash not in self.vectors:
            self.logger.warning(f"Content hash {content_hash} not found in vectors")
            return []
        
        try:
            target_vector = self.vectors[content_hash]
            similarities = []
            
            for other_hash, other_vector in self.vectors.items():
                if other_hash == content_hash:
                    continue
                
                # Cosine similarity
                similarity = np.dot(target_vector, other_vector) / (np.linalg.norm(target_vector) * np.linalg.norm(other_vector))
                
                metadata = self.metadata.get(other_hash, {})
                similarities.append({
                    'content_hash': other_hash,
                    'similarity': float(similarity),
                    **metadata
                })
            
            # Sort by similarity and return top results
            similarities.sort(key=lambda x: x['similarity'], reverse=True)
            return similarities[:top_k]
            
        except Exception as e:
            self.logger.error(f"Error finding similar items: {e}")
            return []
    
    def get_topic_clusters(self, num_clusters: int = 10) -> Dict:
        """Basic clustering of news topics"""
        if not self.vectors:
            return {}
        
        try:
            from sklearn.cluster import KMeans
            
            # Get all vectors
            vectors = list(self.vectors.values())
            content_hashes = list(self.vectors.keys())
            
            # Perform clustering
            kmeans = KMeans(n_clusters=min(num_clusters, len(vectors)), random_state=42)
            cluster_labels = kmeans.fit_predict(vectors)
            
            # Group by clusters
            clusters = {}
            for i, (content_hash, label) in enumerate(zip(content_hashes, cluster_labels)):
                if label not in clusters:
                    clusters[label] = []
                
                metadata = self.metadata.get(content_hash, {})
                clusters[label].append({
                    'content_hash': content_hash,
                    'title': metadata.get('title', ''),
                    'source': metadata.get('source', ''),
                    'category': metadata.get('category', ''),
                    'importance_score': metadata.get('importance_score', 0)
                })
            
            # Sort clusters by average importance
            for cluster_id in clusters:
                clusters[cluster_id].sort(key=lambda x: x['importance_score'], reverse=True)
            
            return clusters
            
        except ImportError:
            self.logger.warning("scikit-learn not available for clustering")
            return {}
        except Exception as e:
            self.logger.error(f"Error clustering topics: {e}")
            return {}
    
    def get_stats(self) -> Dict:
        """Get vector store statistics"""
        return {
            'total_vectors': len(self.vectors),
            'total_metadata': len(self.metadata),
            'model_name': self.model_name,
            'model_available': self.model is not None,
            'vector_file_exists': os.path.exists(self.vector_path),
            'categories': list(set(meta.get('category', '') for meta in self.metadata.values())),
            'sources': list(set(meta.get('source', '') for meta in self.metadata.values()))
        }
    
    def cleanup_old_vectors(self, days: int = 30):
        """Remove vectors older than specified days"""
        cutoff_date = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        cutoff_date = cutoff_date.replace(day=cutoff_date.day - days)
        
        removed = 0
        to_remove = []
        
        for content_hash, metadata in self.metadata.items():
            published_str = metadata.get('published_at', '')
            try:
                published_date = datetime.fromisoformat(published_str.replace('Z', '+00:00'))
                if published_date < cutoff_date:
                    to_remove.append(content_hash)
            except:
                continue
        
        for content_hash in to_remove:
            if content_hash in self.vectors:
                del self.vectors[content_hash]
            if content_hash in self.metadata:
                del self.metadata[content_hash]
            removed += 1
        
        if removed > 0:
            self._save_vectors()
            self.logger.info(f"Removed {removed} old vectors")
        
        return removed

def setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Vector Store Manager')
    parser.add_argument('--index', action='store_true', help='Index recent news items')
    parser.add_argument('--search', type=str, help='Search for news items')
    parser.add_argument('--stats', action='store_true', help='Show statistics')
    parser.add_argument('--cleanup', type=int, help='Remove vectors older than N days')
    parser.add_argument('--hours', type=int, default=24, help='Hours of recent news to index')
    parser.add_argument('--top-k', type=int, default=10, help='Number of search results')
    parser.add_argument('--category', type=str, help='Filter by category')
    
    args = parser.parse_args()
    
    setup_logging()
    
    # Ensure data directory exists
    os.makedirs("data", exist_ok=True)
    
    vector_store = VectorStore()
    
    if args.stats:
        stats = vector_store.get_stats()
        print("Vector Store Statistics:")
        for key, value in stats.items():
            print(f"  {key}: {value}")
    
    elif args.index:
        indexed = vector_store.index_news_items(hours=args.hours)
        print(f"Indexed {indexed} news items")
    
    elif args.search:
        results = vector_store.search(args.search, top_k=args.top_k, category=args.category)
        print(f"Search results for '{args.search}':")
        for i, result in enumerate(results, 1):
            print(f"{i}. {result['title']} ({result['source']}) - {result['similarity']:.3f}")
            if result.get('url'):
                print(f"   URL: {result['url']}")
            print()
    
    elif args.cleanup:
        removed = vector_store.cleanup_old_vectors(days=args.cleanup)
        print(f"Removed {removed} old vectors")
    
    else:
        print("No action specified. Use --help for options.")