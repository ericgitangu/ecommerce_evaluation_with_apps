import os
import time
from flask import Flask, jsonify, request
from prometheus_client import start_http_server, Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from sqlalchemy import create_engine, MetaData, Table, Column, Integer, String, Float, text
from sqlalchemy.exc import SQLAlchemyError
from contextlib import contextmanager
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

# Initialize Flask app
app = Flask(__name__)

# Initialize logger
logger = setup_logger('catalog')

# Metrics
REQUEST_COUNT = Counter(
    'request_count', 'App Request Count',
    ['app_name', 'method', 'endpoint', 'http_status']
)
REQUEST_LATENCY = Histogram(
    'request_latency_seconds', 'Request latency',
    ['app_name', 'endpoint']
)

# Database configuration
DB_HOST = os.getenv('POSTGRES_HOST', 'postgres')
DB_PORT = os.getenv('POSTGRES_PORT', '5432')
DB_NAME = os.getenv('POSTGRES_DB', 'postgres')
DB_USER = os.getenv('POSTGRES_USER', 'postgres')
DB_PASS = os.getenv('POSTGRES_PASSWORD', '')

# SQLAlchemy setup with retry logic
def get_db_engine():
    """Create SQLAlchemy engine with retry logic"""
    url = f"postgresql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
        pool_timeout=30,
        pool_recycle=1800
    )

engine = get_db_engine()
metadata = MetaData()

@contextmanager
def get_db_connection():
    """Context manager for database connections with retry logic"""
    retries = 3
    delay = 2
    last_exception = None
    
    for attempt in range(retries):
        try:
            connection = engine.connect()
            try:
                yield connection
                return
            finally:
                connection.close()
        except Exception as e:
            last_exception = e
            logger.warning(f"Database connection attempt {attempt + 1} failed: {str(e)}")
            if attempt < retries - 1:
                time.sleep(delay * (attempt + 1))
    
    logger.error(f"All database connection attempts failed: {str(last_exception)}")
    raise last_exception

@app.route('/health')
def health():
    """Health check endpoint"""
    try:
        # Test database connection
        with get_db_connection() as conn:
            conn.execute(text("SELECT 1"))
            return jsonify({
                "status": "healthy",
                "database": "connected"
            }), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e)
        }), 500

@app.route('/metrics')
def metrics():
    """Metrics endpoint for Prometheus"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

def create_app():
    """Application factory function"""
    try:
        # Initialize database connection
        with get_db_connection() as conn:
            conn.execute(text("SELECT 1"))
        logger.info("Database connection successful")
        
        # Start metrics server
        start_http_server(8003)
        logger.info("Metrics server started on port 8003")
        
        return app
    except Exception as e:
        logger.error(f"Failed to initialize application: {str(e)}")
        raise

# For Gunicorn
application = create_app()

if __name__ == "__main__":
    application.run(host="0.0.0.0", port=5001)
