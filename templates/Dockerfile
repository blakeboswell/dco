FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  tmux \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
ARG CLAUDE_THEME=dark-daltonized
RUN mkdir -p /workspace /home/node/.claude && \
  echo "{\"theme\": \"$CLAUDE_THEME\"}" > /home/node/.claude/settings.json && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/home/node/.local/bin:$PATH:/usr/local/share/npm-global/bin

# Install uv (runs as node user so it lands in /home/node/.local/bin)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
# Retry with a timeout: the installer clones oh-my-zsh from GitHub and
# occasionally hangs on flaky networks with no timeout of its own.
RUN success=false; \
  for i in 1 2 3; do \
    echo "Installing oh-my-zsh + plugins (attempt $i/3)..."; \
    if timeout 180 sh -c "$(wget --timeout=30 --tries=3 -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
      -p git \
      -p fzf \
      -p zsh-autosuggestions \
      -p zsh-syntax-highlighting \
      -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
      -a "source /usr/share/doc/fzf/examples/completion.zsh" \
      -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
      -a "typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet" \
      -x; then \
      success=true; break; \
    fi; \
    echo "attempt $i failed or timed out; cleaning up and retrying..."; \
    rm -rf "$HOME/.oh-my-zsh"; \
    sleep 5; \
  done; \
  $success

# Install oh-my-zsh community plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
COPY allowlist.txt /usr/local/etc/dco-allowlist.txt
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
