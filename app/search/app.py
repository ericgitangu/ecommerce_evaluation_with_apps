import json
from flask import Flask, jsonify, request
from elasticsearch import Elasticsearch
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST, start_http_server, register_metrics
import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

# Initialize Flask app and Elasticsearch client FQDN
app = Flask(__name__)
es = Elasticsearch(hosts=["es = Elasticsearch(hosts=["http://elasticsearch.logging.svc.cluster.local:9200"])
"])

# Elasticsearch index name
INDEX_NAME = "products"

# Initialize Elasticsearch index with data
def initialize_index():
    """
    Load data from search_data.json into Elasticsearch index.
    """
    try:
        # Check if the index already exists
        if not es.indices.exists(index=INDEX_NAME):
            es.indices.create(index=INDEX_NAME)
            print(f"Created index: {INDEX_NAME}")
        
        # Load data from search_data.json
        with open("data/search_data.json", "r") as f:
            data = json.load(f)
        
        # Index each item
        for item in data:
            es.index(index=INDEX_NAME, id=item["id"], document={"name": item["query"]})
        print("Data indexed successfully.")
    except Exception as e:
        print(f"Error initializing index: {e}")

# Initialize the index
initialize_index()

# Define Prometheus metrics
search_requests_total = Counter(
    'search_requests_total', 
    'Total number of search requests'
)
search_errors_total = Counter(
    'search_errors_total', 
    'Total number of failed search requests'
)
search_latency = Histogram(
    'search_latency_seconds',
    'Search request latency in seconds'
)

# Initialize logger
logger = setup_logger('search')

@app.route('/search', methods=['GET'])
def search():
    logger.info("Received search request")
    search_requests_total.inc()
    query = request.args.get('q', '')
    try:
        with search_latency.time():
            result = es.search(index=INDEX_NAME, query={"match": {"name": query}})
        logger.info(f"Search completed for query: {query}")
        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Search error: {str(e)}")
        search_errors_total.inc()
        return jsonify({"error": str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """
    Metrics endpoint for Prometheus.
    Returns actual metrics in Prometheus format.
    """
    logger.info("Metrics request received for search service")
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health', methods=['GET'])
def health():
    logger.info("Health check request received for search service")
    return jsonify({"status": "healthy"}), 200

# Prometheus metrics registration
register_metrics(app, app_version="v1.0.0", app_config="production")

# Run the Flask app
if __name__ == "__main__":
    start_http_server(8003)  # Expose metrics
    app.run(host="0.0.0.0", port=5002)
