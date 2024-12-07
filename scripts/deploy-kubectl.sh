#!/bin/bash

# Stop Execution on Error
set -e

# Apply secrets
echo "Creating secrets..."
kubectl apply -f secrets.yaml -n ecommerce

# Namespace creation - we already created these in deploy-helm.sh
# echo "Creating namespaces..."
# kubectl create namespace monitoring
# kubectl create namespace logging
# kubectl create namespace messaging
# kubectl create namespace database
# kubectl create namespace istio-system

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

# Create Istio service accounts
echo "Creating Istio service accounts..."
kubectl create namespace istio-system || true
kubectl create serviceaccount istiod -n istio-system || true
kubectl create serviceaccount istio-ingressgateway-service-account -n istio-system || true

# Create the required ConfigMap
echo "Creating initial Istio ConfigMap..."
kubectl create configmap istio-ca-root-cert -n istio-system || true

# Install Istio with basic configuration
echo "Installing Istio..."
istioctl install -f istio/k8s/istio-config.yaml -y || {
    echo "Istio installation failed. Running diagnostics..."
    kubectl describe nodes
    kubectl get pods -n istio-system
    kubectl describe pods -n istio-system
    kubectl logs -n istio-system -l app=istiod --tail=100
    kubectl get events -n istio-system --sort-by='.lastTimestamp'
    exit 1
}

# Wait for Istio components explicitly
echo "Waiting for Istio components..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s || true

# Add a sleep to allow initial creation of pods
echo "Waiting for Istio system namespace to be populated..."
sleep 30

# Enable Istio injection for ecommerce namespace
echo "Enabling Istio injection for ecommerce namespace..."
kubectl label namespace ecommerce istio-injection=enabled --overwrite

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
