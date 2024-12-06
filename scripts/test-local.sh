#!/bin/bash

# Stop on error
set -e

echo "Creating Kind cluster..."
kind create cluster --config kind/.k8s/kind-config.yaml

echo "Loading Docker images into Kind..."
for service in order catalog search frontend; do
  docker build -t egitangu/$service-service:latest -f app/$service/Dockerfile app/$service
  kind load docker-image egitangu/$service-service:latest
done

echo "Deploying services..."
./scripts/deploy-helm.sh
./scripts/deploy-kubectl.sh

echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n ecommerce --timeout=300s

echo "Testing endpoints..."
curl -f http://localhost/health || echo "Frontend health check failed"
curl -f http://localhost/catalog/health || echo "Catalog health check failed"
curl -f http://localhost/search/health || echo "Search health check failed"
curl -f http://localhost/order/health || echo "Order health check failed"