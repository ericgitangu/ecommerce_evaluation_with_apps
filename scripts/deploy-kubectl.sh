#!/bin/bash

# Stop execution on error
set -e

# Environment variables for optional components
DEPLOY_MONITORING=${DEPLOY_MONITORING:-true}
DEPLOY_LOGGING=${DEPLOY_LOGGING:-true}

# Create namespaces first
echo "Creating namespaces (if not exist)..."
for ns in istio-system database messaging ecommerce monitoring logging; do
  kubectl create namespace "$ns" 2>/dev/null || true
done

# Apply secrets early
echo "Creating secrets..."
kubectl apply -f secrets.yaml -n ecommerce

# 1. Install Istio First (Core Service Mesh)
echo "Setting up Istio..."
# Get the Kind cluster name
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
echo "Using Kind cluster: ${CLUSTER_NAME}"

# Pull and load Istio images into Kind
echo "Pulling and loading Istio images..."
docker pull docker.io/istio/pilot:1.24.1
docker pull docker.io/istio/proxyv2:1.24.1
kind load docker-image docker.io/istio/pilot:1.24.1 --name "${CLUSTER_NAME}"
kind load docker-image docker.io/istio/proxyv2:1.24.1 --name "${CLUSTER_NAME}"

# Verify Istio configuration before installation
echo "Analyzing Istio configuration..."
if ! istioctl analyze istio/k8s/deployment.yaml --use-kube=false; then
  echo "Istio configuration validation failed. Halting..."
  exit 1
fi

# Install Istio
echo "Installing Istio..."
if ! istioctl install -f istio/k8s/deployment.yaml --set profile=demo -y; then
  echo "Istio installation failed. Running diagnostics..."
  istioctl analyze -n istio-system
  kubectl get pods -n istio-system
  kubectl get events -n istio-system --sort-by='.lastTimestamp'
  exit 1
fi

# Wait for Istio core components
echo "Waiting for Istio core components..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s || true

# Configure namespace injection
kubectl label namespace default istio-injection=disabled --overwrite
kubectl label namespace istio-system istio-injection=disabled --overwrite
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# Apply mesh configuration
kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s || true
kubectl apply -f istio/k8s/mesh-config.yaml

# 2. Deploy Core Database
echo "Deploying PostgreSQL..."
kubectl apply -f postgres/k8s/deployment.yaml -n database
kubectl apply -f postgres/k8s/service.yaml -n database
echo "Waiting for PostgreSQL..."
kubectl wait --for=condition=available --timeout=300s deployment -l app=postgres -n database || true

# 3. Deploy Message Broker
echo "Deploying RabbitMQ..."
kubectl apply -f rabbitmq/k8s/deployment.yaml -n messaging
kubectl apply -f rabbitmq/k8s/service.yaml -n messaging
echo "Waiting for RabbitMQ..."
kubectl wait --for=condition=available --timeout=300s deployment -l app=rabbitmq -n messaging || true

# 4. Deploy Application Services
echo "Deploying application services..."
for service in frontend catalog order search; do
  echo "Deploying $service service..."
  kubectl apply -f app/$service/k8s/deployment.yaml
  kubectl apply -f app/$service/k8s/service.yaml
  kubectl apply -f app/$service/k8s/hpa.yaml
  echo "Waiting for $service service..."
  kubectl wait --for=condition=available --timeout=180s deployment/$service-service -n ecommerce || true
done

# Apply Authorization Policies
echo "Applying Authorization Policies..."
kubectl apply -f istio/k8s/auth-policy.yaml

# 5. Deploy Monitoring Stack (Optional)
if [ "$DEPLOY_MONITORING" = "true" ]; then
  echo "Deploying Prometheus..."
  kubectl apply -f prometheus/prometheus-configmap.yaml -n monitoring
  kubectl apply -f prometheus/k8s/deployment.yaml -n monitoring
  kubectl apply -f prometheus/k8s/service.yaml -n monitoring
  
  echo "Deploying Grafana..."
  kubectl apply -f grafana/k8s/deployment.yaml -n monitoring
  kubectl apply -f grafana/k8s/service.yaml -n monitoring
  kubectl create configmap grafana-dashboard --from-file=grafana/dashboards/flask-services.json -n monitoring || true
  kubectl apply -f grafana/k8s/datasource.yaml -n monitoring
  kubectl apply -f grafana/k8s/dashboard-provisioning.yaml -n monitoring
  
  echo "Waiting for monitoring services..."
  kubectl wait --for=condition=available --timeout=180s deployment --all -n monitoring || true
fi

# 6. Deploy Logging Stack (Optional)
if [ "$DEPLOY_LOGGING" = "true" ]; then
  echo "Deploying Elasticsearch..."
  kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
  kubectl apply -f elasticsearch/k8s/service.yaml -n logging
  echo "Waiting for Elasticsearch..."
  kubectl rollout status deployment/elasticsearch --timeout=300s -n logging || true
fi

# Display status
echo "Current cluster status:"
kubectl get pods -A
kubectl get services -A
kubectl get deployments -A

# Display resource allocations
echo "Displaying pod resource allocations..."
kubectl get pods -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU_REQUEST:.spec.containers[*].resources.requests.cpu,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEMORY_REQUEST:.spec.containers[*].resources.requests.memory,MEMORY_LIMIT:.spec.containers[*].resources.limits.memory"

# Set up port forwarding for core services
echo "Setting up port forwarding..."
kubectl port-forward -n database svc/postgres 5432:5432 &
kubectl port-forward -n messaging svc/rabbitmq 5672:5672 15672:15672 &
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

# Optional monitoring and logging port forwards
if [ "$DEPLOY_MONITORING" = "true" ]; then
  kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
  kubectl port-forward -n monitoring svc/grafana 3000:3000 &
fi

if [ "$DEPLOY_LOGGING" = "true" ]; then
  kubectl port-forward -n logging svc/elasticsearch 9200:9200 &
fi

echo "Services are available at:"
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

echo "Deployment complete!"
