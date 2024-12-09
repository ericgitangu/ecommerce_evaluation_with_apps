#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
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

deploy_core_services() {
    # PostgreSQL is handled by Helm in deploy-helm.sh
    log_info "Skipping PostgreSQL deployment (handled by Helm) ${TICK}"

    # 2. Deploy Message Broker
    log_info "Deploying RabbitMQ..."
    kubectl apply -f rabbitmq/k8s/deployment.yaml -n messaging
    kubectl apply -f rabbitmq/k8s/service.yaml -n messaging
    log_info "Waiting for RabbitMQ..."
    if ! kubectl rollout status deployment/rabbitmq -n messaging --timeout=300s; then
        log_error "RabbitMQ deployment failed ${CROSS}"
        kubectl describe deployment rabbitmq -n messaging
        return 1
    fi
    log_success "RabbitMQ deployed successfully ${TICK}"

    return 0
}

deploy_application_services() {
    log_info "Deploying application services..."
    for service in frontend catalog order search; do
        log_info "Deploying $service service..."
        kubectl apply -f app/$service/k8s/deployment.yaml
        kubectl apply -f app/$service/k8s/service.yaml
        kubectl apply -f app/$service/k8s/hpa.yaml
        
        log_info "Waiting for $service service..."

        if ! check_service_readiness $service; then
            log_error "${service} service failed readiness check ${CROSS}"
            # Show detailed debugging information
            kubectl describe pods -n ecommerce -l app=${service}-service
            kubectl logs -n ecommerce -l app=${service}-service --tail=50
            return 1
        fi

        if ! kubectl rollout status deployment/${service}-service -n ecommerce --timeout=180s; then
            log_error "${service} service deployment failed ${CROSS}"
            
            # Debug information
            log_info "=== Pod Status ==="
            kubectl get pods -n ecommerce -l app=${service}-service
            
            log_info "=== Pod Logs ==="
            kubectl logs -n ecommerce -l app=${service}-service --tail=50
            
            log_info "=== Pod Description ==="
            kubectl describe pods -n ecommerce -l app=${service}-service
            
            log_info "=== Deployment Status ==="
            kubectl describe deployment ${service}-service -n ecommerce
            
            log_info "=== Events ==="
            kubectl get events -n ecommerce --sort-by=.lastTimestamp | grep ${service}
            
            log_info "=== Image Pull Status ==="
            kubectl get pods -n ecommerce -l app=${service}-service -o jsonpath='{.items[*].status.containerStatuses[*].imageRef}'
            
            return 1
        fi
        log_success "${service} service deployed successfully ${TICK}"
    done

    log_info "Applying Authorization Policies..."
    if kubectl apply -f istio/k8s/auth-policy.yaml; then
        log_success "Authorization policies applied ${TICK}"
    else
        log_error "Failed to apply authorization policies ${CROSS}"
        return 1
    fi

    return 0
}

deploy_monitoring() {
    if [ "$DEPLOY_MONITORING" = "true" ]; then
        log_info "Deploying monitoring stack..."
        
        log_info "Deploying Prometheus..."
        kubectl apply -f prometheus/prometheus-configmap.yaml -n monitoring
        kubectl apply -f prometheus/k8s/deployment.yaml -n monitoring
        kubectl apply -f prometheus/k8s/service.yaml -n monitoring
        
        log_info "Deploying Grafana..."
        kubectl apply -f grafana/k8s/deployment.yaml -n monitoring
        kubectl apply -f grafana/k8s/service.yaml -n monitoring
        kubectl create configmap grafana-dashboard --from-file=grafana/dashboards/flask-services.json -n monitoring || true
        kubectl apply -f grafana/k8s/datasource.yaml -n monitoring
        kubectl apply -f grafana/k8s/dashboard-provisioning.yaml -n monitoring
        
        log_info "Waiting for monitoring services..."
        if kubectl wait --for=condition=available --timeout=180s deployment --all -n monitoring; then
            log_success "Monitoring stack deployed successfully ${TICK}"
        else
            log_warning "Monitoring stack deployment incomplete ${CROSS}"
        fi
    fi
}

deploy_logging() {
    if [ "$DEPLOY_LOGGING" = "true" ]; then
        log_info "Deploying logging stack..."
        kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
        kubectl apply -f elasticsearch/k8s/service.yaml -n logging
        log_info "Waiting for Elasticsearch..."
        if kubectl rollout status deployment/elasticsearch --timeout=300s -n logging; then
            log_success "Logging stack deployed successfully ${TICK}"
        else
            log_warning "Logging stack deployment incomplete ${CROSS}"
        fi
    fi
}

setup_port_forwarding() {
    log_info "Setting up port forwarding..."
    kubectl port-forward -n database svc/postgres 5432:5432 &
    kubectl port-forward -n messaging svc/rabbitmq 5672:5672 15672:15672 &
    kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

    if [ "$DEPLOY_MONITORING" = "true" ]; then
        kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
        kubectl port-forward -n monitoring svc/grafana 3000:3000 &
    fi

    if [ "$DEPLOY_LOGGING" = "true" ]; then
        kubectl port-forward -n logging svc/elasticsearch 9200:9200 &
    fi
}

# 1. Create namespaces
log_info "Creating namespaces..."
for ns in istio-system database messaging ecommerce monitoring logging; do
    if kubectl create namespace "$ns" 2>/dev/null; then
        log_success "Created namespace $ns ${TICK}"
    else
        log_info "Namespace $ns already exists ${TICK}"
    fi
done

# 2. Apply secrets
log_info "Creating secrets..."
if ! kubectl apply -f secrets.yaml -n ecommerce; then
    log_error "Failed to apply secrets ${CROSS}"
    exit 1
fi
log_success "Secrets applied successfully ${TICK}"

# 3. Deploy Istio
log_info "Setting up Istio..."
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
log_info "Using Kind cluster: ${CLUSTER_NAME}"

for image in "pilot:1.24.1" "proxyv2:1.24.1"; do
    if docker pull "docker.io/istio/${image}"; then
        log_success "Pulled istio/${image} ${TICK}"
        if ! kind load docker-image "docker.io/istio/${image}" --name "${CLUSTER_NAME}"; then
            log_error "Failed to load istio/${image} ${CROSS}"
            exit 1
        fi
    else
        log_error "Failed to pull istio/${image} ${CROSS}"
        exit 1
    fi
done

if ! istioctl install -f istio/k8s/deployment.yaml --set profile=demo -y; then
    log_error "Istio installation failed ${CROSS}"
    exit 1
fi
log_success "Istio installed successfully ${TICK}"

# 4. Deploy Core Services
if ! deploy_core_services; then
    log_error "Core services deployment failed ${CROSS}"
    exit 1
fi

# 5. Deploy Application Services
if ! deploy_application_services; then
    log_error "Application services deployment failed ${CROSS}"
    exit 1
fi

# 6. Deploy Monitoring (Less essential if we have resource constraints)
deploy_monitoring

# 7. Deploy Logging (Less essential if we have resource constraints)
deploy_logging

# 8. Setup Port Forwarding
setup_port_forwarding

# Display final status
log_info "Current cluster status:"
kubectl get pods -A
kubectl get services -A
kubectl get deployments -A

log_info "Services are available at:"
echo "Core Services:"
echo "- PostgreSQL: localhost:5432"
echo "- RabbitMQ Management: http://localhost:15672"
echo "- Istio Gateway: http://localhost:8080"

if [ "$DEPLOY_MONITORING" = "true" ]; then
    echo "Monitoring:"
    echo "- Prometheus: http://localhost:9090"
    echo "- Grafana: http://localhost:3000"
fi

if [ "$DEPLOY_LOGGING" = "true" ]; then
    echo "Logging:"
    echo "- Elasticsearch: http://localhost:9200"
fi

log_success "Deployment complete! ${TICK}"

check_pod_status() {
    local service=$1
    log_info "Checking pod status for ${service}..."
    
    # Check pod status
    local pod_status=$(kubectl get pods -n ecommerce -l app=${service}-service -o jsonpath='{.items[0].status.phase}')
    local container_status=$(kubectl get pods -n ecommerce -l app=${service}-service -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
    
    if [[ "$pod_status" != "Running" ]]; then
        log_error "Pod is not running. Current status: $pod_status ${CROSS}"
        # Check for events related to this pod
        kubectl get events -n ecommerce --field-selector involvedObject.kind=Pod,involvedObject.name=$(kubectl get pods -n ecommerce -l app=${service}-service -o jsonpath='{.items[0].metadata.name}') --sort-by='.lastTimestamp'
        return 1
    fi
    
    if [[ "$container_status" != "true" ]]; then
        log_error "Container is not ready ${CROSS}"
        # Get container logs
        kubectl logs -n ecommerce -l app=${service}-service --tail=50
        return 1
    fi
    
    log_success "Pod for ${service} is running and ready ${TICK}"
    return 0
}

check_service_readiness() {
    local service=$1
    local max_retries=30
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if kubectl get pods -n ecommerce -l app=${service}-service -o jsonpath='{.items[0].status.containerStatuses[0].ready}' | grep -q "true"; then
            log_success "${service} service is ready ${TICK}"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_info "Waiting for ${service} service to be ready... (attempt $retry_count/$max_retries)"
        
        # Show recent logs
        kubectl logs -n ecommerce -l app=${service}-service --tail=20 || true
        
        sleep 10
    done
    
    log_error "${service} service failed to become ready ${CROSS}"
    return 1
}
