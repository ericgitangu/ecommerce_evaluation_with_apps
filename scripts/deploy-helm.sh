#!/bin/bash

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script Description:
# This script automates the deployment of infrastructure components using Helm charts.
# It performs the following key tasks:
# 1. Cleans up any existing installations and PVCs
# 2. Creates required namespaces
# 3. Adds and updates Helm repositories 
# 4. Installs core infrastructure components:
#    - Prometheus Operator for monitoring
#    - Elasticsearch for logging
#    - RabbitMQ for messaging
#    - PostgreSQL for database
#    - Grafana for visualization
#    - Istio for service mesh
#
# The script uses color-coded logging for better visibility:
# - Blue for general info messages
# - Green for success messages
# - Red (unused but defined) for potential error messages
#
# Prerequisites:
# - Kubernetes cluster running
# - Helm installed
# - kubectl configured with cluster access
# - Required Helm repositories accessible
#
# Usage: ./deploy-helm.sh


# Print with color
log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }

# Stop Execution on Error
set -e

# Cleanup existing installations
log_info "Cleaning up existing installations..."
helm uninstall prometheus-operator -n monitoring --ignore-not-found
helm uninstall elasticsearch -n logging --ignore-not-found
helm uninstall rabbitmq -n messaging --ignore-not-found
helm uninstall postgres -n database --ignore-not-found
helm uninstall grafana -n monitoring --ignore-not-found
helm uninstall istio-system -n istio-system --ignore-not-found

# Clean up old PVCs
log_info "Cleaning up old PVCs..."
kubectl delete pvc --all -n ecommerce --ignore-not-found
kubectl delete pvc --all -n database --ignore-not-found
kubectl delete pvc --all -n monitoring --ignore-not-found
kubectl delete pvc --all -n logging --ignore-not-found
kubectl delete pvc --all -n messaging --ignore-not-found

# Create namespaces
log_info "Creating namespaces..."
kubectl create namespace monitoring || true
kubectl create namespace logging || true
kubectl create namespace messaging || true
kubectl create namespace database || true
kubectl create namespace ecommerce || true
kubectl create namespace istio-system || true

# Add Helm repositories
log_info "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add elastic https://helm.elastic.co || true
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo update

# Install Prometheus Operator
log_info "Installing Prometheus Operator..."
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
log_info "Waiting for Prometheus CRDs to be ready..."
kubectl wait --for condition=established --timeout=120s crd/servicemonitors.monitoring.coreos.com || true
kubectl wait --for condition=established --timeout=120s crd/prometheuses.monitoring.coreos.com || true
kubectl wait --for condition=established --timeout=120s crd/alertmanagers.monitoring.coreos.com || true

# Deploy Elasticsearch
log_info "Installing Elasticsearch..."
helm install elasticsearch elastic/elasticsearch \
  --namespace logging \
  --create-namespace \
  --timeout 10m

# Deploy RabbitMQ
log_info "Installing RabbitMQ..."
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
  --set volumePermissions.enabled=true \
  --set primary.persistence.storageClass=standard \
  --set primary.persistence.size=1Gi \
  --create-namespace \
  --timeout 10m

log_success "All services installed successfully!"