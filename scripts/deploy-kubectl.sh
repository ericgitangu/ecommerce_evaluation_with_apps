#!/bin/bash

# Namespace creation
echo "Creating namespaces..."
kubectl create namespace monitoring
kubectl create namespace logging
kubectl create namespace messaging
kubectl create namespace database

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

# Verify deployments
echo "Deployment complete. Verifying resources..."
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n messaging
kubectl get pods -n database
kubectl get services -A
