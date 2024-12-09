# E-commerce Microservices Project

[![CI/CD Pipeline](https://github.com/ericgitangu/microservices/actions/workflows/github-actions.yml/badge.svg)](https://github.com/ericgitangu/microservices/actions/workflows/github-actions.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project implements an e-commerce system using a microservices architecture. Each service is built with Flask, and the project is designed to be cloud-native, leveraging Kubernetes for orchestration and Prometheus and Grafana for observability.

## Achievements:

As per the requirements, the following have been achieved, all works have been cited within the relevant manifest files

1. Debug and deploy the services using provided manifests - each service and 3rd party app has its own manifests files within folders named k8s.
2. Address issues in the CI/CD pipeline - set up an automated CI/CD pipeline which is passing, click on the badge for more information.
3. Use logs and metrics to identify and fix issues - using prometheus, integrated grafana and local logs mounted on containers (git excluded for security).
4. Provide solutions for security and cost optimization - using istio for app mesh for secure intra service interactions (mTLS, RBAC, sidecar injection - envoy) enabled. Project is using the host ecommerce.local, routes traffic approproately and for cost using light weight containers and a lightweight Kubernetes in docker setup.

## Project Structure

```bash
.
├── LICENSE
├── README.md
├── app
│   ├── catalog
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   ├── data
│   │   │   └── catalogue_data.json
│   │   └── requirements.txt
│   ├── frontend
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   ├── k8s
│   │   │   ├── deployment.yaml
│   │   │   ├── hpa.yaml
│   │   │   └── service.yaml
│   │   └── requirements.txt
│   ├── order
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   ├── k8s
│   │   │   ├── deployment.yaml
│   │   │   ├── hpa.yaml
│   │   │   └── service.yaml
│   │   └── requirements.txt
│   └── search
│       ├── Dockerfile
│       ├── app.py
│       ├── data
│       │   └── search_data.json
│       └── requirements.txt
├── elasticsearch
│   └── k8s
│       ├── deployment.yaml
│       └── service.yaml
├── grafana
│   ├── dashboards
│   │   └── flask-services.json
│   └── k8s
│       ├── deployment.yaml
│       └── service.yaml
├── logs_and_metrics
├── manifests
├── postgres
│   └── k8s
│       ├── deployment.yaml
│       └── service.yaml
├── prometheus
│   ├── k8s
│   │   ├── config
│   │   │   └── prometheus.yml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── prometheus-configmap.yaml
├── rabbitmq
│   └── k8s
│       ├── deployment.yaml
│       └── service.yaml
└── scripts
    ├── deploy-helm.sh
    └── deploy-kubectl.sh
```


## Microservices Overview

### 1. Catalog Service
- **Purpose**: Manages product catalog data.
- **Endpoints**:
  - `/catalog`: Fetch catalog data.
  - `/metrics`: Metrics for Prometheus.
  - `/health`: Health check endpoint.
- **Integrations**:
  - PostgreSQL for storage.
  - Prometheus for metrics collection.

### 2. Frontend Service
- **Purpose**: Acts as a gateway for the user-facing application.
- **Endpoints**:
  - `/`: Home route.
  - `/health`: Health check.

### 3. Order Service
- **Purpose**: Manages customer orders.
- **Endpoints**:
  - `/create-order`: Handles new orders.
  - `/metrics`: Metrics for Prometheus.
  - `/health`: Health check endpoint.
- **Integrations**:
  - RabbitMQ for message queueing.
  - PostgreSQL for order persistence.

### 4. Search Service
- **Purpose**: Provides search functionality over the catalog data.
- **Endpoints**:
  - `/search`: Query products.
  - `/metrics`: Metrics for Prometheus.
  - `/health`: Health check.
- **Integrations**:
  - Elasticsearch for search indexing.

### 5. Service Mesh Security

#### Istio Integration
- Replaces Nginx Ingress with Istio Service Mesh
- Provides mTLS encryption between services
- Implements fine-grained RBAC
- Manages traffic routing and load balancing

#### Security Features
1. **mTLS Authentication**
   - Automatic encryption between services
   - Certificate management handled by Istio
   - STRICT mode enforced across namespace

2. **Authorization Policies**
   - Frontend Service: Public access to / and /health
   - Catalog Service: Only accessible by Frontend
   - Order Service: Protected endpoints with method restrictions
   - Search Service: Controlled access from Frontend

3. **Traffic Management**
   - Route definitions via Virtual Services
   - Load balancing across service instances
   - Circuit breaking and fault injection capabilities

#### Accessing Services
- All external traffic routes through Istio Ingress Gateway
- Internal service-to-service communication secured by mTLS
- Original ports and endpoints remain unchanged

## Deployment

### Prerequisites
- Kubernetes cluster (local or cloud-based).
- `kubectl` installed and configured.
- Helm installed for package management.

### Steps

1. **Deploy Secrets**:
    ```bash
      kubectl apply -f secrets.yaml
    ```
2. **Deploy Services**:
    ```bash
      ./scripts/deploy-kubectl.sh
    ```
3. **Verify Resources**:
    ```
      kubectl get pods -n ecommerce
      kubectl get services -n ecommerce
    ```
4. **Deploy Helm Charts**:
    ```
      ./scripts/deploy-helm.sh
    ```
5. **Access Services**:
    - Frontend: <Node_IP>:<Port>
    - Metrics: Access Prometheus and Grafana for system observability. 

### Observability

#### **Prometheus**

- Scrapes metrics from the microservices and system components.
- Configured with prometheus.yml.

#### **Grafana**:

- Visualizes metrics collected by Prometheus.
- Dashboards defined in flask-services.json.

#### **Logging**
    
- Local file logging under the folder logs_and_metrics, each service has a volume mount for the logs. 
- Configured with utils/logger.py.

## Testing Microservices

To run this project locally you can use the following script: 

**Requirements**:
- Kind
- Kubectl
- Istioctl
- Helm

Run Locally:

    ```bash
      ./scripts/test-local.sh
    ```
It is Worth looking at the deploy-helm.sh that consolidates all of our helm installations and deploy-kubectl.sh that consolidates all of our deployment, service, hpa and configuration manifests applies them to deploy our apps and 3rd party dependencies to better understand how the test script works.

## Service Endpoints and Ports

### Catalog Service
- **Port**: 5001
- **Endpoints**:
  - `/catalog`: Fetch catalog data
  - `/metrics`: Prometheus metrics
  - `/health`: Health check endpoint
- **Internal Service Name**: catalog-service.ecommerce.svc.cluster.local

### Search Service
- **Port**: 5002
- **Endpoints**:
  - `/search`: Query products
  - `/metrics`: Prometheus metrics
  - `/health`: Health check endpoint
- **Internal Service Name**: search-service.ecommerce.svc.cluster.local

### Order Service
- **Port**: 5003
- **Endpoints**:
  - `/`: Home route
  - `/create-order`: Create new orders
  - `/metrics`: Prometheus metrics
  - `/health`: Health check endpoint
- **Internal Service Name**: order-service.ecommerce.svc.cluster.local

### Frontend Service
- **Port**: 5004
- **Endpoints**:
  - `/`: Home route
  - `/metrics`: Prometheus metrics
  - `/health`: Health check endpoint
- **Internal Service Name**: frontend-service.ecommerce.svc.cluster.local

### Supporting Services

#### Prometheus

(Mmonitoring): Scrapes orders, frontend, search & catalogue for metrics to report.
- **Port**: 9090
- **Internal Service Name**: prometheus.monitoring.svc.cluster.local
- **Access**: http://localhost:9090

#### Grafana

(Observability): Integrates with prometheus, pre-configured dashboards to highlight app level info.
- **Port**: 3000
- **Internal Service Name**: grafana.monitoring.svc.cluster.local
- **Access**: http://localhost:3000
- **Default Credentials**: admin/admin

#### Elasticsearch

Provides a convenient way to search; we have data folders with some rows for simulating searching.
- **Port**: 9200
- **Internal Service Name**: elasticsearch.logging.svc.cluster.local
- **Access**: http://localhost:9200

#### RabbitMQ

For message brokerage, orders are placed in queue and can be polled for processing and viewed on our dashboard.
- **Ports**: 
  - 5672 (AMQP)
  - 15672 (Management Interface)
- **Internal Service Name**: rabbitmq.messaging.svc.cluster.local
- **Access**: http://localhost:15672
- **Default Credentials**: admin/adminpassword

#### PostgreSQL

For ACID persistent storage using a slim version 15 package; for orders.
- **Port**: 5432
- **Internal Service Name**: postgres-postgresql.database.svc.cluster.local
- **Access**: localhost:5432
- **Default Credentials**: postgres/postgrespass

#### Nginx Ingress (Deprecated)

**Deprecated** over Istio, the folders and the deploy and service configs are still available.
- **Port**: 80
- **Internal Service Name**: nginx-ingress.ecommerce.svc.cluster.local
- **Access**: http://localhost:80
- **Configuration**: Managed via ConfigMap nginx-config

## **CI/CD Workflow**

Steps 1,2 & 3 happen in one step then proceeds to 4,5 & 6 if successful. 

1. Install: Installs helm charts for 3rd parties and install the apps requirements.
2. Deploy: Specifies the deploy parameters, deploys the services into our Kind cluster.
3. Test: Run a local test with Kind, this ensures we can create a cluster and operate interoperably with the services.
4. Build: Docker images for each service locally and load them into our Kind cluster.
5. Scan: Vulnerability scanning using Trivy - Optional to discover CVE's present.
6. Publish: Automate publish using GitHub Actions to my public [Dockhub Repo](https://hub.docker.com/repositories/egitangu).

## **License**
This project is licensed under the MIT License. See LICENSE for details, credits to Bineyame <bineyame.afework@engie.com>.
