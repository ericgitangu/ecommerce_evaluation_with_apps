# Microservices Platform Architecture Cheat Sheet

### A Comprehensive Guide for Interview Preparation

This guide provides a complete overview of the microservices platform's architecture, the rationale behind each chosen technology stack and tool, and how they integrate to form a scalable, secure, and maintainable system. Use this as a reference to understand the purpose, pros, and architectural justification of each component, as well as to review code snippets and configurations before an interview.

---

## Table of Contents

1. [System Architecture Overview](#1-system-architecture-overview)
2. [Rationale and Pros of Each Chosen Stack](#2-rationale-and-pros-of-each-chosen-stack)
   - [Docker & Dev Containers](#docker--dev-containers)
   - [Kubernetes](#kubernetes)
   - [Helm](#helm)
   - [Istio Service Mesh & Istioctl](#istio-service-mesh--istioctl)
   - [NGINX Ingress Controller](#nginx-ingress-controller)
   - [PostgreSQL](#postgresql)
   - [RabbitMQ](#rabbitmq)
   - [Prometheus & Grafana](#prometheus--grafana)
3. [Development Environment Configuration](#3-development-environment-configuration)
   - [Dockerfile](#31-dockerfile)
   - [Dev Container Configuration (`devcontainer.json`)](#32-dev-container-configuration-devcontainerjson)
4. [Kubernetes Setup](#4-kubernetes-setup)
   - [Installing `kind`](#41-installing-kind)
   - [Creating a Kubernetes Cluster](#42-creating-a-kubernetes-cluster)
5. [Helm Package Manager Usage](#5-helm-package-manager-usage)
   - [Installing Helm](#51-installing-helm)
   - [Deploying PostgreSQL via Helm](#52-deploying-postgresql-via-helm)
   - [Deploying RabbitMQ via Helm](#53-deploying-rabbitmq-via-helm)
   - [Deploying Prometheus & Grafana via Helm](#54-deploying-prometheus--grafana-via-helm)
   - [Deploying NGINX Ingress Controller via Helm](#55-deploying-nginx-ingress-controller-via-helm)
6. [Istio Service Mesh Integration](#6-istio-service-mesh-integration)
   - [Installing Istio](#61-installing-istio)
   - [Configuring Istio](#62-configuring-istio)
7. [Microservices Deployment](#7-microservices-deployment)
   - [Django (User Service)](#71-django-user-service)
   - [Ruby on Rails (Order Service)](#72-ruby-on-rails-order-service)
   - [Rust/Actix (Payment Service)](#73-rustactix-payment-service)
8. [Ingress Configuration](#8-ingress-configuration)
   - [Creating Ingress Resource](#81-creating-ingress-resource)
9. [Monitoring & Logging](#9-monitoring--logging)
   - [Accessing Grafana Dashboard](#91-accessing-grafana-dashboard)
10. [Common Bash Commands](#10-common-bash-commands)
11. [Quick Tips & Best Practices](#11-quick-tips--best-practices)

---

## 1. System Architecture Overview

**Purpose:**  
To establish a microservices-based platform that is scalable, maintainable, and secure. The architecture integrates multiple tools for containerization, orchestration, service mesh capabilities, ingress/egress management, asynchronous messaging, persistent storage, and observability.

**Architecture Diagram:**

bash

```
+----------------------+ +-----------------------+
| Clients | | GitHub Codespaces |
| (Browsers, Mobile) | | Dev Container |
+----------+-----------+ +-----------+-----------+
| |
v v
+----------------------+ +-----------------------+
| API Gateway | <------------> | Kubernetes |
| (NGINX Ingress Ctrl) | | Cluster |
+----------+-----------+ +-----------+-----------+
|
v
+----------+-----------+---------+-----------+------------+
| | | | | |
v v v v v v
+------+ +-------+ +-------+ +--------+ +---------+ +-----------+
| User | |Product| | Order | |Payment | | Rabbit | | PostgreSQL|
|Service| |Service| |Service| |Service | | MQ | | Database |
| :8000 | | :3000 | | :5000 | | :8080 | | :5672 | | :5432 |
+------+ +-------+ +-------+ +--------+ +---------+ +-----------+
| | | |
+-----------+---------+-----------+
|
v
+--------------+
| Service Mesh |
| (Istio) |
+--------------+
```

## Key Components:

- **Clients**: End-users interacting with the platform via browsers or mobile apps.
- **API Gateway (NGINX Ingress Controller)**: Manages and routes incoming traffic to appropriate microservices.
- **Kubernetes Cluster**: Orchestrates containerized applications, ensuring scalability and reliability.

## Microservices:

- **User Service (Django)**: Handles user authentication and management.
- **Product Service (Next.js)**: Manages product listings and inventory.
- **Order Service (Ruby on Rails)**: Processes orders and handles order-related operations.
- **Payment Service (Rust/Actix)**: Manages payment processing securely.

## Supporting Services:

- **RabbitMQ**: Facilitates asynchronous messaging between services.
- **PostgreSQL Database**: Provides persistent storage for application data.
- **Service Mesh (Istio)**: Enhances inter-service communication with features like traffic management, security, and observability.
- **Dev Container (GitHub Codespaces)**: Provides a consistent development environment leveraging Docker and Kubernetes.

## 2. Development Environment

### 2.1. Dockerfile

### Location: .devcontainer/Dockerfile

**Purpose**:

Sets up the development environment by installing necessary tools and dependencies. Leverages the host's Docker daemon for efficient resource usage.

### Key Components:

bash

```
    # Base Image
    FROM mcr.microsoft.com/devcontainers/base:bullseye

    # Install Docker CLI
    RUN apt-get update && apt-get install -y \
        docker.io \
        && rm -rf /var/lib/apt/lists/*

    # Update PATH
    ENV PATH="/usr/bin/docker:${PATH}"

    # Install Node.js >= 20
    RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get install -y nodejs

    # Install Python >= 3.11
    RUN apt-get update && apt-get install -y software-properties-common && \
        add-apt-repository ppa:deadsnakes/ppa && \
        apt-get install -y python3.11 python3.11-dev python3.11-distutils
    RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

    # Install pip for Python 3.11
    RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

    # Install Ruby and Bundler
    RUN apt-get install -y ruby-full
    RUN gem install bundler

    # Install Rust
    RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
    ENV PATH="$HOME/.cargo/bin:${PATH}"

    # Install PostgreSQL client
    RUN apt-get install -y postgresql-client

    # Install additional tools
    RUN apt-get install -y git curl

    # Install Vite globally
    RUN npm install -g vite

    # Cleanup
    RUN apt-get clean && rm -rf /var/lib/apt/lists/*
```

### Highlights.

- **Docker CLI**: Enables Docker commands within the Dev Container.
- **Node.js, Python, Ruby, Rust**: Supports microservices built with these languages.
- **PostgreSQL Client**: Facilitates database interactions.
- **Vite**: Assists with frontend tooling for services like Next.js.

### 2.2. Dev Container Configuration (devcontainer.json)

### Location: .devcontainer/devcontainer.json

**Purpose**:

- Defines the configuration for the Dev Container, including build instructions, environment settings, extensions, port forwarding, and volume mounts.

**Key Components**:

bash

```
{
    "name": "Docker Outside of Dockerfile",
    "build": {
        "dockerfile": "Dockerfile",
        "context": "."
    },
    "workspaceFolder": "/workspace/${localWorkspaceFolderBasename}",

    "remoteEnv": {
        "LOCAL_WORKSPACE_FOLDER": "${localWorkspaceFolder}"
    },

    "features": {
        "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {
            "version": "latest",
            "enableNonRootDocker": "true",
            "moby": "false"
        }
    },

    "extensions": [
        "ms-python.python",
        "ms-azuretools.vscode-docker",
        "dbaeumer.vscode-eslint",
        "rebornix.Ruby",
        "rust-lang.rust-analyzer",
        "Prisma.prisma",
        "ms-vscode.vscode-typescript-next",
        "esbenp.prettier-vscode",
        "eamodio.gitlens",
        "mhutchie.git-graph",
        "oderwat.indent-rainbow",
        "ms-kubernetes-tools.vscode-kubernetes-tools",
        "redhat.vscode-yaml",
        "bradlc.vscode-tailwindcss",
        "mui.material-ui-snippets"
    ],

    "forwardPorts": [8000, 3000, 5000, 8080, 5432, 5672, 15672],

    "mounts": [
        "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
        "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
    ],

    "postCreateCommand": "sudo apt-get update && sudo apt-get install -y libpq-dev"
}
```

### Highlights:

### Build Configuration:

- **dockerfile & context**: Points to the Dockerfile in the .devcontainer directory.

### Workspace:

- **\*workspaceFolder**: Mounts the project directory inside the container.

### Environment Variables:

- **remoteEnv**: Sets variables accessible within the container.

### Features

- docker-outside-of-docker:
- enableNonRootDocker: Allows Docker commands without root privileges.
- moby: Set to false to avoid installing Moby inside the container.

### Extensions:

- Includes essential VS Code extensions for Python, Ruby, Rust, Docker, Kubernetes, and frontend development.

## Port Forwarding:

- **forwardPorts**: Exposes service ports for external access (e.g., APIs, databases, RabbitMQ).

### Mounts:

- Docker Socket: Allows communication with the host's Docker daemon.

### Project Directory:

- Ensures file synchronization between host and container.

### Post-Creation Commands:

- Installs PostgreSQL development libraries (libpq-dev) required for Python packages like psycopg2.

## 3. Kubernetes Setup

**Purpose**:
Establish a local Kubernetes cluster using kind (Kubernetes in Docker) for orchestrating microservices, databases, and messaging systems.

### 3.1. Installing kind

Installation Script:

bash

```
# Download the latest kind binary
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64

# Make the binary executable
chmod +x ./kind

# Move it to a directory in your PATH
sudo mv ./kind /usr/local/bin/kind
```

### Verify Installation:

bash

```
kind version
```

### Expected Output:

bash

```
kind v0.20.0 go1.18.3 linux/amd64
```

### 3.2. Creating a Kubernetes Cluster

Command:

bash

```
kind create cluster --name ecommerce-cluster


### Verify Cluster:

bash
```

kubectl cluster-info --context kind-ecommerce-cluster

```

### Expected Output:

arduino
```

Kubernetes control plane is running at https://127.0.0.1:XXXXX

### Set Kubernetes Context:

bash

```
kubectl config use-context kind-ecommerce-cluster
```

## 4. Helm Package Manager

**Purpose**:
Use Helm as a package manager to deploy and manage Kubernetes applications like PostgreSQL, RabbitMQ, Prometheus, Grafana, and NGINX Ingress Controller.

### 4.1. Installing Helm

Installation Script:

bash

```
# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Verify Installation:

bash

```
helm version
```

### Expected Output:

css

```
version.BuildInfo{Version:"v3.8.0", GitCommit:"...", GitTreeState:"clean", GoVersion:"go1.18.3"}
```

### 4.2. Deploying PostgreSQL via Helm

**Rationale**:
PostgreSQL is a robust relational database system essential for storing structured data used by microservices.

### Commands:

bash

```
# Add Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create namespace (if not already created)
kubectl create namespace ecommerce

# Deploy PostgreSQL
helm install postgres bitnami/postgresql \
  --namespace ecommerce \
  --set global.postgresql.auth.postgresPassword=mysecretpassword \
  --set global.postgresql.auth.username=postgres \
  --set global.postgresql.auth.database=postgres \
  --set primary.persistence.enabled=true \
  --set primary.persistence.size=2Gi
```

### Key Configuration:

- **postgresPassword**: Sets the postgres user password.
- **username**: Database username.
- **database**: Initial database name.
- **persistence.enabled**: Enables persistent storage.
- **persistence.size**: Allocates storage size.

### Verify Deployment:

bash

```
kubectl get pods -n ecommerce -l app.kubernetes.io/name=postgresql
```

### Expected Output:

sql

```
NAME                       READY   STATUS    RESTARTS   AGE
postgres-postgresql-0      1/1     Running   0          2m
```

### 4.3. Deploying RabbitMQ via Helm

**Rationale**:
RabbitMQ facilitates asynchronous messaging between microservices, enabling reliable communication and decoupling.

**Commands**:

bash

```
# Deploy RabbitMQ
helm install rabbitmq bitnami/rabbitmq \
  --namespace ecommerce \
  --set auth.username=guest \
  --set auth.password=guest \
  --set auth.erlangCookie=mycookie \
  --set service.type=ClusterIP
```

### Key Configuration:

- auth.username & auth.password: RabbitMQ credentials.
- auth.erlangCookie: Required for clustering.
- service.type: Exposes RabbitMQ internally within the cluster.

### Verify Deployment:

bash

```
kubectl get pods -n ecommerce -l app.kubernetes.io/name=rabbitmq
```

### Expected Output:

sql

```
NAME                             READY   STATUS    RESTARTS   AGE
rabbitmq-0                       1/1     Running   0          2m
```

### 4.4. Deploying Prometheus & Grafana via Helm

**Rationale**:
Prometheus and Grafana provide monitoring and visualization, essential for observability of microservices' performance and health.

**Commands**:

bash

```
# Add Prometheus Community Repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/prometheus \
  --namespace ecommerce

# Install Grafana
helm install grafana prometheus-community/grafana \
  --namespace ecommerce \
  --set adminPassword=admin \
  --set service.type=ClusterIP
```

### Key Configuration:

- adminPassword: Sets Grafana admin password.
- service.type: Configures Grafana service type.

### Verify Installations:

bash

```
kubectl get pods -n ecommerce -l app.kubernetes.io/name=prometheus
kubectl get pods -n ecommerce -l app.kubernetes.io/name=grafana
```

### 4.5. Deploying NGINX Ingress Controller via Helm

**Rationale**:
NGINX Ingress Controller manages external access to services within the Kubernetes cluster, handling routing based on URL paths and hostnames.

**Commands**:

bash

```
# Add Ingress-NGINX Repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ecommerce \
  --create-namespace \
  --set controller.publishService.enabled=true
```

### Key Configuration:

- controller.publishService.enabled: Publishes the Ingress controller's service, enabling external access.

### Verify Installation:

bash

```
kubectl get pods -n ecommerce -l app.kubernetes.io/name=ingress-nginx
```

### Expected Output:

sql

```
NAME                                           READY   STATUS    RESTARTS   AGE
nginx-ingress-controller-xxxxxxxxxx-yyyyy        1/1     Running   0          2m
```

## 5. Istio Service Mesh

**Purpose**:
Enhances microservices with advanced features like traffic management, security (mTLS), and observability without modifying application code.

### 5.1. Installing Istio

Installation Script:

bash

```
# Download Istio
curl -L https://istio.io/downloadIstio | sh -

# Navigate to Istio directory
cd istio-1.18.0  # Replace with the latest version if different

# Add istioctl to PATH
export PATH=$PWD/bin:$PATH

# Verify istioctl installation
istioctl version
```

### Expected Output:

yaml

```
istioctl version: 1.18.0
```

### 5.2. Configuring Istio

Commands:

bash

```
# Install Istio with Demo Profile
istioctl install --set profile=demo -y

# Label Namespace for Automatic Sidecar Injection
kubectl label namespace ecommerce istio-injection=enabled

# Verify Istio Components
kubectl get pods -n istio-system
```

### Expected Output:

sql

```
NAME                                    READY   STATUS    RESTARTS   AGE
istiod-xxxxxxxxxx-yyyyy                  1/1     Running   0          5m
istio-ingressgateway-xxxxxxxxxx-yyyyy    1/1     Running   0          5m
```

### Highlights:

- Automatic Sidecar Injection: Ensures that each pod in the ecommerce namespace has an Istio sidecar (envoy) for enhanced communication.

## 6. Microservices Deployment

**Purpose**:
Deploy individual microservices (Django, Ruby on Rails, Rust/Actix) with necessary configurations and integrations.

### 6.1. Django (User Service)

Location: user_service/

**Purpose**:
Handles user authentication, management, and profiles.

### Deployment Steps:

- Build Docker Image:

bash

```
cd user_service/
docker build -t yourdockerhub/user-service:latest .
```

Push to Docker Hub:

bash

```
docker push yourdockerhub/user-service:latest
```

- Create Kubernetes Deployment (k8s/user-deployment.yaml):

yaml

```
# k8s/user-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: ecommerce
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
  template:
    metadata:
      labels:
        app: user-service
    spec:
      containers:
        - name: user-service
          image: yourdockerhub/user-service:latest
          ports:
            - containerPort: 8000
          env:
            - name: DB_HOST
              value: "postgres-postgresql.ecommerce.svc.cluster.local"
            - name: DB_NAME
              value: "postgres"
            - name: DB_USER
              value: "postgres"
            - name: DB_PASSWORD
              value: "mysecretpassword"
            - name: DB_PORT
              value: "5432"
            - name: RABBITMQ_HOST
              value: "rabbitmq.ecommerce.svc.cluster.local"
            - name: RABBITMQ_USER
              value: "guest"
            - name: RABBITMQ_PASSWORD
              value: "guest"
          imagePullPolicy: IfNotPresent
```

### Create Kubernetes Service (k8s/user-service.yaml):

yaml

```
# k8s/user-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: user-service
  namespace: ecommerce
spec:
  selector:
    app: user-service
  ports:
    - protocol: TCP
      port: 8000
      targetPort: 8000
  type: ClusterIP
```

- Apply Configurations:

bash

```
kubectl apply -f k8s/user-deployment.yaml
kubectl apply -f k8s/user-service.yaml
```

- Update Deployment with Latest Image:

bash

```
kubectl set image deployment/user-service user-service=yourdockerhub/user-service:latest -n ecommerce
kubectl rollout status deployment/user-service -n ecommerce
```

### 6.2. Ruby on Rails (Order Service)

Location: order_service/

**Purpose**:
Manages orders, processing, and order-related operations.

- Deployment Steps:

Build Docker Image:

bash

```
cd order_service/
docker build -t yourdockerhub/order-service:latest .
```

- Push to Docker Hub:

bash

```
docker push yourdockerhub/order-service:latest
```

- Create Kubernetes Deployment (k8s/order-deployment.yaml):

yaml

```
# k8s/order-deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
name: order-service
namespace: ecommerce
spec:
replicas: 2
selector:
matchLabels:
app: order-service
template:
metadata:
labels:
app: order-service
spec:
containers: - name: order-service
image: yourdockerhub/order-service:latest
ports: - containerPort: 5000
env: - name: DB_HOST
value: "postgres-postgresql.ecommerce.svc.cluster.local" - name: DB_NAME
value: "postgres" - name: DB_USER
value: "postgres" - name: DB_PASSWORD
value: "mysecretpassword" - name: DB_PORT
value: "5432" - name: RABBITMQ_HOST
value: "rabbitmq.ecommerce.svc.cluster.local" - name: RABBITMQ_USER
value: "guest" - name: RABBITMQ_PASSWORD
value: "guest"
imagePullPolicy: IfNotPresent
```

- Create Kubernetes Service (k8s/order-service.yaml):

yaml

```
# k8s/order-service.yaml

apiVersion: v1
kind: Service
metadata:
name: order-service
namespace: ecommerce
spec:
selector:
app: order-service
ports: - protocol: TCP
port: 5000
targetPort: 5000
type: ClusterIP
```

- Apply Configurations:

bash

```
kubectl apply -f k8s/order-deployment.yaml
kubectl apply -f k8s/order-service.yaml
```

- Update Deployment with Latest Image:

bash

```
kubectl set image deployment/order-service order-service=yourdockerhub/order-service:latest -n ecommerce
kubectl rollout status deployment/order-service -n ecommerce
```

### 6.3. Rust/Actix (Payment Service)

Location: payment_service/

**Purpose**:
Processes payments securely and efficiently.

Deployment Steps:

- Build Rust Binary:

bash

```
cd payment_service/
cargo build --release
```

- Build Docker Image:

bash

```
docker build -t yourdockerhub/payment-service:latest .
```

- Push to Docker Hub:

bash

```
docker push yourdockerhub/payment-service:latest
``

Create Kubernetes Deployment (k8s/payment-deployment.yaml):

yaml
```

# k8s/payment-deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
name: payment-service
namespace: ecommerce
spec:
replicas: 2
selector:
matchLabels:
app: payment-service
template:
metadata:
labels:
app: payment-service
spec:
containers: - name: payment-service
image: yourdockerhub/payment-service:latest
ports: - containerPort: 8080
env: - name: AMQP_URL
value: "amqp://guest:guest@rabbitmq.ecommerce.svc.cluster.local:5672/%2f"
imagePullPolicy: IfNotPresent

```

- Create Kubernetes Service (k8s/payment-service.yaml):

yaml
```

# k8s/payment-service.yaml

apiVersion: v1
kind: Service
metadata:
name: payment-service
namespace: ecommerce
spec:
selector:
app: payment-service
ports: - protocol: TCP
port: 8080
targetPort: 8080
type: ClusterIP

```

- Apply Configurations:

bash
```

kubectl apply -f k8s/payment-deployment.yaml
kubectl apply -f k8s/payment-service.yaml

```

- Update Deployment with Latest Image:

bash
```

kubectl set image deployment/payment-service payment-service=yourdockerhub/payment-service:latest -n ecommerce
kubectl rollout status deployment/payment-service -n ecommerce

```

##7. Ingress Configuration

**Purpose**:
Manages external access to the microservices via HTTP, routing requests based on URL paths and hostnames.

## 7.1. Creating Ingress Resource

Configuration (k8s/ingress.yaml):

yaml
```

# k8s/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
name: ecommerce-ingress
namespace: ecommerce
annotations:
nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: ecommerce.local
      http:
        paths:
          - path: /user-service(/|$)(._)
pathType: Prefix
backend:
service:
name: user-service
port:
number: 8000 - path: /order-service(/|$)(._)
pathType: Prefix
backend:
service:
name: order-service
port:
number: 5000 - path: /payment-service(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
          - path: /product-service(/|$)(.\*)
pathType: Prefix
backend:
service:
name: product-service
port:
number: 3000

```

**Highlights**:

host: Defines the hostname (e.g., ecommerce.local). Update /etc/hosts to map this to localhost.
paths: Routes specific URL paths to corresponding services.
rewrite-target: Rewrites the URL path before forwarding to the backend service.

### 7.2. Applying Ingress Resource
Command:

bash
```

kubectl apply -f k8s/ingress.yaml

```

### 7.3. Updating /etc/hosts for Local Testing
Command:

bash
```

sudo nano /etc/hosts

```

- Add the Following Line:

lua
```

127.0.0.1 ecommerce.local

```

- Save and Exit:

Press Ctrl+O, then Enter to save.
Press Ctrl+X to exit.

### 7.4. Accessing Services via Browser

- User Service: http://ecommerce.local/user-service/api/users/
- Order Service: http://ecommerce.local/order-service/orders/
- Payment Service: http://ecommerce.local/payment-service/process_payment
- Product Service: http://ecommerce.local/product-service/

### Note:
- Ensure that port forwarding for the Ingress controller is set up if accessing from outside the cluster.

### Optional Port Forwarding:

bash
```

kubectl port-forward --namespace ecommerce svc/nginx-ingress-ingress-nginx-controller 8080:80

```

Access Services via: http://localhost:8080/<service-path>

## 8. Monitoring & Logging

**Purpose**:
Implement observability tools to monitor and log the performance and health of microservices.

### 8.1. Accessing Grafana Dashboard

Steps:

- Port Forward Grafana Service:

bash
```

kubectl port-forward --namespace ecommerce svc/grafana 3000:80

```

Access Grafana:

Open your browser and navigate to http://localhost:3000.
Login Credentials:
- Username: admin
- Password: admin (as set during Helm installation)

### Configure Data Sources & Dashboards:

### Add Prometheus as a Data Source:

Navigate to Configuration > Data Sources > Add data source > Prometheus.
URL: http://prometheus-server.ecommerce.svc.cluster.local:80
Save & Test.

### Import Dashboards:

- Use pre-built dashboards from Grafana's dashboard repository for Kubernetes, Istio, Django, Rails, etc.
- Navigate to Create > Import and enter the dashboard ID.


### 8.2. Enable Istio Telemetry

Steps:

- Apply Istio Metrics Configuration:

- Istio automatically collects telemetry data. Ensure Prometheus is scraping Istio endpoints.

### Verify Metrics in Grafana:

Explore Prometheus data source in Grafana to view Istio and microservices metrics.

**Benefits**:

- Prometheus: Collects metrics from Kubernetes, Istio, and applications.
- Grafana: Visualizes metrics, enabling monitoring of system health and performance. 9. Common Bash

**Commands**

Purpose:
Quick reference for essential bash commands used in setting up and managing the microservices platform.

Command Purpose

- curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 Downloads the kind binary for Kubernetes cluster setup.
- chmod +x ./kind Makes the kind binary executable.
- sudo mv ./kind /usr/local/bin/kind Moves kind to a directory in the PATH for easy access.

- kind create cluster --name ecommerce-cluster Creates a new Kubernetes cluster named ecommerce-cluster using kind.
- kubectl cluster-info --context kind-ecommerce-cluster Displays information about the Kubernetes cluster context.
- kubectl config use-context kind-ecommerce-cluster Sets the current Kubernetes context to ecommerce-cluster.
- helm repo add bitnami https://charts.bitnami.com/bitnami Adds the Bitnami repository to Helm for accessing PostgreSQL and RabbitMQ charts.
- helm install postgres bitnami/postgresql --namespace ecommerce --set ... Deploys PostgreSQL using

### Helm with specified configurations.
- helm install rabbitmq bitnami/rabbitmq --namespace ecommerce --set ... Deploys RabbitMQ using Helm with specified configurations.
- helm repo add prometheus-community https://prometheus-community.github.io/helm-charts Adds the

### Prometheus Community repository to Helm.
- helm install prometheus prometheus-community/prometheus --namespace ecommerce Installs Prometheus monitoring tool via Helm.
- helm install grafana prometheus-community/grafana --namespace ecommerce --set ... Installs Grafana visualization tool via Helm.
- helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx Adds the Ingress-NGINX repository to Helm.
- helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ecommerce --set ... Deploys NGINX Ingress Controller via Helm.
- `curl -L https://istio.io/downloadIstio	sh -`
- istioctl install --set profile=demo -y Installs Istio with the demo profile for service mesh capabilities.
- kubectl label namespace ecommerce istio-injection=enabled Enables automatic Istio sidecar injection for the ecommerce namespace.
- kubectl apply -f k8s/<file>.yaml Applies Kubernetes configurations (Deployments, Services, Ingress, etc.).
- docker build -t yourdockerhub/<service>:latest . Builds a Docker image for a microservice.
docker push yourdockerhub/<service>:latest Pushes the Docker image to Docker Hub.
- kubectl set image deployment/<service> <service>=yourdockerhub/<service>:latest -n ecommerce Updates the Kubernetes deployment with the latest Docker image.
- kubectl rollout status deployment/<service> -n ecommerce Monitors the rollout status of a deployment.
- kubectl port-forward --namespace ecommerce svc/<service> <local>:<remote> Forwards a port from a Kubernetes service to the local machine for access.
- kubectl get pods -n ecommerce Lists all pods in the ecommerce namespace.
- kubectl describe pod <pod-name> -n ecommerce Provides detailed information about a specific pod.
- kubectl logs <pod-name> -n ecommerce Retrieves logs from a specific pod. 10. Quick Tips & Best

### Practices

- Consistency in Environment Variables:
- Ensure that environment variables in Kubernetes deployments match those expected by your microservices.

### Leverage Helm for Simplification:

- Use Helm charts for deploying complex applications like databases and message brokers to simplify configurations.

### Utilize Namespaces:

- Organize resources within namespaces (ecommerce) for better management and isolation.

### Monitor Deployments:

- Regularly check pod statuses and logs to identify and resolve issues promptly.

### Secure Your Services:

- Use strong passwords and consider implementing secrets management for sensitive data.

### Maintain Clear Project Structure:

- Keep dedicated directories for configurations (k8s/), services (user_service/, etc.), and the Dev Container (.devcontainer/).

### Automate Processes:

- Use CI/CD pipelines (e.g., GitHub Actions) to automate building, testing, and deploying your microservices.

### Document Thoroughly:

- Keep your README.md and internal documentation updated to reflect the current state of the project and deployment steps.

### Practice Common Scenarios:

- Familiarize yourself with common Kubernetes operations like scaling deployments, updating services, and rolling back changes.

### Understand Service Mesh Benefits:

- Grasp how Istio enhances security, traffic management, and observability for your microservices architecture.

### Regular Backups:
- Ensure critical data (e.g., PostgreSQL databases) is backed up regularly to prevent data loss.

### Stay Updated:

- Keep Kubernetes, Helm charts, Istio, and other dependencies up to date to benefit from the latest features and security patches.

### Use Port Forwarding Wisely:
- Limit port forwarding to essential services to reduce security risks and resource usage.

## Technology Stack Notes

### 1. Docker & Dev Containers
   Purpose:
   Provide a consistent development environment across different machines, ensuring all necessary tools and dependencies are available.

**Key Benefits**:

- Isolation: Avoids conflicts with other projects or system configurations.
- Portability: Easily shareable configurations via devcontainer.json.
- Efficiency: Leverages the host's Docker daemon to reduce resource overhead.

Code Snippets & Configurations:

Dockerfile: Defines the base image and installs necessary tools.
devcontainer.json: Configures the development container, including extensions, port forwarding, and volume mounts.
Example Usage:

bash
```

# Build and push a microservice Docker image

docker build -t yourdockerhub/user-service:latest .
docker push yourdockerhub/user-service:latest

```

## 2. Kubernetes (kubectl)

**Purpose**:
Orchestrates containerized applications, managing deployment, scaling, and operations of application containers across clusters of hosts.

### Key Components:

- Pods: Smallest deployable units containing one or more containers.
- Deployments: Manage the desired state of Pods, ensuring the specified number are running.
- Services: Expose Pods internally or externally, enabling communication.
- Ingress: Manages external access to services, typically via HTTP.

Example Configuration:

yaml
```

# Kubernetes Deployment for User Service

apiVersion: apps/v1
kind: Deployment
metadata:
name: user-service
namespace: ecommerce
spec:
replicas: 2
selector:
matchLabels:
app: user-service
template:
metadata:
labels:
app: user-service
spec:
containers: - name: user-service
image: yourdockerhub/user-service:latest
ports: - containerPort: 8000
env: - name: DB_HOST
value: "postgres-postgresql.ecommerce.svc.cluster.local" - name: DB_PASSWORD
value: "mysecretpassword"
imagePullPolicy: IfNotPresent

```

Common Commands:

kubectl apply -f <file>.yaml: Deploys resources defined in YAML.
kubectl get pods -n ecommerce: Lists all pods in the ecommerce namespace.
kubectl logs <pod-name> -n ecommerce: Retrieves logs from a specific pod. 3. Helm
Purpose:
Simplifies the deployment and management of Kubernetes applications using Helm charts, which are pre-configured Kubernetes resources.

Key Benefits:

Reusability: Helm charts can be reused across different projects.
Versioning: Manage application versions easily.
Customization: Configure applications through values files without modifying templates.
Example Commands:

bash
```

# Add a Helm repository

helm repo add bitnami https://charts.bitnami.com/bitnami

# Install PostgreSQL

helm install postgres bitnami/postgresql --namespace ecommerce --set ...

# Upgrade a release

helm upgrade postgres bitnami/postgresql --namespace ecommerce --set ...

```


Example Configuration:

bash
```

# Deploy RabbitMQ with Helm

helm install rabbitmq bitnami/rabbitmq \
 --namespace ecommerce \
 --set auth.username=guest \
 --set auth.password=guest \
 --set auth.erlangCookie=mycookie \
 --set service.type=ClusterIP 4. Istio Service Mesh

```


Purpose:
Enhances microservices architecture with features like traffic management, security (mTLS), and observability without modifying application code.

Key Benefits:

Traffic Control: Advanced routing, load balancing, and fault injection.
Security: Mutual TLS for secure service-to-service communication.
Observability: Detailed metrics, logging, and tracing of service interactions.
Installation Steps:

bash
```

# Install Istio with demo profile

istioctl install --set profile=demo -y

# Label namespace for sidecar injection

kubectl label namespace ecommerce istio-injection=enabled

```

Example Configuration:

yaml
Copy code

# Enable mTLS in Istio

apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
name: default
namespace: ecommerce
spec:
mtls:
mode: STRICT
Common Commands:

istioctl install --set profile=demo -y: Installs Istio with predefined configurations.
kubectl label namespace ecommerce istio-injection=enabled: Enables automatic sidecar injection for the namespace. 5. PostgreSQL
Purpose:
Serves as the primary relational database for storing structured data utilized by microservices.

Key Features:

ACID Compliance: Ensures reliable transactions.
Scalability: Handles large volumes of data efficiently.
Extensibility: Supports custom functions and data types.
Deployment via Helm:

bash
Copy code
helm install postgres bitnami/postgresql \
 --namespace ecommerce \
 --set global.postgresql.auth.postgresPassword=mysecretpassword \
 --set global.postgresql.auth.username=postgres \
 --set global.postgresql.auth.database=postgres \
 --set primary.persistence.enabled=true \
 --set primary.persistence.size=2Gi
Accessing PostgreSQL:

bash
Copy code

# Port forward PostgreSQL for local access

kubectl port-forward --namespace ecommerce svc/postgres-postgresql 5432:5432

# Connect using psql

psql -h localhost -U postgres -d postgres 6. RabbitMQ
Purpose:
Facilitates asynchronous messaging between microservices, enabling reliable communication and decoupling.

Key Features:

Message Queuing: Ensures messages are delivered reliably.
Publish/Subscribe Model: Supports multiple messaging patterns.
Scalability: Handles high-throughput messaging scenarios.
Deployment via Helm:

bash
Copy code
helm install rabbitmq bitnami/rabbitmq \
 --namespace ecommerce \
 --set auth.username=guest \
 --set auth.password=guest \
 --set auth.erlangCookie=mycookie \
 --set service.type=ClusterIP
Accessing RabbitMQ Management UI:

bash
Copy code

# Port forward RabbitMQ management port

kubectl port-forward --namespace ecommerce svc/rabbitmq 15672:15672

# Access via browser

http://localhost:15672

# Login Credentials:

# Username: guest

# Password: guest

7. Prometheus & Grafana
   Purpose:
   Provide monitoring and visualization of system metrics, enabling observability of microservices' performance and health.

Key Benefits:

Prometheus: Collects and stores metrics from Kubernetes, Istio, and applications.
Grafana: Visualizes metrics through customizable dashboards.
Deployment via Helm:

bash
Copy code

# Install Prometheus

helm install prometheus prometheus-community/prometheus \
 --namespace ecommerce

# Install Grafana

helm install grafana prometheus-community/grafana \
 --namespace ecommerce \
 --set adminPassword=admin \
 --set service.type=ClusterIP
Accessing Grafana:

bash
Copy code

# Port forward Grafana

kubectl port-forward --namespace ecommerce svc/grafana 3000:80

# Access via browser

http://localhost:3000

# Login Credentials:

# Username: admin

# Password: admin

Configuring Data Sources:

Add Prometheus as a Data Source:

URL: http://prometheus-server.ecommerce.svc.cluster.local:80
Import Dashboards:

Utilize pre-built dashboards for Kubernetes, Istio, Django, Rails, etc. 8. NGINX Ingress Controller
Purpose:
Manages external HTTP/S traffic, routing requests to appropriate microservices based on URL paths and hostnames.

Key Benefits:

Centralized Traffic Management: Simplifies routing rules and load balancing.
SSL/TLS Termination: Handles encryption and decryption of traffic.
Path-Based Routing: Directs traffic to specific services based on URL paths.
Deployment via Helm:

bash
Copy code
helm install nginx-ingress ingress-nginx/ingress-nginx \
 --namespace ecommerce \
 --create-namespace \
 --set controller.publishService.enabled=true
Example Ingress Resource:

yaml
Copy code

# k8s/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
name: ecommerce-ingress
namespace: ecommerce
annotations:
nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: ecommerce.local
      http:
        paths:
          - path: /user-service(/|$)(._)
pathType: Prefix
backend:
service:
name: user-service
port:
number: 8000 - path: /order-service(/|$)(._)
pathType: Prefix
backend:
service:
name: order-service
port:
number: 5000 - path: /payment-service(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
          - path: /product-service(/|$)(.\*)
pathType: Prefix
backend:
service:
name: product-service
port:
number: 3000 9. Common Bash Commands
Purpose:
Quick reference for essential bash commands used in setting up and managing the microservices platform.

Command Purpose
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 Downloads the kind binary for Kubernetes cluster setup.
chmod +x ./kind Makes the kind binary executable.
sudo mv ./kind /usr/local/bin/kind Moves kind to a directory in the PATH for easy access.
kind create cluster --name ecommerce-cluster Creates a new Kubernetes cluster named ecommerce-cluster using kind.
kubectl cluster-info --context kind-ecommerce-cluster Displays information about the Kubernetes cluster context.
kubectl config use-context kind-ecommerce-cluster Sets the current Kubernetes context to ecommerce-cluster.
helm repo add bitnami https://charts.bitnami.com/bitnami Adds the Bitnami repository to Helm for accessing PostgreSQL and RabbitMQ charts.
helm install postgres bitnami/postgresql --namespace ecommerce --set ... Deploys PostgreSQL using Helm with specified configurations.
helm install rabbitmq bitnami/rabbitmq --namespace ecommerce --set ... Deploys RabbitMQ using Helm with specified configurations.
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts Adds the Prometheus Community repository to Helm.
helm install prometheus prometheus-community/prometheus --namespace ecommerce Installs Prometheus monitoring tool via Helm.
helm install grafana prometheus-community/grafana --namespace ecommerce --set ... Installs Grafana visualization tool via Helm.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx Adds the Ingress-NGINX repository to Helm.
helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ecommerce --set ... Deploys NGINX Ingress Controller via Helm.
`curl -L https://istio.io/downloadIstio	sh -`
istioctl install --set profile=demo -y Installs Istio with the demo profile for service mesh capabilities.
kubectl label namespace ecommerce istio-injection=enabled Enables automatic Istio sidecar injection for the ecommerce namespace.
kubectl apply -f k8s/<file>.yaml Applies Kubernetes configurations (Deployments, Services, Ingress, etc.).
docker build -t yourdockerhub/<service>:latest . Builds a Docker image for a microservice.
docker push yourdockerhub/<service>:latest Pushes the Docker image to Docker Hub.
kubectl set image deployment/<service> <service>=yourdockerhub/<service>:latest -n ecommerce Updates the Kubernetes deployment with the latest Docker image.
kubectl rollout status deployment/<service> -n ecommerce Monitors the rollout status of a deployment.
kubectl port-forward --namespace ecommerce svc/<service> <local>:<remote> Forwards a port from a Kubernetes service to the local machine for access.
kubectl get pods -n ecommerce Lists all pods in the ecommerce namespace.
kubectl describe pod <pod-name> -n ecommerce Provides detailed information about a specific pod.
kubectl logs <pod-name> -n ecommerce Retrieves logs from a specific pod.
`curl -fsSL https://deb.nodesource.com/setup_20.x	bash -`
apt-get install -y nodejs Installs Node.js.
gem install bundler Installs Bundler for Ruby dependency management.
cargo build --release Builds the Rust project in release mode.
npm install -g vite Installs Vite globally for frontend tooling.
Technology Stack Notes

1. Docker & Dev Containers
   Purpose:
   Provide a consistent development environment across different machines, ensuring all necessary tools and dependencies are available.

Key Benefits:

Isolation: Avoids conflicts with other projects or system configurations.
Portability: Easily shareable configurations via devcontainer.json.
Efficiency: Leverages the host's Docker daemon to reduce resource overhead.
Code Snippets & Configurations:

Dockerfile: Defines the base image and installs necessary tools.
devcontainer.json: Configures the development container, including extensions, port forwarding, and volume mounts.
Example Usage:

bash
Copy code

# Build and push a microservice Docker image

docker build -t yourdockerhub/user-service:latest .
docker push yourdockerhub/user-service:latest
Installation & Configuration:

Dockerfile: Ensures all required languages and tools are installed within the container.
devcontainer.json: Sets up the development environment with necessary extensions and mounts Docker socket for Docker-in-Docker capabilities.
Code Snippets:

dockerfile
Copy code

# Install Docker CLI

RUN apt-get update && apt-get install -y docker.io
json
Copy code
"mounts": [
"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
"source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached"
], 2. Kubernetes (kubectl)
Purpose:
Orchestrates containerized applications, managing deployment, scaling, and operations of application containers across clusters of hosts.

Key Components:

Pods: Smallest deployable units containing one or more containers.
Deployments: Manage the desired state of Pods, ensuring the specified number are running.
Services: Expose Pods internally or externally, enabling communication.
Ingress: Manages external access to services, typically via HTTP.
Example Configuration:

yaml
Copy code

# Kubernetes Deployment for User Service

apiVersion: apps/v1
kind: Deployment
metadata:
name: user-service
namespace: ecommerce
spec:
replicas: 2
selector:
matchLabels:
app: user-service
template:
metadata:
labels:
app: user-service
spec:
containers: - name: user-service
image: yourdockerhub/user-service:latest
ports: - containerPort: 8000
env: - name: DB_HOST
value: "postgres-postgresql.ecommerce.svc.cluster.local" - name: DB_PASSWORD
value: "mysecretpassword"
imagePullPolicy: IfNotPresent
Common Commands:

kubectl apply -f <file>.yaml: Deploys resources defined in YAML.
kubectl get pods -n ecommerce: Lists all pods in the ecommerce namespace.
kubectl logs <pod-name> -n ecommerce: Retrieves logs from a specific pod. 3. Helm
Purpose:
Simplifies the deployment and management of Kubernetes applications using Helm charts, which are pre-configured Kubernetes resources.

Key Benefits:

Reusability: Helm charts can be reused across different projects.
Versioning: Manage application versions easily.
Customization: Configure applications through values files without modifying templates.
Example Commands:

bash
Copy code

# Add a Helm repository

helm repo add bitnami https://charts.bitnami.com/bitnami

# Install PostgreSQL

helm install postgres bitnami/postgresql --namespace ecommerce --set ...

# Upgrade a release

helm upgrade postgres bitnami/postgresql --namespace ecommerce --set ...
Example Configuration:

bash
Copy code

# Deploy RabbitMQ with Helm

helm install rabbitmq bitnami/rabbitmq \
 --namespace ecommerce \
 --set auth.username=guest \
 --set auth.password=guest \
 --set auth.erlangCookie=mycookie \
 --set service.type=ClusterIP
Best Practices:

Use Values Files: Manage configurations through values.yaml for better maintainability.
Version Control: Keep Helm chart configurations under version control.
Namespace Management: Deploy related applications within the same Kubernetes namespace. 4. Istio Service Mesh
Purpose:
Enhances microservices architecture with features like traffic management, security (mTLS), and observability without modifying application code.

Key Benefits:

Traffic Control: Advanced routing, load balancing, and fault injection.
Security: Mutual TLS for secure service-to-service communication.
Observability: Detailed metrics, logging, and tracing of service interactions.
Installation Steps:

bash
Copy code

# Install Istio with demo profile

istioctl install --set profile=demo -y

# Label namespace for sidecar injection

kubectl label namespace ecommerce istio-injection=enabled
Example Configuration:

yaml
Copy code

# Enable mTLS in Istio

apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
name: default
namespace: ecommerce
spec:
mtls:
mode: STRICT
Common Commands:

istioctl install --set profile=demo -y: Installs Istio with predefined configurations.
kubectl label namespace ecommerce istio-injection=enabled: Enables automatic sidecar injection for the namespace.
Benefits in System Architecture:

Decoupled Concerns: Separates operational concerns from application code.
Enhanced Security: Enforces secure communication between services.
Traffic Management: Enables sophisticated routing strategies and resilience patterns. 5. PostgreSQL
Purpose:
Serves as the primary relational database for storing structured data utilized by microservices.

Key Features:

ACID Compliance: Ensures reliable transactions.
Scalability: Handles large volumes of data efficiently.
Extensibility: Supports custom functions and data types.
Deployment via Helm:

bash
Copy code
helm install postgres bitnami/postgresql \
 --namespace ecommerce \
 --set global.postgresql.auth.postgresPassword=mysecretpassword \
 --set global.postgresql.auth.username=postgres \
 --set global.postgresql.auth.database=postgres \
 --set primary.persistence.enabled=true \
 --set primary.persistence.size=2Gi
Accessing PostgreSQL:

bash
Copy code

# Port forward PostgreSQL for local access

kubectl port-forward --namespace ecommerce svc/postgres-postgresql 5432:5432

# Connect using psql

psql -h localhost -U postgres -d postgres
Example Usage in Microservices:

yaml
Copy code

# Environment Variables in Deployment

env:

- name: DB_HOST
  value: "postgres-postgresql.ecommerce.svc.cluster.local"
- name: DB_NAME
  value: "postgres"
- name: DB_USER
  value: "postgres"
- name: DB_PASSWORD
  value: "mysecretpassword"
- name: DB_PORT
  value: "5432"

6. RabbitMQ
   Purpose:
   Facilitates asynchronous messaging between microservices, enabling reliable communication and decoupling.

Key Features:

Message Queuing: Ensures messages are delivered reliably.
Publish/Subscribe Model: Supports multiple messaging patterns.
Scalability: Handles high-throughput messaging scenarios.
Deployment via Helm:

bash
Copy code
helm install rabbitmq bitnami/rabbitmq \
 --namespace ecommerce \
 --set auth.username=guest \
 --set auth.password=guest \
 --set auth.erlangCookie=mycookie \
 --set service.type=ClusterIP
Accessing RabbitMQ Management UI:

bash
Copy code

# Port forward RabbitMQ management port

kubectl port-forward --namespace ecommerce svc/rabbitmq 15672:15672

# Access via browser

http://localhost:15672

# Login Credentials:

# Username: guest

# Password: guest

Example Usage in Microservices:

yaml
Copy code

# Environment Variables in Deployment

env:

- name: RABBITMQ_HOST
  value: "rabbitmq.ecommerce.svc.cluster.local"
- name: RABBITMQ_USER
  value: "guest"
- name: RABBITMQ_PASSWORD
  value: "guest"
  Benefits in System Architecture:

Decoupling Services: Microservices communicate through RabbitMQ without direct dependencies.
Asynchronous Processing: Enables handling tasks that don't require immediate processing.
Reliability: Ensures message delivery even if some services are temporarily unavailable. 7. Prometheus & Grafana
Purpose:
Provide monitoring and visualization of system metrics, enabling observability of microservices' performance and health.

Key Benefits:

Prometheus: Collects and stores metrics from Kubernetes, Istio, and applications.
Grafana: Visualizes metrics through customizable dashboards.
Deployment via Helm:

bash
Copy code

# Install Prometheus

helm install prometheus prometheus-community/prometheus \
 --namespace ecommerce

# Install Grafana

helm install grafana prometheus-community/grafana \
 --namespace ecommerce \
 --set adminPassword=admin \
 --set service.type=ClusterIP
Accessing Grafana:

bash
Copy code

# Port forward Grafana

kubectl port-forward --namespace ecommerce svc/grafana 3000:80

# Access via browser

http://localhost:3000

# Login Credentials:

# Username: admin

# Password: admin

Configuring Data Sources:

Add Prometheus as Data Source:

URL: http://prometheus-server.ecommerce.svc.cluster.local:80
Import Dashboards:

Utilize pre-built dashboards for Kubernetes, Istio, Django, Rails, etc.
Benefits in System Architecture:

Observability: Gain insights into system performance and identify bottlenecks.
Alerting: Set up alerts based on specific metrics to proactively manage issues.
Performance Tuning: Use metrics to optimize resource allocation and service performance.

### 8. NGINX Ingress Controller

**Purpose**:
Manages external HTTP/S traffic, routing requests to appropriate microservices based on URL paths and hostnames.

**Key Benefits**:

- Centralized Traffic Management: Simplifies routing rules and load balancing.
- SSL/TLS Termination: Handles encryption and decryption of traffic.
- Path-Based Routing: Directs traffic to specific services based on URL paths.

Deployment via Helm:

bash

```

helm install nginx-ingress ingress-nginx/ingress-nginx \
 --namespace ecommerce \
 --create-namespace \
 --set controller.publishService.enabled=true

```

Example Ingress Resource:

yaml

```

# k8s/ingress.yaml

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
name: ecommerce-ingress
namespace: ecommerce
annotations:
nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: ecommerce.local
      http:
        paths:
          - path: /user-service(/|$)(._)
pathType: Prefix
backend:
service:
name: user-service
port:
number: 8000 - path: /order-service(/|$)(._)
pathType: Prefix
backend:
service:
name: order-service
port:
number: 5000 - path: /payment-service(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: payment-service
                port:
                  number: 8080
          - path: /product-service(/|$)(.\*)
pathType: Prefix
backend:
service:
name: product-service
port:
number: 3000

```

### Benefits in System Architecture:

Simplified Routing: Easily manage complex routing rules without modifying application code.
Load Balancing: Distribute traffic evenly across multiple instances of microservices.
Security: Implement SSL/TLS for secure communication between clients and services.

## Final Notes - Preparing for the Interview:

### Understand Each Component:

- Know the purpose, benefits, and configurations of Docker, Kubernetes, Helm, Istio, PostgreSQL, RabbitMQ, Prometheus, Grafana, and NGINX Ingress.

### Review Deployment Steps:

- Be comfortable explaining how each microservice is containerized, deployed, and integrated within the Kubernetes cluster.

### Explain Integration Rationale:

- Understand why specific technologies were chosen (e.g., Istio for service mesh, Helm for package management).

### Demonstrate Troubleshooting Skills:

- Be prepared to discuss how to troubleshoot common issues (e.g., pod failures, connectivity issues).

### Highlight Best Practices:

- Emphasize the use of namespaces, secure configurations, monitoring, and scalability considerations.

### Prepare Code Snippets:

- Be ready to walk through example YAML configurations, Dockerfiles, and Helm commands.

### Know Common Commands:

- Familiarize yourself with essential kubectl, helm, and Docker commands used in the setup.
```
