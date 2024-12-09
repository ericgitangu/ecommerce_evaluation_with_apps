from flask import Flask, jsonify
import pika
import logging
from prometheus_client import start_http_server, Counter, Histogram
import time
import os
import sys


sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

app = Flask(__name__)

# Metrics
API_HITS = Counter('api_hits', 'API Hits', ['method', 'endpoint'])
PROCESSING_TIME = Histogram('processing_time_seconds', 'Processing Time', ['endpoint'])

# RabbitMQ configuration
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
QUEUE_NAME = "orders"

# Logging setup
logger = setup_logger('frontend')

def poll_rabbitmq():
    try:
        connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST))
        channel = connection.channel()
        channel.queue_declare(queue=QUEUE_NAME)
        for method_frame, properties, body in channel.consume(QUEUE_NAME, auto_ack=True):
            logger.info(f"Received message: {body.decode('utf-8')}")
            channel.basic_ack(method_frame.delivery_tag)
    except Exception as e:
        logger.error(f"Error polling RabbitMQ: {e}")

@app.route("/")
def home():
    start_time = time.time()
    API_HITS.labels(method='GET', endpoint='/').inc()
    PROCESSING_TIME.labels(endpoint='/').observe(time.time() - start_time)
    logger.info("Frontend Service Running!")
    return jsonify({"message": "Frontend Service Running!"}), 200

@app.route("/metrics")
def metrics():
    from prometheus_client import generate_latest
    logger.info("Metrics request received for frontend service")
    return generate_latest()

@app.route("/health")
def health():
    logger.info("Health check request received for frontend service")
    return jsonify({"status": "healthy"}), 200

def create_app():
    """Application factory function"""
    logger.info("Creating app for Gunicorn: %s", 'frontend-service')
    return app

# For Gunicorn
application = create_app()

if __name__ == "__main__":
    # Start Prometheus metrics server
    start_http_server(8003) # TODO: we are using metrics server with the service's metrics endpoint!
    
    # Start RabbitMQ polling in a separate thread
    import threading
    rabbitmq_thread = threading.Thread(target=poll_rabbitmq, daemon=True)
    rabbitmq_thread.start()
    
    # Start Flask app
    application.run(host="0.0.0.0", port=5004)