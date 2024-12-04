FROM mcr.microsoft.com/devcontainers/base:bookworm

# Use bash
SHELL ["/bin/bash", "-c"]

# Install prerequisites
RUN apt-get update && apt-get install -y \
    build-essential libssl-dev pkg-config \
    python3.11 python3.11-dev python3-pip python3-venv \
    ruby-full postgresql-client git curl docker.io zsh \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js >= 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Ruby Bundler
RUN gem install bundler

# Switch to vscode user for installing rust & related tools
USER vscode
ENV HOME="/home/vscode"
WORKDIR /home/vscode

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
    && . "$HOME/.cargo/env" \
    && rustup default stable \
    && rustup update stable \
    && rustup component add rustfmt clippy rust-analyzer \
    && cargo install cargo-edit cargo-watch

# Set ENV so cargo, rustc are always on PATH
ENV PATH="$HOME/.cargo/bin:${PATH}"

# Ensure PATH is loaded in interactive shells
RUN echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc \
    && echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc

USER root
# Install Vite globally as root
RUN npm install -g vite

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to vscode
USER vscode

# Verify versions
RUN rustc --version && cargo --version && vite --version
