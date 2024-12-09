from flask import Flask, jsonify, request
import pika
import psycopg2
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import os
import time
import sys
import uuid
from datetime import datetime
import json

# Add the project root to the Python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

app = Flask(__name__)

# Initialize logger
logger = setup_logger('order')

# Metrics
REQUEST_COUNT = Counter(
    'request_count', 'App Request Count',
    ['app_name', 'method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'request_latency_seconds', 'Request latency',
    ['app_name', 'endpoint']
)

# Database connection
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv('POSTGRES_HOST'),
        port=os.getenv('POSTGRES_PORT', '5432'),
        database=os.getenv('POSTGRES_DB'),
        user=os.getenv('POSTGRES_USER'),
        password=os.getenv('POSTGRES_PASSWORD')
    )

# RabbitMQ connection parameters
RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'rabbitmq')
RABBITMQ_USER = os.getenv('RABBITMQ_USERNAME', 'guest')
RABBITMQ_PASS = os.getenv('RABBITMQ_PASSWORD', 'guest')

def init_db():
    """Initialize the database with required tables"""
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS orders (
                    id SERIAL PRIMARY KEY,
                    order_id VARCHAR(255) NOT NULL,
                    product VARCHAR(255) NOT NULL,
                    quantity INTEGER NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
            """)
        conn.commit()
        conn.close()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Error initializing database: {str(e)}")
        raise

def publish_to_queue(message):
    """Publish message to RabbitMQ"""
    try:
        credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(
                host=RABBITMQ_HOST,
                credentials=credentials,
                connection_attempts=3,
                retry_delay=5
            )
        )
        channel = connection.channel()
        channel.queue_declare(queue='orders', durable=True)
        channel.basic_publish(
            exchange='',
            routing_key='orders',
            body=message,
            properties=pika.BasicProperties(delivery_mode=2)
        )
        logger.info(f"Published message to orders queue: {message}")
        connection.close()
    except Exception as e:
        logger.error(f"Error publishing to RabbitMQ: {str(e)}")
        raise

@app.route('/')
def home():
    """Home endpoint"""
    start_time = time.time()
    REQUEST_COUNT.labels(app_name='order', method='GET', endpoint='/', http_status=200).inc()
    REQUEST_LATENCY.labels(app_name='order', endpoint='/').observe(time.time() - start_time)
    return jsonify({"message": "Order Service Running"}), 200

@app.route('/order', methods=['POST'])
def create_order():
    """Create a new order"""
    start_time = time.time()
    
    try:
        data = request.get_json()
        if not data or not all(k in data for k in ["product", "quantity"]):
            REQUEST_COUNT.labels(app_name='order', method='POST', endpoint='/order', http_status=400).inc()
            return jsonify({"error": "Missing required fields"}), 400

        order_id = str(uuid.uuid4())
        
        # Store in database
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO orders (order_id, product, quantity) VALUES (%s, %s, %s)",
                (order_id, data['product'], data['quantity'])
            )
        conn.commit()
        conn.close()
        
        # Publish to RabbitMQ
        message = json.dumps({
            'order_id': order_id,
            'product': data['product'],
            'quantity': data['quantity'],
            'timestamp': datetime.now().isoformat()
        })
        publish_to_queue(message)
        
        REQUEST_LATENCY.labels(app_name='order', endpoint='/order').observe(time.time() - start_time)
        REQUEST_COUNT.labels(app_name='order', method='POST', endpoint='/order', http_status=201).inc()
        return jsonify({"order_id": order_id, "status": "created"}), 201
        
    except Exception as e:
        logger.error(f"Error creating order: {str(e)}")
        REQUEST_COUNT.labels(app_name='order', method='POST', endpoint='/order', http_status=500).inc()
        return jsonify({"error": "Failed to create order"}), 500

@app.route('/metrics')
def metrics():
    """Metrics endpoint for Prometheus"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/health')
def health():
    """Health check endpoint"""
    try:
        # Basic application health
        health_status = {
            "status": "healthy",
            "database": "unknown",
            "message_queue": "unknown"
        }

        # Test database connection
        try:
            conn = get_db_connection()
            with conn.cursor() as cursor:
                cursor.execute('SELECT 1')
            conn.close()
            health_status["database"] = "connected"
        except Exception as e:
            logger.warning(f"Database health check failed: {str(e)}")
            health_status["database"] = "disconnected"

        # Test RabbitMQ connection
        try:
            credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    host=RABBITMQ_HOST,
                    credentials=credentials,
                    connection_attempts=1,
                    socket_timeout=1
                )
            )
            connection.close()
            health_status["message_queue"] = "connected"
        except Exception as e:
            logger.warning(f"RabbitMQ health check failed: {str(e)}")
            health_status["message_queue"] = "disconnected"

        # Return 200 if at least basic app is healthy
        return jsonify(health_status), 200

    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 500

def create_app():
    """Application factory function"""
    logger.info("Creating app for Gunicorn: %s", 'order-service')
    return app

# For Gunicorn
application = create_app()

if __name__ == "__main__":
    # Initialize database
    init_db()
    
    # Start metrics server - TODO: we are using metrics server with the service's metrics endpoint!
    # start_http_server(8003)
    
    # Start Flask app
    application.run(host="0.0.0.0", port=5003)
