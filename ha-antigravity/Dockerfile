# Both base images are named by digest and the Antigravity CLI archive by
# version, URL and SHA-512 checksum, so the same Dockerfile builds the same
# image on any day. The weekly workflow moves them together.
FROM node:22-bookworm-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d AS node

FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=unknown
ARG AGY_VERSION=1.5.14
ARG AGY_URL_ARM64=https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.14-5302690847260672/linux-arm/cli_linux_arm64.tar.gz
ARG AGY_SHA512_ARM64=c9b29bba475f63a1a80161ae93ba72b221c7a586d9851e4d0061546704bab66d6b2760b25d716d191724fc7564f3246456ee151e28aa37af48dbcd72bdc6c463
ARG AGY_URL_AMD64=https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.14-5302690847260672/linux-x64/cli_linux_x64.tar.gz
ARG AGY_SHA512_AMD64=83311d3f354567612dc16c1ae2ea9b503d6f6833aa4e138d39aa229da3f3bb99b0e4d7cca0bce4796b0060d6a51d8113eb7449ed5dc0e7900bf217107ea5bff9
ARG PLAYWRIGHT_MCP_VERSION=0.0.84

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 AGY_CLI_DISABLE_AUTO_UPDATE=true

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq mosquitto-clients nginx-light openssh-client poppler-utils procps tmux ttyd tzdata util-linux \
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
 && ttyd --version \
 && command -v pdftoppm

RUN case "$(uname -m)" in \
      aarch64|arm64) url="${AGY_URL_ARM64}"; sha="${AGY_SHA512_ARM64}" ;; \
      x86_64|amd64)  url="${AGY_URL_AMD64}"; sha="${AGY_SHA512_AMD64}" ;; \
      *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/agy.tar.gz "$url" \
 && printf '%s  /tmp/agy.tar.gz\n' "$sha" | sha512sum -c - \
 && tar -xzf /tmp/agy.tar.gz -C /tmp antigravity \
 && install -m 0755 -o root -g root /tmp/antigravity /usr/local/bin/agy \
 && rm -f /tmp/agy.tar.gz /tmp/antigravity \
 && agy --version | grep -F "${AGY_VERSION}"

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# The browser: Playwright MCP, pinned, and the headless Chromium its own
# Playwright names, with the libraries it needs, in a folder root owns and
# every user can read and no one but root can write.
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/share/ha-antigravity/browsers
RUN npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
 && apt-get update \
 && playwright-mcp install-browser --with-deps --only-shell chromium \
 && shell="$(find "$PLAYWRIGHT_BROWSERS_PATH" -path '*chromium_headless_shell-*' -type f -name chrome-headless-shell | head -n 1)" \
 && [ -x "$shell" ] && ln -s "$shell" "$PLAYWRIGHT_BROWSERS_PATH/chrome-headless-shell" \
 && rm -rf /var/lib/apt/lists/* \
 && npm cache clean --force \
 && chown -R root:root "$PLAYWRIGHT_BROWSERS_PATH" /usr/local/lib/node_modules/@playwright \
 && chmod -R a+rX,go-w "$PLAYWRIGHT_BROWSERS_PATH" /usr/local/lib/node_modules/@playwright \
 && playwright-mcp --version | grep -F "${PLAYWRIGHT_MCP_VERSION}"

RUN useradd --no-create-home --home-dir /data/home --shell /bin/bash --uid 1500 antigravity

COPY rootfs/ /
COPY schemas/ /usr/share/ha-antigravity/schemas/

LABEL io.hass.version="${BUILD_VERSION}" io.hass.type="app" io.hass.arch="${BUILD_ARCH}"

CMD ["/usr/local/bin/addon-run"]
