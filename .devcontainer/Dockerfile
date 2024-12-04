# .devcontainer/Dockerfile

FROM mcr.microsoft.com/devcontainers/base:bookworm

# Update image
RUN apt-get update && apt-get install -y build-essential libssl-dev pkg-config


# Install Docker CLI
RUN apt-get update && apt-get install -y \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Set Docker binary path
ENV PATH="/usr/bin/docker:${PATH}"

# Install Node.js >= 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install Python >= 3.11
RUN apt-get update && apt-get install -y python3.11 python3.11-dev python3-pip python3-venv
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# Install Ruby and Bundler
RUN apt-get install -y ruby-full
RUN gem install bundler

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install PostgreSQL client (psql)
RUN apt-get install -y postgresql-client

# Install additional tools
RUN apt-get install -y git curl

# Install Vite globally
RUN npm install -g vite

# Install Rust with rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Rust tooling.
RUN cargo install cargo-edit # For managing dependencies in Cargo.toml
RUN cargo install cargo-watch # For watching and rebuilding code on changes

# Install rust-analyzer
RUN rustup component add rust-analyzer

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
