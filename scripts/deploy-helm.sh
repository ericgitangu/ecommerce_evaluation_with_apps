#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
TICK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"

# Print with color
log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

check_postgres_connection() {
    log_info "Verifying PostgreSQL connection..."
    local retries=0
    local max_retries=30
    
    while [ $retries -lt $max_retries ]; do
        if kubectl exec -n database sts/postgres-postgresql -- pg_isready -U postgres 2>/dev/null; then
            log_success "PostgreSQL is ready ${TICK}"
            return 0
        fi
        retries=$((retries + 1))
        log_info "Waiting for PostgreSQL to be ready... (attempt $retries/$max_retries)"
        sleep 10
    done
    
    log_error "PostgreSQL failed to become ready ${CROSS}"
    log_info "Current PostgreSQL resources:"
    kubectl get all -n database -l app.kubernetes.io/name=postgresql
    kubectl describe sts postgres-postgresql -n database
    kubectl get events -n database --sort-by=.metadata.creationTimestamp | tail -n 20
    return 1
}

# Stop Execution on Error
set -e

# Cleanup existing installations
echo "Cleaning up existing installations..."
helm uninstall prometheus-operator -n monitoring --ignore-not-found
helm uninstall elasticsearch -n logging --ignore-not-found
helm uninstall rabbitmq -n messaging --ignore-not-found
helm uninstall postgres -n database --ignore-not-found
helm uninstall grafana -n monitoring --ignore-not-found
helm uninstall istio-system -n istio-system --ignore-not-found

# Clean up old PVCs
echo "Cleaning up old PVCs..."
kubectl delete pvc --all -n ecommerce --ignore-not-found
kubectl delete pvc --all -n database --ignore-not-found
kubectl delete pvc --all -n monitoring --ignore-not-found
kubectl delete pvc --all -n logging --ignore-not-found
kubectl delete pvc --all -n messaging --ignore-not-found

# Create namespaces
echo "Creating namespaces..."
kubectl create namespace monitoring || true
kubectl create namespace logging || true
kubectl create namespace messaging || true
kubectl create namespace database || true
kubectl create namespace ecommerce || true
kubectl create namespace istio-system || true

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add elastic https://helm.elastic.co || true
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo update

# Install Prometheus Operator
echo "Installing Prometheus Operator..."
helm install prometheus-operator prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheusOperator.createCustomResource=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=false \
  --set grafana.enabled=true \
  --set grafana.adminPassword=admin \
  --timeout 10m

# Wait for Prometheus CRDs to be ready
echo "Waiting for Prometheus CRDs to be ready..."
kubectl wait --for condition=established --timeout=120s crd/servicemonitors.monitoring.coreos.com || true
kubectl wait --for condition=established --timeout=120s crd/prometheuses.monitoring.coreos.com || true
kubectl wait --for condition=established --timeout=120s crd/alertmanagers.monitoring.coreos.com || true

# Deploy Elasticsearch
echo "Deploying Elasticsearch..."
helm install elasticsearch elastic/elasticsearch \
  --namespace logging \
  --create-namespace \
  --timeout 10m

# Deploy RabbitMQ
echo "Deploying RabbitMQ..."
helm install rabbitmq bitnami/rabbitmq \
  --namespace messaging \
  --set auth.username=admin \
  --set auth.password=adminpassword \
  --create-namespace \
  --timeout 10m

# Deploy PostgreSQL
log_info "Installing PostgreSQL..."
helm install postgres bitnami/postgresql \
  --namespace database \
  --set auth.postgresPassword=mysecretpassword \
  --set primary.resources.requests.cpu=100m \
  --set primary.resources.requests.memory=256Mi \
  --set primary.resources.limits.cpu=200m \
  --set primary.resources.limits.memory=512Mi \
  --set readReplicas.resources.requests.cpu=50m \
  --set readReplicas.resources.requests.memory=128Mi \
  --set readReplicas.resources.limits.cpu=100m \
  --set readReplicas.resources.limits.memory=256Mi \
  --create-namespace \
  --timeout 10m

# Check PostgreSQL connection after installation
if ! check_postgres_connection; then
    log_error "PostgreSQL installation verification failed ${CROSS}"
    exit 1
fi

echo "All services deployed successfully!"
