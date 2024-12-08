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

# Stop execution on error
set -e

# Environment variables for optional components
DEPLOY_MONITORING=${DEPLOY_MONITORING:-true}
DEPLOY_LOGGING=${DEPLOY_LOGGING:-true}

# Create namespaces first
log_info "Creating namespaces..."
for ns in istio-system database messaging ecommerce monitoring logging; do
    if kubectl create namespace "$ns" 2>/dev/null; then
        log_success "Created namespace $ns ${TICK}"
    else
        log_info "Namespace $ns already exists ${TICK}"
    fi
done

# Apply secrets early
log_info "Creating secrets..."
if kubectl apply -f secrets.yaml -n ecommerce; then
    log_success "Secrets applied successfully ${TICK}"
else
    log_error "Failed to apply secrets ${CROSS}"
    exit 1
fi

# 1. Install Istio First
log_info "Setting up Istio..."
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
log_info "Using Kind cluster: ${CLUSTER_NAME}"

# Pull and load Istio images
log_info "Pulling and loading Istio images..."
for image in "pilot:1.24.1" "proxyv2:1.24.1"; do
    if docker pull "docker.io/istio/${image}"; then
        log_success "Pulled istio/${image} ${TICK}"
        if kind load docker-image "docker.io/istio/${image}" --name "${CLUSTER_NAME}"; then
            log_success "Loaded istio/${image} into cluster ${TICK}"
        else
            log_error "Failed to load istio/${image} into cluster ${CROSS}"
            exit 1
        fi
    else
        log_error "Failed to pull istio/${image} ${CROSS}"
        exit 1
    fi
done

# Verify Istio configuration
log_info "Analyzing Istio configuration..."
if ! istioctl analyze istio/k8s/deployment.yaml --use-kube=false; then
    log_error "Istio configuration validation failed ${CROSS}"
    exit 1
fi
log_success "Istio configuration validated ${TICK}"

# Install Istio
log_info "Installing Istio..."
if ! istioctl install -f istio/k8s/deployment.yaml --set profile=demo -y; then
    log_error "Istio installation failed. Running diagnostics... ${CROSS}"
    istioctl analyze -n istio-system
    kubectl get pods -n istio-system
    kubectl get events -n istio-system --sort-by='.lastTimestamp'
    exit 1
fi
log_success "Istio installed successfully ${TICK}"

# Wait for Istio components
log_info "Waiting for Istio core components..."
for component in "istiod" "istio-ingressgateway"; do
    if kubectl wait --for=condition=ready pod -l app=$component -n istio-system --timeout=300s; then
        log_success "$component is ready ${TICK}"
    else
        log_warning "$component not ready within timeout"
    fi
done

# Configure namespace injection
log_info "Configuring namespace injection..."
for ns in default istio-system; do
    kubectl label namespace $ns istio-injection=disabled --overwrite
    log_success "Disabled injection for $ns ${TICK}"
done
kubectl label namespace ecommerce istio-injection=enabled --overwrite
log_success "Enabled injection for ecommerce ${TICK}"

# Apply mesh configuration
log_info "Applying mesh configuration..."
kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s
if kubectl apply -f istio/k8s/mesh-config.yaml; then
    log_success "Mesh configuration applied ${TICK}"
else
    log_error "Failed to apply mesh configuration ${CROSS}"
    exit 1
fi
