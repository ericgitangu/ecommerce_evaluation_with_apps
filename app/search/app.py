import json
from flask import Flask, jsonify, request
from elasticsearch import Elasticsearch
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST, start_http_server
import os
import sys
import time
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

# Initialize Flask app
app = Flask(__name__)

# Initialize logger
logger = setup_logger('search')

# Elasticsearch configuration
ES_HOST = os.getenv('ELASTICSEARCH_HOST', 'elasticsearch.logging.svc.cluster.local')
ES_PORT = os.getenv('ELASTICSEARCH_PORT', '9200')
ES_URL = f"http://{ES_HOST}:{ES_PORT}"

# Initialize Elasticsearch client with retry configuration
es = Elasticsearch(
    [ES_URL],
    retry_on_timeout=True,
    max_retries=3,
    timeout=30
)

# Elasticsearch index name
INDEX_NAME = "products"

# Define Prometheus metrics
REQUEST_COUNT = Counter(
    'request_count', 'App Request Count',
    ['app_name', 'method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'request_latency_seconds', 'Request latency',
    ['app_name', 'endpoint']
)
SEARCH_ERRORS = Counter(
    'search_errors_total',
    'Total number of search errors',
    ['error_type']
)

def initialize_index():
    """
    Initialize Elasticsearch index with sample data
    """
    try:
        # Check if the index already exists
        if not es.indices.exists(index=INDEX_NAME):
            # Create index with proper mappings
            mappings = {
                "mappings": {
                    "properties": {
                        "name": {"type": "text"},
                        "description": {"type": "text"},
                        "price": {"type": "float"},
                        "category": {"type": "keyword"}
                    }
                }
            }
            es.indices.create(index=INDEX_NAME, body=mappings)
            logger.info(f"Created index: {INDEX_NAME}")
            
            # Load sample data
            try:
                with open("data/search_data.json", "r") as f:
                    data = json.load(f)
                
                # Bulk index the data
                bulk_data = []
                for item in data:
                    bulk_data.extend([
                        {"index": {"_index": INDEX_NAME, "_id": item["id"]}},
                        {"name": item["query"]}
                    ])
                
                if bulk_data:
                    es.bulk(index=INDEX_NAME, body=bulk_data, refresh=True)
                logger.info("Sample data indexed successfully")
                
            except FileNotFoundError:
                logger.warning("search_data.json not found, skipping sample data")
            except json.JSONDecodeError:
                logger.error("Invalid JSON in search_data.json")
                SEARCH_ERRORS.labels(error_type="json_decode").inc()
    except Exception as e:
        logger.error(f"Error initializing Elasticsearch index: {str(e)}")
        SEARCH_ERRORS.labels(error_type="es_init").inc()
        raise

@app.route('/search', methods=['GET'])
def search():
    """
    Search endpoint: search for products with Elasticsearch
    """
    start_time = time.time()
    query = request.args.get('q', '')
    
    if not query:
        REQUEST_COUNT.labels(app_name='search', method='GET', endpoint='/search', http_status=400).inc()
        return jsonify({"error": "Query parameter 'q' is required"}), 400
    
    try:
        search_query = {
            "query": {
                "multi_match": {
                    "query": query,
                    "fields": ["name^2", "description"],
                    "fuzziness": "AUTO"
                }
            }
        }
        
        result = es.search(index=INDEX_NAME, body=search_query)
        
        REQUEST_LATENCY.labels(app_name='search', endpoint='/search').observe(time.time() - start_time)
        REQUEST_COUNT.labels(app_name='search', method='GET', endpoint='/search', http_status=200).inc()
        
        logger.info(f"Search completed for query: {query}")
        return jsonify(result['hits']), 200
        
    except Exception as e:
        logger.error(f"Search error: {str(e)}")
        SEARCH_ERRORS.labels(error_type="search").inc()
        REQUEST_COUNT.labels(app_name='search', method='GET', endpoint='/search', http_status=500).inc()
        return jsonify({"error": "Search operation failed"}), 500

@app.route('/metrics')
def metrics():
    """
    Metrics endpoint for Prometheus
    """
    logger.info("Metrics endpoint called - search service")
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health')
def health():
    """
    Health check endpoint
    """
    logger.info("Health check endpoint called - search service")
    try:
        # Check Elasticsearch connection
        if es.ping():
            logger.info("Elasticsearch ping successful")
            # Check if index exists
            if es.indices.exists(index=INDEX_NAME):
                logger.info(f"Index {INDEX_NAME} exists")
                return jsonify({
                    "status": "healthy",
                    "elasticsearch": "connected",
                    "index": "exists"
                }), 200
            else:
                logger.warning(f"Index {INDEX_NAME} is missing")
                return jsonify({
                    "status": "degraded",
                    "elasticsearch": "connected",
                    "index": "missing"
                }), 200
        else:
            logger.error("Elasticsearch ping failed")
            return jsonify({
                "status": "unhealthy",
                "elasticsearch": "disconnected"
            }), 200 # TODO: change to 500 to ensure our health check is working
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 200 # TODO: change to 500 to ensure our health check is working

def create_app():
    """
    Application factory function
    """
    logger.info("Creating app for Gunicorn: %s", 'search-service')
    return app

# For Gunicorn
application = create_app()

if __name__ == "__main__":
    # Initialize Elasticsearch index
    initialize_index()
    
    # Start metrics server - TODO: we are using metrics server with the service's metrics endpoint!
    # start_http_server(8003)
    
    # Start Flask app
    application.run(host="0.0.0.0", port=5002)