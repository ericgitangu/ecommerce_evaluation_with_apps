#!/bin/bash

# Stop on error
set -e

# Delete existing cluster if it exists
echo "Cleaning up any existing cluster..."
kind delete cluster --name egitangu-local-cluster || true

echo "Creating Kind cluster..."
kind create cluster \
  --config kind/k8s/kind-config.yaml \
  --name egitangu-local-cluster

# Verify cluster is ready
echo "Verifying cluster is ready..."
kubectl cluster-info --context kind-egitangu-local-cluster
kubectl wait --for=condition=ready node --all --timeout=60s

echo "Loading Docker images into Kind..."
for service in order catalog search frontend; do
  docker build -t egitangu/$service-service:latest -f app/$service/Dockerfile app/$service
  kind load docker-image egitangu/$service-service:latest --name egitangu-local-cluster
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