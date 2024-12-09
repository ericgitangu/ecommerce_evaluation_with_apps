FROM python:3.9-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file
COPY requirements.txt /app/

# Install the dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the utils folder
COPY utils /app/utils/

# Copy the application code
COPY . /app/

# Expose the port
EXPOSE 5003

# Run the application
CMD ["gunicorn", "-b", "0.0.0.0:5003", "app:application"]
