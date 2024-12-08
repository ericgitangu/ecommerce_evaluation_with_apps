#!/bin/bash

# Stop execution on error
set -e

# Apply secrets
echo "Creating secrets..."
kubectl apply -f secrets.yaml -n ecommerce

# Namespace creation (non-blocking)
echo "Creating namespaces (if not exist)..."
for ns in monitoring logging messaging database istio-system; do
  kubectl create namespace "$ns" 2>/dev/null || true
done

# Deploy Prometheus
echo "Deploying Prometheus..."
kubectl apply -f prometheus/prometheus-configmap.yaml -n monitoring
kubectl apply -f prometheus/k8s/deployment.yaml -n monitoring
kubectl apply -f prometheus/k8s/service.yaml -n monitoring

# Deploy Grafana
echo "Deploying Grafana..."
kubectl apply -f grafana/k8s/deployment.yaml -n monitoring
kubectl apply -f grafana/k8s/service.yaml -n monitoring

# Create Grafana dashboard configmap
echo "Configuring Grafana..."
kubectl create configmap grafana-dashboard --from-file=grafana/dashboards/flask-services.json -n monitoring

# Apply Grafana datasource and dashboards
kubectl apply -f grafana/k8s/datasource.yaml -n monitoring
kubectl apply -f grafana/k8s/dashboard-provisioning.yaml -n monitoring

# Deploy Elasticsearch
echo "Deploying Elasticsearch..."
kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
kubectl apply -f elasticsearch/k8s/service.yaml -n logging

# Deploy RabbitMQ (delete old resources and recreate)
echo "Deploying RabbitMQ..."
kubectl delete -f rabbitmq/k8s/deployment.yaml -n messaging --ignore-not-found
kubectl delete -f rabbitmq/k8s/service.yaml -n messaging --ignore-not-found
kubectl create -f rabbitmq/k8s/deployment.yaml -n messaging --save-config
kubectl create -f rabbitmq/k8s/service.yaml -n messaging --save-config

# Deploy PostgreSQL (delete old resources and recreate)
echo "Deploying PostgreSQL..."
kubectl delete -f postgres/k8s/deployment.yaml -n database --ignore-not-found
kubectl delete -f postgres/k8s/service.yaml -n database --ignore-not-found
kubectl create -f postgres/k8s/deployment.yaml -n database --save-config
kubectl create -f postgres/k8s/service.yaml -n database --save-config

# Get the Kind cluster name
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
echo "Using Kind cluster: ${CLUSTER_NAME}"

# Pull and load Istio images into Kind
echo "Pulling and loading Istio images..."
docker pull docker.io/istio/pilot:1.24.1
docker pull docker.io/istio/proxyv2:1.24.1
kind load docker-image docker.io/istio/pilot:1.24.1 --name "${CLUSTER_NAME}"
kind load docker-image docker.io/istio/proxyv2:1.24.1 --name "${CLUSTER_NAME}"

# Wait before health checks
echo "Waiting for resources to be ready..."
sleep 30

# Verify Istio configuration before installation
echo "Analyzing Istio configuration..."
if ! istioctl analyze istio/k8s/deployment.yaml --use-kube=false; then
  echo "Istio configuration validation failed. Halting..."
  exit 1
else
  echo "No validation issues found for Istio configuration."
fi

# Now install Istio with full configuration
echo "Installing Istio..."
if ! istioctl install -f istio/k8s/deployment.yaml --set profile=demo -y; then
  echo "Istio installation failed. Running diagnostics..."
  echo "Configuration validation:"
  istioctl analyze -n istio-system
  echo "Pod Status:"
  kubectl get pods -n istio-system
  echo "Events:"
  kubectl get events -n istio-system --sort-by='.lastTimestamp'
  exit 1
fi

# Wait for Istio pods to be ready (increased timeout)
echo "Waiting for Istio pods to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s

# Apply mesh configuration after Istio is fully ready
echo "Applying Istio mesh configuration..."
kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=300s
kubectl apply -f istio/k8s/mesh-config.yaml

# Configure namespace injection
echo "Configuring Istio injection for namespaces..."
# Explicitly disable Istio injection for default namespace
kubectl label namespace default istio-injection=disabled --overwrite

# Enable Istio injection for required namespaces
for ns in ecommerce; do
  kubectl label namespace "$ns" istio-injection=enabled --overwrite
done

# Wait for Istio pods to be ready
echo "Waiting for Istio pods to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s || true

# Verify installation and wait for webhook
echo "Verifying Istio installation..."
istioctl analyze || true

# Additional wait for Istio system namespace population
echo "Waiting for Istio system namespace to be populated..."
sleep 30

# Check and wait for webhook configuration
echo "Waiting for Istio webhook configuration..."
for i in {1..30}; do
  if kubectl get validatingwebhookconfiguration istiod-istio-system >/dev/null 2>&1; then
    echo "Webhook configuration found, waiting for it to be ready..."
    kubectl wait --for=condition=ready -n istio-system validatingwebhookconfiguration/istiod-istio-system --timeout=30s
    break
  else
    echo "Waiting for webhook configuration to be created... (attempt $i/30)"
    sleep 10
  fi
  if [ $i -eq 30 ]; then
    echo "Warning: Webhook configuration not found after 5 minutes. Continuing deployment..."
  fi
done

# Deploy application services
for service in order catalog search frontend; do
  echo "Deploying $service service..."
  kubectl apply -f app/$service/k8s/deployment.yaml
  kubectl apply -f app/$service/k8s/service.yaml
  kubectl apply -f app/$service/k8s/hpa.yaml
done

# Apply Authorization Policies
echo "Applying Authorization Policies..."
kubectl apply -f istio/k8s/auth-policy.yaml

# Verification steps for deployments
echo "Verifying resources..."
kubectl wait --for=condition=available --timeout=60s deployment --all -n monitoring
kubectl wait --for=condition=available --timeout=60s deployment --all -n logging
kubectl wait --for=condition=available --timeout=60s deployment --all -n messaging
kubectl wait --for=condition=available --timeout=60s deployment --all -n database
kubectl wait --for=condition=available --timeout=60s deployment --all -n ecommerce

kubectl get pods -A
kubectl get services -A

# Display pod resource allocations and usage
echo "Displaying pod resource allocations..."
kubectl get pods -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU_REQUEST:.spec.containers[*].resources.requests.cpu,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEMORY_REQUEST:.spec.containers[*].resources.requests.memory,MEMORY_LIMIT:.spec.containers[*].resources.limits.memory"

echo -e "\nCurrent resource usage by pods:"
if command -v kubectl-top-plugin &>/dev/null; then
  kubectl top pods -A
else
  echo "kubectl top not available, skipping resource usage."
fi

# Set up port forwarding
echo "Setting up port forwarding..."
kubectl port-forward -n monitoring svc/prometheus-service 9090:9090 &
kubectl port-forward -n monitoring svc/grafana-service 3000:3000 &
kubectl port-forward -n logging svc/elasticsearch-service 9200:9200 &
kubectl port-forward -n messaging svc/rabbitmq-service 5672:5672 15672:15672 &
kubectl port-forward -n database svc/postgres-service 5432:5432 &
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

echo "Services are available at:"
echo "- Prometheus: http://localhost:9090"
echo "- Grafana: http://localhost:3000"
echo "- Elasticsearch: http://localhost:9200"
echo "- RabbitMQ Management: http://localhost:15672"
echo "- PostgreSQL: localhost:5432"
echo "- Istio Gateway: http://localhost:8080"
