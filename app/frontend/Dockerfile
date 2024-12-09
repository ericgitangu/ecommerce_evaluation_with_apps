FROM python:3.9-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy the utils package
COPY utils /app/utils/

# Copy the application code
COPY . /app/

# Expose the port
EXPOSE 5004 8003

# Run the application
CMD ["python3", "app.py"]
