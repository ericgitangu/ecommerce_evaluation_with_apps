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

# Stop on error
set -e

# Cleanup function
cleanup() {
    log_info "Performing cleanup..."
    
    # Check if cluster exists before attempting cleanup
    if kubectl cluster-info >/dev/null 2>&1; then
        log_info "Cleaning up existing Helm installations..."
        for app in prometheus-operator elasticsearch rabbitmq postgres grafana istio-system; do
            if helm uninstall $app -n ${app#*-} --ignore-not-found; then
                log_success "Uninstalled $app ${TICK}"
            else
                log_warning "Failed to uninstall $app ${CROSS}"
            fi
        done

        log_info "Cleaning up resources in all namespaces..."
        for ns in ecommerce database monitoring logging messaging istio-system; do
            for resource in pvc configmap secret; do
                if kubectl delete $resource --all -n $ns --ignore-not-found; then
                    log_success "Cleaned up ${resource}s in $ns ${TICK}"
                else
                    log_warning "Failed to clean up ${resource}s in $ns ${CROSS}"
                fi
            done
        done
    else
        log_warning "No active cluster found, skipping Kubernetes cleanup..."
    fi

    log_info "Deleting Kind cluster..."
    if kind delete cluster --name egitangu-local-cluster; then
        log_success "Kind cluster deleted ${TICK}"
    else
        log_warning "Kind cluster deletion skipped (might not exist) ${CROSS}"
    fi
}

# Run cleanup
cleanup

# Create new cluster
log_info "Creating Kind cluster..."
if [ ! -f "kind/k8s/kind-config.yaml" ]; then
    log_error "kind/k8s/kind-config.yaml not found ${CROSS}"
    ls -la .
    # exit 1
fi

if kind create cluster \
    --config kind/k8s/kind-config.yaml \
    --name egitangu-local-cluster \
    --image kindest/node:v1.28.0 \
    --wait 60s; then
    log_success "Kind cluster created successfully ${TICK}"
else
    log_error "Failed to create Kind cluster ${CROSS}"
    # exit 1
fi

# Verify cluster is ready
log_info "Verifying cluster is ready..."
if kubectl cluster-info --context kind-egitangu-local-cluster; then
    log_success "Cluster info verified ${TICK}"
else
    log_error "Cluster verification failed ${CROSS}"
    # exit 1
fi

if kubectl wait --for=condition=ready node --all --timeout=60s; then
    log_success "All nodes are ready ${TICK}"
else
    log_error "Nodes not ready within timeout ${CROSS}"
    # exit 1
fi

log_info "Loading Docker images into Kind..."
for service in order catalog search frontend; do
    log_info "Building $service service..."
    if docker build -t egitangu/$service-service:latest -f app/$service/Dockerfile app/$service; then
        log_success "Built $service image ${TICK}"
        if kind load docker-image egitangu/$service-service:latest --name egitangu-local-cluster; then
            log_success "Loaded $service image into cluster ${TICK}"
        else
            log_error "Failed to load $service image ${CROSS}"
            # exit 1
        fi
    else
        log_error "Failed to build $service image ${CROSS}"
        # exit 1
    fi
done

log_info "Deploying services..."
./scripts/deploy-helm.sh
./scripts/deploy-kubectl.sh

log_info "Waiting for all pods to be ready..."
if kubectl wait --for=condition=ready pod --all -n ecommerce --timeout=300s; then
    log_success "All pods are ready ${TICK}"
else
    log_error "Not all pods are ready ${CROSS}"
fi

log_info "Testing endpoints..."
for service in frontend catalog search order; do
    if curl -f http://localhost/${service#frontend/}/health; then
        log_success "$service health check passed ${TICK}"
    else
        log_error "$service health check failed ${CROSS}"
    fi
done

# Set trap to cleanup on script exit
trap cleanup EXIT

log_success "Setup complete! ${TICK}"