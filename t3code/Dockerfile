ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:trixie
ARG BUILD_VERSION=dev
ARG BUILD_ARCH
ARG T3_VERSION=0.0.33

FROM ${BUILD_FROM}

ARG BUILD_VERSION
ARG BUILD_ARCH
ARG T3_VERSION

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="aarch64|amd64"

# Node 22+ for T3 (engines: ^22.16 || ^23.11 || >=24.10); build tools for native npm deps.
RUN set -x \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    xz-utils \
    bash \
    jq \
    python3 \
    make \
    g++ \
  && NODE_ARCH="$(dpkg --print-architecture)" \
  && case "${NODE_ARCH}" in \
       amd64) NODE_ARCH=x64 ;; \
       arm64) NODE_ARCH=arm64 ;; \
       *) echo "unsupported arch: ${NODE_ARCH}" >&2; exit 1 ;; \
     esac \
  && NODE_VERSION=22.23.2 \
  && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1 \
  && YQ_ARCH="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_${YQ_ARCH}" \
    -o /usr/local/bin/yq \
  && chmod +x /usr/local/bin/yq \
  && node --version \
  && npm --version \
  && npm install -g "t3@${T3_VERSION}" \
  && t3 --version \
  && curl https://cursor.com/install -fsS | bash \
  && ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent \
  && ln -sf /root/.local/bin/agent /usr/local/bin/agent \
  && cursor-agent --version \
  && rm -rf /var/lib/apt/lists/* /root/.npm /tmp/*

ENV PATH="/root/.local/bin:${PATH}"

COPY skills /opt/ha-t3code/skills
COPY deploy-skills.py run.sh /
RUN chmod a+x /run.sh /deploy-skills.py

CMD [ "/run.sh" ]
