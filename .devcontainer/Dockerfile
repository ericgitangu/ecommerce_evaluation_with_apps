FROM mcr.microsoft.com/devcontainers/base:bookworm

# Use bash
SHELL ["/bin/bash", "-c"]

# Install system-wide prerequisites (excluding docker.io)
RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    pkg-config \
    python3.11 \
    python3.11-dev \
    python3-pip \
    python3-venv \
    ruby-full \
    postgresql-client \
    git \
    curl \
    zsh \
    && rm -rf /var/lib/apt/lists/*

# Set up environment variables for the vscode user
ENV HOME="/home/vscode"
ENV PATH="$HOME/.cargo/bin:${PATH}"

# Install Rust & related tools as vscode user
USER vscode
WORKDIR /home/vscode

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && source "$HOME/.cargo/env" \
    && rustup default stable \
    && rustup update stable \
    && rustup component add rustfmt clippy rust-analyzer \
    && cargo install cargo-edit cargo-watch

# Ensure PATH is loaded in interactive shells
RUN echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc \
    && echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc

# Switch back to root user
USER root

# Install Node.js >= 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Ruby Bundler
RUN gem install bundler

# Install kubectl (version v1.27.3 to match Kind node image)
RUN curl -LO "https://dl.k8s.io/release/v1.27.3/bin/linux/amd64/kubectl" \
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

# Install Vite globally
RUN npm install -g vite

# Clean up to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to vscode user
USER vscode

# Verify installations
RUN rustc --version && cargo --version && vite --version \
    && kubectl version --client && kind version && istioctl version