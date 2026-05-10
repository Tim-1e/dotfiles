FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates curl git \
  && rm -rf /var/lib/apt/lists/*

COPY . /opt/dotfiles
WORKDIR /opt/dotfiles

RUN chmod +x ./bootstrap.sh ./scripts/install.sh ./test/smoke.sh ./run_once_before_00-install-env.sh.tmpl \
  && bash ./bootstrap.sh

ENV SHELL=/bin/zsh \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

WORKDIR /workspace
CMD ["zsh"]
