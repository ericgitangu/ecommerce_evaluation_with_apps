FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy the requirements file
COPY requirements.txt /app/

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the utils package
COPY utils /app/utils/

# Copy the application code
COPY . /app/

# Create logs directory
RUN mkdir -p /app/logs && \
    chmod 777 /app/logs

# Expose the port
EXPOSE 5004

# Run the application
CMD ["gunicorn", "--config", "gunicorn-config.py", "app:application"]