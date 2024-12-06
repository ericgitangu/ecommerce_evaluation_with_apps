from flask import Flask, jsonify, request
import pika
import psycopg2
from prometheus_client import start_http_server, Counter, Histogram
import os
import time

app = Flask(__name__)

# Metrics
API_HITS = Counter('api_hits', 'API Hits', ['method', 'endpoint'])
PROCESSING_TIME = Histogram('processing_time_seconds', 'Processing Time', ['endpoint'])

# Database connection
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:mysecretpassword@postgres/orders_db')
db_connection = psycopg2.connect(DATABASE_URL)

# RabbitMQ connection
RABBITMQ_HOST = os.getenv('RABBITMQ_HOST', 'rabbitmq')

@app.route('/')
def home():
    start_time = time.time()
    API_HITS.labels(method='GET', endpoint='/').inc()
    PROCESSING_TIME.labels(endpoint='/').observe(time.time() - start_time)
    return jsonify({"message": "Order Service Running"}), 200

@app.route('/create-order', methods=['POST'])
def create_order():
    start_time = time.time()
    API_HITS.labels(method='POST', endpoint='/create-order').inc()
    data = request.json
    try:
        # Publish message to RabbitMQ
        connection = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST))
        channel = connection.channel()
        channel.queue_declare(queue='orders')
        channel.basic_publish(exchange='', routing_key='orders', body=str(data))
        connection.close()

        # Insert order into PostgreSQL
        with db_connection.cursor() as cursor:
            cursor.execute("INSERT INTO orders (order_id, product, quantity) VALUES (%s, %s, %s)",
                           (data["order_id"], data["product"], data["quantity"]))
        db_connection.commit()

        PROCESSING_TIME.labels(endpoint='/create-order').observe(time.time() - start_time)
        return jsonify({"status": "order created"}), 201
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/metrics')
def metrics():
    from prometheus_client import generate_latest
    return generate_latest()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    start_http_server(8003)  # Expose metrics
    app.run(host="0.0.0.0", port=8001)
