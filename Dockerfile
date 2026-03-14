FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# Core packages
RUN apt-get update && apt-get install -y \
    tmux zsh git curl wget locales lsof procps fzf \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user with zsh
RUN useradd -m -s /bin/zsh dev
USER dev
WORKDIR /home/dev

# TPM (tmux plugin manager)
RUN mkdir -p ~/.tmux/plugins \
    && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Oh my zsh (unattended)
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab

# Copy dotfiles
COPY --chown=dev:dev dotfiles/tmux.conf /home/dev/.tmux.conf
COPY --chown=dev:dev dotfiles/tmux/base.conf /home/dev/.tmux/base.conf
COPY --chown=dev:dev dotfiles/tmux/keys-gmux.conf /home/dev/.tmux/keys-gmux.conf
COPY --chown=dev:dev dotfiles/tmux/keys-vanilla.conf /home/dev/.tmux/keys-vanilla.conf
COPY --chown=dev:dev dotfiles/tmux/entrypoint.sh /home/dev/.tmux/entrypoint.sh
COPY --chown=dev:dev dotfiles/zshrc /home/dev/.zshrc
COPY --chown=dev:dev dotfiles/tmux/scripts/ /home/dev/.tmux/scripts/
COPY --chown=dev:dev dotfiles/config/zsh/ /home/dev/.config/zsh/

# Make scripts executable + install tmux plugins
RUN chmod +x ~/.tmux/scripts/*.sh ~/.tmux/entrypoint.sh \
    && ~/.tmux/plugins/tpm/bin/install_plugins

ENTRYPOINT ["/home/dev/.tmux/entrypoint.sh"]
