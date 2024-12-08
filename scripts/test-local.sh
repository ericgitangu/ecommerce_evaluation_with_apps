#!/bin/bash

# Stop on error
set -e

# Cleanup function
cleanup() {
    echo "Performing cleanup..."
    
    # Check if cluster exists before attempting cleanup
    if kubectl cluster-info >/dev/null 2>&1; then
        # Cleanup existing Helm installations
        echo "Cleaning up existing Helm installations..."
        helm uninstall prometheus-operator -n monitoring --ignore-not-found
        helm uninstall elasticsearch -n logging --ignore-not-found
        helm uninstall rabbitmq -n messaging --ignore-not-found
        helm uninstall postgres -n database --ignore-not-found
        helm uninstall grafana -n monitoring --ignore-not-found
        helm uninstall istio-system -n istio-system --ignore-not-found

        # Clean up resources in all namespaces
        echo "Cleaning up resources in all namespaces..."
        for ns in ecommerce database monitoring logging messaging istio-system; do
            kubectl delete pvc --all -n $ns --ignore-not-found
            kubectl delete configmap --all -n $ns --ignore-not-found
            kubectl delete secret --all -n $ns --ignore-not-found
        done
    else
        echo "No active cluster found, skipping Kubernetes cleanup..."
    fi

    # Delete existing cluster
    echo "Deleting Kind cluster..."
    kind delete cluster --name egitangu-local-cluster || true
}

# Run cleanup
cleanup

# Get the absolute path to the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create new cluster
echo "Creating Kind cluster..."
kind create cluster \
  --config "${PROJECT_ROOT}/kind/k8s/kind-config.yaml" \
  --name egitangu-local-cluster \
  --image kindest/node:v1.28.0 \
  --wait 60s

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

# Set trap to cleanup on script exit
trap cleanup EXIT