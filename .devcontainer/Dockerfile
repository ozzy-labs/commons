FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# Install as vscode user
USER vscode

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install mise
RUN curl --proto '=https' --tlsv1.2 -fsSL https://mise.run | sh

# Install oh-my-zsh plugins (static layer — placed before mise install for better caching)
RUN git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
        ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && sed -i 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc

# Install tools defined in .mise.toml (cached in image layer)
# GITHUB_TOKEN avoids GitHub API rate limits for aqua backend downloads
ARG GITHUB_TOKEN
COPY --chown=vscode:vscode .mise.toml /home/vscode/.mise.toml
RUN ~/.local/bin/mise trust /home/vscode/.mise.toml \
    && ~/.local/bin/mise install \
    && rm /home/vscode/.mise.toml

# Switch back to root for remaining setup
USER root
RUN chsh -s /bin/zsh vscode \
    && echo 'eval "$(/home/vscode/.local/bin/mise activate bash)"' >> /etc/bash.bashrc \
    && echo 'eval "$(/home/vscode/.local/bin/mise activate zsh)"' >> /etc/zsh/zshrc \
    && echo 'export HISTFILE="$HOME/.zsh_history"' >> /etc/zsh/zshrc \
    && echo 'export HISTSIZE=10000' >> /etc/zsh/zshrc \
    && echo 'export SAVEHIST=10000' >> /etc/zsh/zshrc \
    && echo '# Write history in-place; the default copy-and-rename fails on bind-mounted files' >> /etc/zsh/zshrc \
    && echo 'unsetopt HIST_SAVE_BY_COPY' >> /etc/zsh/zshrc
