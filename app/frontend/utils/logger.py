import logging
import os
from logging.handlers import RotatingFileHandler

def setup_logger(service_name):
    # Create logs directory if it doesn't exist
    log_dir = f"logs_and_metrics/{service_name}"
    os.makedirs(log_dir, exist_ok=True)

    # Create logger
    logger = logging.getLogger(service_name)
    logger.setLevel(logging.INFO)

    # Create handlers
    console_handler = logging.StreamHandler()
    file_handler = RotatingFileHandler(
        f'{log_dir}/{service_name}.log',
        maxBytes=10485760,  # 10MB
        backupCount=5
    )

    # Create formatters and add it to handlers
    log_format = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    console_handler.setFormatter(log_format)
    file_handler.setFormatter(log_format)

    # Add handlers to the logger
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)

    return logger