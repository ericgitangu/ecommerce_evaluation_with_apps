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

# Function to load images into Kind
load_images_to_kind() {
    log_info "Loading Docker images into Kind..."
    for service in order catalog search frontend; do
        log_info "Building $service service..."
        if docker build -t egitangu/$service-service:latest -f app/$service/Dockerfile app/$service; then
            log_success "Built $service image ${TICK}"
            
            # Load into Kind cluster
            if kind load docker-image egitangu/$service-service:latest --name egitangu-local-cluster; then
                log_success "Loaded $service image into cluster ${TICK}"
                
                # Verify image is available in the cluster
                if crictl -r unix:///var/run/containerd/containerd.sock images | grep "egitangu/$service-service" >/dev/null 2>&1; then
                    log_success "Verified $service image in cluster ${TICK}"
                else
                    # Alternative verification using docker
                    if docker exec egitangu-local-cluster-control-plane crictl images | grep "egitangu/$service-service" >/dev/null 2>&1; then
                        log_success "Verified $service image in cluster ${TICK}"
                    else
                        log_warning "Image verification skipped (continuing anyway) ${YELLOW}⚠${NC}"
                    fi
                fi
            else
                log_error "Failed to load $service image ${CROSS}"
                return 1
            fi
        else
            log_error "Failed to build $service image ${CROSS}"
            return 1
        fi
    done
    return 0
}

# Call the function where we previously had the direct loop
if ! load_images_to_kind; then
    log_error "Failed to load images into Kind ${CROSS}"
    exit 1
fi

install_metrics_server() {
    log_info "Installing metrics server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    # Patch metrics-server to work with Kind's self-signed certificates
    kubectl patch deployment metrics-server \
      -n kube-system \
      --type=json \
      -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

    # Wait for metrics-server to be ready
    if kubectl wait --for=condition=available --timeout=90s deployment/metrics-server -n kube-system; then
        log_success "Metrics server installed successfully ${TICK}"
    else
        log_warning "Metrics server installation incomplete ${CROSS}"
    fi
}

# Add this call after cluster creation but before deploying services
if ! install_metrics_server; then
    log_warning "Metrics server installation failed - HPA may not work properly ${CROSS}"
fi

log_info "Deploying services..."
./scripts/deploy-helm.sh
./scripts/deploy-kubectl.sh

log_info "Waiting for all pods to be ready..."
check_cluster_status() {
    log_error "Not all pods are ready ${CROSS}"
    
    # Node Status
    log_info "=== Node Status ==="
    kubectl get nodes -o wide
    echo
    
    # Resource Usage
    log_info "=== Resource Usage ==="
    kubectl describe nodes | grep -A 5 "Allocated resources"
    echo
    
    # Pod Status Across All Namespaces
    log_info "=== Pod Status (All Namespaces) ==="
    kubectl get pods --all-namespaces -o wide | \
        awk 'NR==1{print $0}; NR>1{if ($4 != "Running") print $0}'
    echo
    
    # Detailed Pod Status for ecommerce namespace
    log_info "=== Detailed Pod Status (ecommerce) ==="
    kubectl get pods -n ecommerce -o custom-columns=\
        "NAME:.metadata.name,\
        STATUS:.status.phase,\
        READY:.status.containerStatuses[*].ready,\
        RESTARTS:.status.containerStatuses[*].restartCount,\
        AGE:.metadata.creationTimestamp"
    echo
    
    # Check for Events
    log_info "=== Recent Events ==="
    kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 20
    echo
    
    # Deployment Status
    log_info "=== Deployment Status ==="
    kubectl get deployments --all-namespaces -o wide
    echo
    
    # Service Status
    log_info "=== Service Status ==="
    kubectl get services --all-namespaces -o wide
    echo
    
    # Check for PVC issues
    log_info "=== PVC Status ==="
    kubectl get pvc --all-namespaces
    echo
    
    # Resource Quotas
    log_info "=== Resource Quotas ==="
    kubectl get resourcequota --all-namespaces
    echo
    
    # Detailed status for non-running pods
    log_info "=== Detailed Status for Problematic Pods ==="
    for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
        kubectl get pods -n $ns | grep -v "Running" | grep -v "Completed" | while read pod status rest; do
            if [ ! -z "$pod" ]; then
                echo -e "${YELLOW}=== Details for $pod in namespace $ns ===${NC}"
                kubectl describe pod $pod -n $ns | grep -A 10 "Events:"
                echo
            fi
        done
    done
}

if kubectl wait --for=condition=ready pod --all -n ecommerce --timeout=300s; then
    log_success "All pods are ready ${TICK}"
else
    check_cluster_status
    exit 1
fi

log_info "Testing endpoints..."
INGRESS_HOST="localhost"  # Since you're running locally
INGRESS_PORT="80"        # Default HTTP port for Istio Ingress Gateway

# Test frontend separately as it might have a different path
if curl -f "http://${INGRESS_HOST}:${INGRESS_PORT}/health"; then
    log_success "frontend health check passed ${TICK}"
else
    log_error "frontend health check failed ${CROSS}"
fi

# Test other services
for service in catalog search order; do
    if curl -f "http://${INGRESS_HOST}:${INGRESS_PORT}/${service}/health"; then
        log_success "$service health check passed ${TICK}"
    else
        log_error "$service health check failed ${CROSS}"
    fi
done

log_success "Setup complete! ${TICK}"