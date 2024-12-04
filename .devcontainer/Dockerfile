# .devcontainer/Dockerfile

FROM mcr.microsoft.com/devcontainers/base:bookworm

# Update image and install essential dependencies
RUN apt-get update && apt-get install -y \
    build-essential libssl-dev pkg-config \
    python3.11 python3.11-dev python3-pip python3-venv \
    ruby-full postgresql-client git curl docker.io \
    && rm -rf /var/lib/apt/lists/*

# Set Docker binary path
ENV PATH="/usr/bin/docker:${PATH}"

# Install Node.js >= 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Install Ruby and Bundler
RUN gem install bundler

# Install Rust and related tools for the non-root user
USER vscode

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc \
    && . ~/.bashrc \
    && rustup update stable \
    && rustup component add rustfmt clippy rust-analyzer \
    && cargo install cargo-edit cargo-watch

# Add Rust binaries to the PATH
ENV PATH="/home/vscode/.cargo/bin:${PATH}"

# Install Vite globally
RUN npm install -g vite

# Switch back to root to perform cleanup
USER root

# Clean up unnecessary files to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Final verification step for Rust and Vite (optional)
RUN rustc --version && cargo --version && vite --version
