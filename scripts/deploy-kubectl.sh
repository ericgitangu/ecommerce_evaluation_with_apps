#!/bin/bash

# Stop execution on error
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
TICK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"

# Logging functions
log_info() { echo -e "${BLUE}INFO:${NC} $1"; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_warning() { echo -e "${YELLOW}WARNING:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1"; }

# Environment variables for optional components
DEPLOY_MONITORING=${DEPLOY_MONITORING:-true}
DEPLOY_LOGGING=${DEPLOY_LOGGING:-true}

# Utility: wait for a deployment to be ready, if not print debug info and fail
wait_for_deployment() {
    local name=$1
    local namespace=$2
    local timeout=${3:-180s}

    log_info "Waiting for deployment $name in namespace $namespace..."
    if ! kubectl rollout status deployment/$name -n $namespace --timeout=$timeout; then
        log_error "Deployment $name failed to become ready ${CROSS}"
        log_info "=== Deployment Describe ==="
        kubectl describe deployment $name -n $namespace || true

        log_info "=== Pods ==="
        kubectl get pods -n $namespace -l app=$name || true

        log_info "=== Pod Details ==="
        kubectl describe pods -n $namespace -l app=$name || true

        log_info "=== Pod Logs ==="
        kubectl logs -n $namespace -l app=$name --tail=50 || true

        exit 1
    fi
    log_success "Deployment $name is ready ${TICK}"
}

# Utility: wait for a StatefulSet to be ready, if not print debug info and fail
wait_for_statefulset() {
    local name=$1
    local namespace=$2
    local timeout=${3:-180s}
    log_info "Waiting for StatefulSet $name in namespace $namespace..."
    if ! kubectl rollout status statefulset/$name -n $namespace --timeout=$timeout; then
        log_error "StatefulSet $name failed to become ready ${CROSS}"
        log_info "=== StatefulSet Describe ==="
        kubectl describe statefulset $name -n $namespace || true

        log_info "=== Pods ==="
        kubectl get pods -n $namespace -l app=$name || true

        log_info "=== Pod Details ==="
        kubectl describe pods -n $namespace -l app=$name || true

        log_info "=== Pod Logs ==="
        kubectl logs -n $namespace -l app=$name --tail=50 || true

        exit 1
    fi
    log_success "StatefulSet $name is ready ${TICK}"
}

# Deploy core services (PostgreSQL, RabbitMQ)
deploy_core_services() {
    # Check if metrics server is already installed
    if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
        log_info "Metrics server already installed ${TICK}"
    else
        # Deploy metrics server
        log_info "Deploying metrics server..."
        if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
            log_error "Failed to deploy metrics server ${CROSS}"
            exit 1
        fi

        # Patch metrics-server for Kind's self-signed certificates
        kubectl patch deployment metrics-server \
          -n kube-system \
          --type=json \
          -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

        # Wait for metrics-server to be ready
        if ! kubectl wait --for=condition=available --timeout=90s deployment/metrics-server -n kube-system; then
            log_warning "Metrics server not fully ready ${CROSS}"
        else
            log_success "Metrics server deployed successfully ${TICK}"
        fi
    fi

    # Show metrics server status at the end
    log_info "Metrics Server Status:"
    kubectl get pods -n kube-system | grep metrics-server
    kubectl top nodes || true
    kubectl top pods -n ecommerce || true

    # Create secrets for each namespace
    for ns in database messaging ecommerce monitoring logging; do
        log_info "Creating secrets in $ns namespace..."
        if ! kubectl create secret generic service-secrets \
            --namespace="$ns" \
            --from-literal=postgres-username=postgres \
            --from-literal=postgres-password=mysecretpassword \
            --from-literal=postgres-database=postgres \
            --from-literal=rabbitmq-username=admin \
            --from-literal=rabbitmq-password=adminpassword \
            --dry-run=client -o yaml | kubectl apply -f -
        then
            log_error "Failed to create secrets in the $ns namespace ${CROSS}"
            exit 1
        fi
        log_success "Secrets created in $ns namespace ${TICK}"
    done

    log_info "Deploying PostgreSQL..."
    if ! kubectl apply -f postgres/k8s/deployment.yaml -n database; then
        log_error "Failed to apply PostgreSQL configuration ${CROSS}"
        exit 1
    fi
    wait_for_statefulset postgres database 300s

    log_info "Deploying RabbitMQ..."
    kubectl apply -f rabbitmq/k8s/deployment.yaml -n messaging
    kubectl apply -f rabbitmq/k8s/service.yaml -n messaging
    wait_for_deployment rabbitmq messaging 300s
}

# Deploy application services (frontend, catalog, order, search)
deploy_application_services() {
    log_info "Deploying application services..."
    for service in frontend catalog order search; do
        log_info "Deploying $service service..."
        kubectl apply -f app/$service/k8s/deployment.yaml
        kubectl apply -f app/$service/k8s/service.yaml
        kubectl apply -f app/$service/k8s/hpa.yaml
        wait_for_deployment "${service}-service" ecommerce 180s
    done

    log_info "Applying Authorization Policies..."
    if kubectl apply -f istio/k8s/auth-policy.yaml; then
        log_success "Authorization policies applied ${TICK}"
    else
        log_error "Failed to apply authorization policies ${CROSS}"
        exit 1
    fi
}

# Deploy monitoring stack (Prometheus, Grafana)
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

        log_info "Waiting for monitoring deployments..."
        # If monitoring fails, just warn; don’t fail the entire pipeline
        if ! kubectl wait --for=condition=available --timeout=180s deployment --all -n monitoring; then
            log_warning "Monitoring stack not fully ready ${CROSS}"
        else
            log_success "Monitoring stack deployed successfully ${TICK}"
        fi
    fi
}

# Deploy logging stack (Elasticsearch)
deploy_logging() {
    if [ "$DEPLOY_LOGGING" = "true" ]; then
        log_info "Deploying logging stack (Elasticsearch)..."
        kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
        kubectl apply -f elasticsearch/k8s/service.yaml -n logging
        # If Elasticsearch fails, just warn
        if ! kubectl rollout status deployment/elasticsearch --timeout=300s -n logging; then
            log_warning "Elasticsearch deployment incomplete ${CROSS}"
        else
            log_success "Elasticsearch deployed successfully ${TICK}"
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

# Main execution flow

log_info "Creating namespaces..."
for ns in istio-system database messaging ecommerce monitoring logging; do
    if kubectl create namespace "$ns" 2>/dev/null; then
        log_success "Created namespace $ns ${TICK}"
    else
        log_info "Namespace $ns already exists ${TICK}"
    fi
done

log_info "Setting up Istio..."
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
log_info "Using Kind cluster: ${CLUSTER_NAME}"

# Pull Istio images
for image in "pilot:1.24.1" "proxyv2:1.24.1"; do
    if ! docker pull "docker.io/istio/$image"; then
        log_error "Failed to pull istio/$image ${CROSS}"
        exit 1
    fi
    if ! kind load docker-image "docker.io/istio/$image" --name "${CLUSTER_NAME}"; then
        log_error "Failed to load istio/$image into Kind ${CROSS}"
        exit 1
    fi
    log_success "Loaded istio/$image into Kind ${TICK}"
done

if ! istioctl install -f istio/k8s/deployment.yaml --set profile=demo -y; then
    log_error "Istio installation failed ${CROSS}"
    exit 1
fi
log_success "Istio installed ${TICK}"

log_info "Waiting for Istio core components..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s || true

kubectl label namespace default istio-injection=disabled --overwrite
kubectl label namespace istio-system istio-injection=disabled --overwrite
kubectl label namespace ecommerce istio-injection=enabled --overwrite

kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s || true
kubectl apply -f istio/k8s/mesh-config.yaml

deploy_core_services
deploy_application_services
deploy_monitoring
deploy_logging

sleep 60 # wait for all pods to come up

log_info "Waiting for all pods to come up before port forwarding..."
if ! kubectl wait --for=condition=ready pod --all --timeout=600s; then
    log_error "Not all pods are ready, proceeding with port forwarding anyway ${CROSS}"
else
    log_success "All pods are ready, proceeding with port forwarding ${TICK}"
fi

setup_port_forwarding

log_info "Current cluster status:"
kubectl get pods -A
kubectl get services -A
kubectl get deployments -A

log_info "Metrics Server Status:"
echo "Metrics Server Pod:"
kubectl get pods -n kube-system | grep metrics-server
echo -e "\nNode Resource Usage:"
kubectl top nodes || true
echo -e "\nPod Resource Usage:"
kubectl top pods -n ecommerce || true

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

log_info "Waiting for all pods to be ready..."
if ! kubectl wait --for=condition=ready pod --all --timeout=300s; then
    log_error "Not all pods are ready, proceeding with script anyway ${CROSS}"
else
    log_success "All pods are ready, steps completed! ${TICK}"
fi

log_info "Service IP Addresses:"
echo "Core Services:"
kubectl get service -n database postgres-postgresql -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- PostgreSQL: {}"
kubectl get service -n messaging rabbitmq -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- RabbitMQ: {}"
kubectl get service -n istio-system istio-ingressgateway -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Istio Gateway: {}"

echo -e "\nApplication Services:"
kubectl get service -n ecommerce frontend-service -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Frontend Service: {}"
kubectl get service -n ecommerce catalog-service -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Catalog Service: {}"
kubectl get service -n ecommerce search-service -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Search Service: {}"
kubectl get service -n ecommerce order-service -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Order Service: {}"

if [ "$DEPLOY_MONITORING" = "true" ]; then
  echo -e "\nMonitoring Services:"
  kubectl get service -n monitoring prometheus-server -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Prometheus: {}"
  kubectl get service -n monitoring grafana -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Grafana: {}"
fi

if [ "$DEPLOY_LOGGING" = "true" ]; then
  echo -e "\nLogging Services:"
  kubectl get service -n logging elasticsearch-master -o jsonpath='{.spec.clusterIP}' | xargs -I {} echo "- Elasticsearch: {}"
fi


log_success "Deployment complete! ${TICK}"
