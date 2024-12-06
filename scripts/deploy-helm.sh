#!/bin/bash

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add elastic https://helm.elastic.co
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Deploy Prometheus
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --create-namespace \
  --set server.configMapOverrideName=prometheus-config \
  --set alertmanager.enabled=false \
  --set pushgateway.enabled=false

# Deploy Grafana
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin \
  --create-namespace

# Deploy Elasticsearch
helm install elasticsearch elastic/elasticsearch \
  --namespace logging \
  --create-namespace

# Deploy RabbitMQ
helm install rabbitmq bitnami/rabbitmq \
  --namespace messaging \
  --set auth.username=admin \
  --set auth.password=adminpassword \
  --create-namespace

# Deploy PostgreSQL
helm install postgres bitnami/postgresql \
  --namespace database \
  --set auth.postgresPassword=mysecretpassword \
  --create-namespace
