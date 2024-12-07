FROM mcr.microsoft.com/devcontainers/base:bookworm

# Use bash
SHELL ["/bin/bash", "-c"]

# Install system-wide prerequisites (excluding docker.io)
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    pkg-config \
    postgresql-client \
    git \
    curl \
    zsh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl

# Install Kind
RUN curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Istio CLI
RUN curl -L https://istio.io/downloadIstioctl | sh - \
    && mv "$HOME/.istioctl/bin/istioctl" /usr/local/bin/istioctl \
    && chmod +x /usr/local/bin/istioctl

# Switch back to vscode user
USER vscode

# Verify installations
RUN kubectl version --client && kind version && istioctl version