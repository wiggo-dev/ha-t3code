ARG BUILD_VERSION=dev
ARG BUILD_ARCH
ARG T3_VERSION=0.0.33

FROM ghcr.io/home-assistant/base:latest

ARG BUILD_VERSION
ARG BUILD_ARCH
ARG T3_VERSION

LABEL \
  io.hass.version="${BUILD_VERSION}" \
  io.hass.type="app" \
  io.hass.arch="aarch64|amd64"

RUN set -x \
  && apk add --no-cache \
    nodejs \
    npm \
    python3 \
    make \
    g++ \
    linux-headers \
  && node --version \
  && npm --version \
  && npm install -g "t3@${T3_VERSION}" \
  && t3 --version \
  && rm -rf /root/.npm /tmp/*

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
