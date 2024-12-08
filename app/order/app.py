from flask import Flask, jsonify, request
import pika
import psycopg2
from prometheus_client import start_http_server, Counter, Histogram, register_metrics, CONTENT_TYPE_LATEST
import os
import logging
import time
import sys
import uuid
from datetime import datetime
import json
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

app = Flask(__name__)

# Initialize logger
logger = setup_logger('order')

# Metrics
API_HITS = Counter('api_hits', 'API Hits', ['method', 'endpoint'])
PROCESSING_TIME = Histogram('processing_time_seconds', 'Processing Time', ['endpoint'])

# Database connection
DATABASE_URL = os.getenv("DATABASE_URL", f"postgresql://{os.getenv('POSTGRES_USERNAME', 'postgres')}:{os.getenv('POSTGRES_PASSWORD', '')}@localhost:5432/postgres")
db_connection = psycopg2.connect(DATABASE_URL)

# RabbitMQ connection
RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'rabbitmq')

# Add this function to initialize the database
def init_db():
    try:
        with db_connection.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    id SERIAL PRIMARY KEY,
                    order_id VARCHAR(255) NOT NULL,
                    product VARCHAR(255) NOT NULL,
                    quantity INTEGER NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
        db_connection.commit()
        logging.info("Database initialized successfully")
    except Exception as e:
        logging.error(f"Error initializing database: {str(e)}")
        raise

# Publish to RabbitMQ
def publish_to_queue(message):
    try:
        connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST))
        channel = connection.channel()
        channel.queue_declare(queue='orders')
        channel.basic_publish(
            exchange='',
            routing_key='orders',
            body=message
        )
        logger.info(f"Published message to orders queue: {message}")
        connection.close()
    except Exception as e:
        logger.error(f"Error publishing to RabbitMQ: {str(e)}")

@app.route('/')
def home():
    start_time = time.time()
    API_HITS.labels(method='GET', endpoint='/').inc()
    PROCESSING_TIME.labels(endpoint='/').observe(time.time() - start_time)
    return jsonify({"message": "Order Service Running"}), 200

@app.route('/create-order', methods=['POST'])
def create_order():
    logger.info("Received new order request")
    start_time = time.time()
    API_HITS.labels(method='POST', endpoint='/create-order').inc()
    
    try:
        data = request.json
        if not data or not all(k in data for k in ["order_id", "product", "quantity"]):
            logger.warning("Invalid order request - missing required fields")
            return jsonify({"status": "error", "message": "Missing required fields"}), 400
        
        if not isinstance(data["quantity"], int) or data["quantity"] <= 0:
            return jsonify({"status": "error", "message": "Invalid quantity"}), 400

        # Publish message to RabbitMQ
        connection = None
        try:
            connection = pika.BlockingConnection(pika.ConnectionParameters(
                host=RABBITMQ_HOST,
                connection_attempts=3,
                retry_delay=5
            ))
            channel = connection.channel()
            channel.queue_declare(queue='orders', durable=True)  # Make queue durable
            channel.basic_publish(
                exchange='',
                routing_key='orders',
                body=str(data),
                properties=pika.BasicProperties(delivery_mode=2)  # Make message persistent
            )
        finally:
            if connection and not connection.is_closed:
                connection.close()

        # Insert order into PostgreSQL
        with db_connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO orders (order_id, product, quantity) VALUES (%s, %s, %s)",
                (data["order_id"], data["product"], data["quantity"])
            )
        db_connection.commit()

        PROCESSING_TIME.labels(endpoint='/create-order').observe(time.time() - start_time)
        logger.info(f"Order {data['order_id']} processed successfully")
        return jsonify({"status": "success", "message": "order created"}), 201

    except psycopg2.Error as e:
        db_connection.rollback()
        logging.error(f"Database error: {str(e)}")
        return jsonify({"status": "error", "message": "Database error occurred"}), 500
    except pika.exceptions.AMQPError as e:
        logging.error(f"RabbitMQ error: {str(e)}")
        return jsonify({"status": "error", "message": "Message queue error occurred"}), 500
    except Exception as e:
        logger.error(f"Error processing order: {str(e)}")
        return jsonify({"status": "error", "message": "An unexpected error occurred"}), 500

@app.route('/metrics')
def metrics():
    from prometheus_client import generate_latest
    logger.info("Metrics request received for order service")
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health')
def health():
    logger.info("Health check request received for order service")
    return jsonify({"status": "healthy"}), 200

# Add a new endpoint to create orders that will publish messages
@app.route('/order', methods=['POST'])
def create_order():
    start_time = time.time()
    API_HITS.labels(method='POST', endpoint='/order').inc()
    
    try:
        data = request.get_json()
        order_id = str(uuid.uuid4())
        
        # Store in database
        with db_connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO orders (order_id, product, quantity) VALUES (%s, %s, %s)",
                (order_id, data['product'], data['quantity'])
            )
        db_connection.commit()
        
        # Publish to RabbitMQ
        message = json.dumps({
            'order_id': order_id,
            'product': data['product'],
            'quantity': data['quantity'],
            'timestamp': datetime.now().isoformat()
        })
        publish_to_queue(message)
        
        PROCESSING_TIME.labels(endpoint='/order').observe(time.time() - start_time)
        return jsonify({"order_id": order_id, "status": "created"}), 201
        
    except Exception as e:
        logger.error(f"Error creating order: {str(e)}")
        return jsonify({"error": "Failed to create order"}), 500

# Prometheus metrics registration
register_metrics(app, app_version="v1.0.0", app_config="production")

if __name__ == "__main__":
    init_db()  # Initialize database before starting the server
    start_http_server(8003) # Expose metrics
    app.run(host="0.0.0.0", port=5003)
