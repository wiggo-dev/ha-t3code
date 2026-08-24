ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:trixie
ARG BUILD_VERSION=dev
ARG BUILD_ARCH
ARG T3_VERSION=0.0.33
ARG CURSOR_VERSION=2026.08.11-e8db854
ARG CURSOR_SHA256_LINUX_X64=bfff4bf6f4e9dd30c1d0ef0a70b6077b074015dd2948e4c50685d53afdcfce5a
ARG CURSOR_SHA256_LINUX_ARM64=ea13f92e295f523a99ce8d8f57d6894d21e5d1e2d030ffad718ccd5955ca2eed

FROM ${BUILD_FROM}

ARG BUILD_VERSION
ARG BUILD_ARCH
ARG T3_VERSION
ARG CURSOR_VERSION
ARG CURSOR_SHA256_LINUX_X64
ARG CURSOR_SHA256_LINUX_ARM64

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="aarch64|amd64"

# Node 22+ for T3 (engines: ^22.16 || ^23.11 || >=24.10); build tools for native npm deps.
# Cursor CLI is pinned by lab tarball URL + checksum (ADR-0007); not via cursor.com/install.
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
  && CURSOR_ARCH="$(dpkg --print-architecture)" \
  && case "${CURSOR_ARCH}" in \
       amd64) CURSOR_ARCH=x64; CURSOR_SHA256="${CURSOR_SHA256_LINUX_X64}" ;; \
       arm64) CURSOR_ARCH=arm64; CURSOR_SHA256="${CURSOR_SHA256_LINUX_ARM64}" ;; \
       *) echo "unsupported arch for Cursor CLI: ${CURSOR_ARCH}" >&2; exit 1 ;; \
     esac \
  && CURSOR_DIR="/root/.local/share/cursor-agent/versions/${CURSOR_VERSION}" \
  && mkdir -p "${CURSOR_DIR}" \
  && curl -fsSL "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/${CURSOR_ARCH}/agent-cli-package.tar.gz" \
    -o /tmp/cursor-agent.tar.gz \
  && echo "${CURSOR_SHA256}  /tmp/cursor-agent.tar.gz" | sha256sum -c - \
  && tar --strip-components=1 -xzf /tmp/cursor-agent.tar.gz -C "${CURSOR_DIR}" \
  && chmod +x "${CURSOR_DIR}/cursor-agent" \
  && rm -f /tmp/cursor-agent.tar.gz \
  && rm -rf /var/lib/apt/lists/* /root/.npm /tmp/*

ENV CURSOR_VERSION="${CURSOR_VERSION}"
ENV CURSOR_AGENT_BIN="/root/.local/share/cursor-agent/versions/${CURSOR_VERSION}/cursor-agent"

COPY cursor-agent-wrapper.sh /usr/local/bin/cursor-agent
COPY skills /opt/ha-t3code/skills
COPY deploy-skills.py run.sh /
RUN chmod a+x /run.sh /deploy-skills.py /usr/local/bin/cursor-agent \
  && ln -sfn cursor-agent /usr/local/bin/agent \
  && cursor-agent --version

CMD [ "/run.sh" ]
