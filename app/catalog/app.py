import os
import time
from flask import Flask, jsonify, request
from flask_prometheus_metrics import register_metrics, start_http_server, CONTENT_TYPE_LATEST
from sqlalchemy import create_engine, MetaData, Table, Column, Integer, String, Float
from sqlalchemy.exc import OperationalError
from contextlib import contextmanager
from sqlalchemy.sql import text
import os
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.logger import setup_logger

# Flask app initialization
app = Flask(__name__)

# Logging setup
logger = setup_logger('catalog')
logger.info("Catalog service starting up")

# Read environment variables
DATABASE_URL = os.getenv("DATABASE_URL", f"postgresql://{os.getenv('POSTGRES_USERNAME', 'postgres')}:{os.getenv('POSTGRES_PASSWORD', '')}@localhost:5432/postgres")
DB_TIMEOUT = int(os.getenv("DB_TIMEOUT", 5))  # Timeout for health check queries

# SQLAlchemy setup
engine = create_engine(DATABASE_URL, pool_pre_ping=True)
metadata = MetaData()

# Define the catalog table
catalog_table = Table(
    "catalog", metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("name", String(255), nullable=False),
    Column("price", Float, nullable=False),
    Column("stock", Integer, nullable=False)
)

# Add a connection manager
@contextmanager
def get_db_connection():
    connection = engine.connect()
    try:
        yield connection
    finally:
        connection.close()

# Modify initialize_table to return success status
def initialize_table() -> bool:
    try:
        metadata.create_all(engine)
        # Verify table exists
        with get_db_connection() as conn:
            conn.execute(text("SELECT 1 FROM catalog LIMIT 1"))
        print("Catalog table created successfully or already exists.")
        return True
    except Exception as e:
        print(f"Error initializing database: {e}")
        return False

# Add table verification
def verify_table_exists() -> bool:
    try:
        with get_db_connection() as conn:
            conn.execute(text("SELECT 1 FROM catalog LIMIT 1"))
        return True
    except Exception:
        return False

# Modify get_catalog with better error handling
@app.route('/catalog', methods=['GET'])
def get_catalog():
    """
    Fetch the entire catalog from the database.
    """
    logger.info("Received request to fetch entire catalog")
    if not verify_table_exists():
        logger.error("Catalog table not initialized")
        return jsonify({"error": "Catalog table not initialized"}), 500
        
    try:
        with get_db_connection() as connection:
            start_time = time.time()
            result = connection.execute(catalog_table.select())
            duration = time.time() - start_time
            catalog_items = [dict(row) for row in result]
            
        logger.info(f"Successfully fetched {len(catalog_items)} catalog items in {duration:.2f} seconds")
        return jsonify(catalog_items), 200
    except Exception as e:
        logger.error(f"Failed to fetch catalog: {str(e)}", exc_info=True)
        return jsonify({"error": "Database error occurred"}), 500

# Modify get_catalog_item with better error handling
@app.route('/catalog/<int:item_id>', methods=['GET'])
def get_catalog_item(item_id):
    """
    Fetch a specific catalog item by ID.
    """
    logger.info(f"Received request to fetch catalog item {item_id}")
    if not verify_table_exists():
        logger.error("Catalog table not initialized")
        return jsonify({"error": "Catalog table not initialized"}), 500
        
    if not isinstance(item_id, int) or item_id < 1:
        logger.warning(f"Invalid item ID requested: {item_id}")
        return jsonify({"error": "Invalid item ID"}), 400
        
    try:
        with get_db_connection() as connection:
            start_time = time.time()
            query = catalog_table.select().where(catalog_table.c.id == item_id)
            result = connection.execute(query).fetchone()
            duration = time.time() - start_time
            
        if result:
            logger.info(f"Successfully fetched item {item_id} in {duration:.2f} seconds")
            return jsonify(dict(result)), 200
        logger.warning(f"Item {item_id} not found")
        return jsonify({"error": "Item not found"}), 404
    except Exception as e:
        logger.error(f"Failed to fetch item {item_id}: {str(e)}", exc_info=True)
        return jsonify({"error": "Database error occurred"}), 500

# Modify health check
@app.route('/health', methods=['GET'])
def health():
    """
    Health endpoint to check service health.
    """
    logger.debug("Health check requested")
    try:
        table_exists = verify_table_exists()
        with get_db_connection() as connection:
            connection.execute(text("SELECT 1"))
        status = "exists" if table_exists else "missing"
        logger.info(f"Health check successful. Catalog table {status}")
        return jsonify({
            "status": "healthy",
            "database": "connected",
            "catalog_table": status
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}", exc_info=True)
        return jsonify({
            "status": "unhealthy",
            "error": str(e),
            "database": "disconnected"
        }), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """
    Metrics endpoint for Prometheus.
    Returns actual metrics in Prometheus format.
    """
    from prometheus_client import generate_latest
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# Prometheus metrics registration
register_metrics(app, app_version="v1.0.0", app_config="production")

# Flask app execution
if __name__ == "__main__":
    start_http_server(8003)  # Expose metrics
    app.run(host="0.0.0.0", port=5001)
