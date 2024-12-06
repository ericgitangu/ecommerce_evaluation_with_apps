#!/bin/bash

# Stop Execution on Error
set -e

# Apply secrets
echo "Creating secrets..."
kubectl apply -f secrets.yaml -n ecommerce

# Namespace creation - we already created these in deploy-helm.sh
# echo "Creating namespaces..."
# kubectl create namespace monitoring
# kubectl create namespace logging
# kubectl create namespace messaging
# kubectl create namespace database

# Prometheus deployment
echo "Deploying Prometheus..."
kubectl apply -f prometheus/prometheus-configmap.yaml -n monitoring
kubectl apply -f prometheus/k8s/deployment.yaml -n monitoring
kubectl apply -f prometheus/k8s/service.yaml -n monitoring

# Grafana deployment
echo "Deploying Grafana..."
kubectl apply -f grafana/k8s/deployment.yaml -n monitoring
kubectl apply -f grafana/k8s/service.yaml -n monitoring
kubectl create configmap grafana-dashboard --from-file=grafana/dashboards/flask-services.json -n monitoring

# Elasticsearch deployment
echo "Deploying Elasticsearch..."
kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
kubectl apply -f elasticsearch/k8s/service.yaml -n logging

# RabbitMQ deployment
echo "Deploying RabbitMQ..."
kubectl apply -f rabbitmq/k8s/deployment.yaml -n messaging
kubectl apply -f rabbitmq/k8s/service.yaml -n messaging

# PostgreSQL deployment
echo "Deploying PostgreSQL..."
kubectl apply -f postgres/k8s/deployment.yaml -n database
kubectl apply -f postgres/k8s/service.yaml -n database

# Flask Services deployment
for service in order catalog search frontend; do
  echo "Deploying $service service..."
  kubectl apply -f app/$service/k8s/deployment.yaml
  kubectl apply -f app/$service/k8s/service.yaml
  kubectl apply -f app/$service/k8s/hpa.yaml
done

# Deploy Nginx configurations
echo "Deploying Nginx Ingress configurations..."
kubectl apply -f nginx/k8s/deployment.yaml
kubectl apply -f nginx/k8s/service.yaml -n ecommerce

# Verification Step
echo "Verifying resources..."
kubectl wait --for=condition=available --timeout=60s deployment --all -n monitoring
kubectl wait --for=condition=available --timeout=60s deployment --all -n logging
kubectl wait --for=condition=available --timeout=60s deployment --all -n messaging
kubectl wait --for=condition=available --timeout=60s deployment --all -n database
kubectl wait --for=condition=available --timeout=60s deployment --all -n ecommerce

kubectl get pods -A
kubectl get services -A

# Set up port forwarding
echo "Setting up port forwarding..."
kubectl port-forward -n monitoring svc/prometheus-service 9090:9090 &
kubectl port-forward -n monitoring svc/grafana-service 3000:3000 &
kubectl port-forward -n logging svc/elasticsearch-service 9200:9200 &
kubectl port-forward -n messaging svc/rabbitmq-service 5672:5672 15672:15672 &
kubectl port-forward -n database svc/postgres-service 5432:5432 &
kubectl port-forward -n ecommerce svc/nginx-ingress 80:80 &

echo "Services are available at:"
echo "- Prometheus: http://localhost:9090"
echo "- Grafana: http://localhost:3000"
echo "- Elasticsearch: http://localhost:9200"
echo "- RabbitMQ Management: http://localhost:15672"
echo "- PostgreSQL: localhost:5432"
echo "- Nginx Ingress: localhost:80"
