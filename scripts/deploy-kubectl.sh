#!/bin/bash

# Stop Execution on Error
set -e

# Apply secrets
echo "Creating secrets..."
kubectl apply -f secrets.yaml -n ecommerce

# Namespace creation
echo "Creating namespaces, ignoring if already exists..."
kubectl create namespace monitoring 2>/dev/null || true
kubectl create namespace logging 2>/dev/null || true
kubectl create namespace messaging 2>/dev/null || true
kubectl create namespace database 2>/dev/null || true
kubectl create namespace istio-system 2>/dev/null || true

# Prometheus deployment
echo "Deploying Prometheus..."
kubectl apply -f prometheus/prometheus-configmap.yaml -n monitoring
kubectl apply -f prometheus/k8s/deployment.yaml -n monitoring
kubectl apply -f prometheus/k8s/service.yaml -n monitoring

# 1. Deploy base Grafana
kubectl apply -f grafana/k8s/deployment.yaml -n monitoring
kubectl apply -f grafana/k8s/service.yaml -n monitoring

# 2. Create dashboard configmap
kubectl create configmap grafana-dashboard --from-file=grafana/dashboards/flask-services.json -n monitoring

# 3. Configure Grafana
kubectl apply -f grafana/k8s/datasource.yaml -n monitoring
kubectl apply -f grafana/k8s/dashboard-provisioning.yaml -n monitoring

# Elasticsearch deployment
echo "Deploying Elasticsearch..."
kubectl apply -f elasticsearch/k8s/deployment.yaml -n logging
kubectl apply -f elasticsearch/k8s/service.yaml -n logging

# RabbitMQ deployment
echo "Deploying RabbitMQ..."
kubectl delete -f rabbitmq/k8s/deployment.yaml -n messaging --ignore-not-found
kubectl delete -f rabbitmq/k8s/service.yaml -n messaging --ignore-not-found
kubectl create -f rabbitmq/k8s/deployment.yaml -n messaging --save-config
kubectl create -f rabbitmq/k8s/service.yaml -n messaging --save-config

# PostgreSQL deployment
echo "Deploying PostgreSQL..."
kubectl delete -f postgres/k8s/deployment.yaml -n database --ignore-not-found
kubectl delete -f postgres/k8s/service.yaml -n database --ignore-not-found
kubectl create -f postgres/k8s/deployment.yaml -n database --save-config
kubectl create -f postgres/k8s/service.yaml -n database --save-config

# Get the kind cluster name
CLUSTER_NAME=$(kubectl config current-context | sed 's/kind-//')
echo "Using kind cluster: ${CLUSTER_NAME}"

# Pull and load Istio images
echo "Pulling and loading Istio images..."
docker pull docker.io/istio/pilot:1.24.1
docker pull docker.io/istio/proxyv2:1.24.1

echo "Loading images into kind cluster..."
kind load docker-image docker.io/istio/pilot:1.24.1 --name "${CLUSTER_NAME}"
kind load docker-image docker.io/istio/proxyv2:1.24.1 --name "${CLUSTER_NAME}"

# Create namespace and service accounts with retries
echo "Creating Istio namespace and service accounts..."
for i in {1..3}; do
    kubectl create namespace istio-system 2>/dev/null || true
    kubectl create serviceaccount istiod -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create istiod service account after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

for i in {1..3}; do
    kubectl create serviceaccount istio-ingressgateway-service-account -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create ingress gateway service account after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

# Create required ConfigMaps and Secrets with retries
echo "Creating initial Istio ConfigMaps and Secrets..."
for i in {1..3}; do
    kubectl create configmap istio-ca-root-cert -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create istio-ca-root-cert configmap after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

for i in {1..3}; do
    kubectl create configmap istio -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create istio configmap after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

# Create essential Istio secrets with retries
echo "Creating essential Istio secrets..."
for i in {1..3}; do
    kubectl create secret generic istiod-tls -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create istiod-tls secret after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

for i in {1..3}; do
    kubectl create secret generic istio-ingressgateway-certs -n istio-system && break || {
        if [ $i -eq 3 ]; then
            echo "Failed to create ingress gateway certs secret after 3 attempts"
            exit 1
        fi
        echo "Attempt $i failed, waiting 10s..."
        sleep 10
    }
done

# Wait longer for resources to be ready
echo "Waiting for resources to be ready..."
sleep 30

# Verify cluster health before proceeding
echo "Verifying cluster health..."
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# Verify the Istio configuration
echo "Analyzing Istio configuration..."
istioctl analyze \
    istio/k8s/deployment.yaml \
    --use-kube=false
    echo "Istio configuration validation failed. See errors above."
    exit 1
}

# Install Istio
istioctl install -f istio/k8s/deployment.yaml -y || {
    echo "Istio installation failed. Running diagnostics..."
    
    echo "Configuration validation:"
    istioctl analyze -n istio-system
    
    echo "Pod Status:"
    kubectl get pods -n istio-system
    
    echo "Events:"
    kubectl get events -n istio-system --sort-by='.lastTimestamp'
    
    echo "Resource Usage:"
    kubectl describe nodes | grep -A 5 "Allocated resources"
    
    exit 1
}

# Wait for pods explicitly after installation
echo "Waiting for Istio pods to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s || true

# Verify installation
echo "Verifying Istio installation..."
istioctl analyze || true

# Add a sleep to allow initial creation of pods
echo "Waiting for Istio system namespace to be populated..."
sleep 30

# Enable Istio injection for ecommerce namespace
echo "Enabling Istio injection for ecommerce namespace..."
kubectl label namespace ecommerce istio-injection=enabled --overwrite

# Wait for Istiod webhook to be ready before applying mesh config
echo "Waiting for Istiod webhook to be ready..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
kubectl wait --for=condition=ready -n istio-system validatingwebhookconfiguration/istiod-istio-system --timeout=300s || true

# Apply Istio configurations
echo "Applying Istio configurations..."
kubectl apply -f istio/k8s/mesh-config.yaml

# Now deploy the services
for service in order catalog search frontend; do
  echo "Deploying $service service..."
  kubectl apply -f app/$service/k8s/deployment.yaml
  kubectl apply -f app/$service/k8s/service.yaml
  kubectl apply -f app/$service/k8s/hpa.yaml
done

# Apply Authorization Policies
echo "Applying Authorization Policies..."
kubectl apply -f istio/k8s/auth-policy.yaml

# Verification Step
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

# Get current resource usage
echo -e "\nCurrent resource usage by pods:"
kubectl top pods -A



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
