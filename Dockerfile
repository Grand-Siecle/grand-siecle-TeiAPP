# ============================================================
# Multi-stage Dockerfile for Grand Siècle (TEI Publisher)
#
# Two terminal targets, selected via `--target`:
#
#   docker buildx build --target dev  -t gdsiecle:dev  .
#       BUILD: in-container (clone deps + ant)
#       CACHE: HTTP proxy-cache OFF — modifs ODD/XQuery visibles
#              immédiatement sans Ctrl+Shift+R navigateur.
#       BASE:  duncdrum/existdb (root user, no auto-build assumed)
#
#   ant && docker buildx build --target prod -t gdsiecle:prod .
#       BUILD: requires ./build/*.xar produced by `ant` first
#       CACHE: HTTP proxy-cache ON — réponses 304 Not Modified
#              pour navigation rapide.
#       BASE:  ghcr.io/jinntec/base (nonroot, slim)
#
# Default (no --target) → builds the LAST stage in this file = prod.
# ============================================================

ARG EXIST_VERSION=6.4.0
ARG ROUTER_VERSION=1.11.0
ARG JWT_VERSION=2.0.1
ARG CRYPTO_VERSION=6.0.1

# ── Stage 1 — builder (shared by dev only) ───────────────────
FROM ghcr.io/eeditiones/builder:latest AS builder

ARG ROUTER_VERSION
ARG JWT_VERSION
ARG CRYPTO_VERSION

WORKDIR /tmp

RUN git clone https://github.com/eeditiones/jinks-templates.git \
    && cd jinks-templates \
    && ant

RUN git clone https://github.com/eeditiones/tei-publisher-lib.git \
    && cd tei-publisher-lib \
    && ant

COPY . GdSiecle/
RUN cd GdSiecle && ant

ADD http://exist-db.org/exist/apps/public-repo/public/roaster-${ROUTER_VERSION}.xar 001.xar
ADD http://exist-db.org/exist/apps/public-repo/public/jwt-${JWT_VERSION}.xar 002.xar
ADD https://exist-db.org/exist/apps/public-repo/public/expath-crypto-module-${CRYPTO_VERSION}.xar 003.xar

# ── Stage 2 — dev target ─────────────────────────────────────
FROM duncdrum/existdb:${EXIST_VERSION} AS dev

USER root
WORKDIR /exist

COPY --from=builder /tmp/*.xar /exist/autodeploy/
COPY --from=builder /tmp/jinks-templates/build/*.xar /exist/autodeploy/004.xar
COPY --from=builder /tmp/tei-publisher-lib/build/*.xar /exist/autodeploy/005.xar
COPY --from=builder /tmp/GdSiecle/build/*.xar /exist/autodeploy/006.xar

ARG NER_ENDPOINT=http://localhost:8001
ARG CONTEXT_PATH=auto
ENV JDK_JAVA_OPTIONS="\
    -Dteipublisher.ner-endpoint=${NER_ENDPOINT} \
    -Dteipublisher.context-path=${CONTEXT_PATH} \
    -Dteipublisher.proxy-caching=false"

RUN [ "java", "org.exist.start.Main", "client", "--no-gui", "-l", "-u", "admin", "-P", "" ]

EXPOSE 8080 8443

# ── Stage 3 — prod target (default if no --target) ───────────
FROM ghcr.io/jinntec/base:main AS prod

ARG PUBLISHER_VERSION
USER nonroot
WORKDIR /exist

ADD --chown=nonroot https://github.com/eeditiones/jinks-templates/releases/latest/download/jinks-templates.xar /exist/autodeploy/004.xar
ADD --chown=nonroot https://github.com/eeditiones/tei-publisher-libs/releases/latest/download/tei-publisher-lib.xar /exist/autodeploy/005.xar

# Requires `ant` to have produced ./build/*.xar before docker build
COPY --chown=nonroot ./build/*.xar /exist/autodeploy/

ARG NER_ENDPOINT=http://localhost:8001
ARG CONTEXT_PATH=auto
ENV JDK_JAVA_OPTIONS="\
    -Dteipublisher.ner-endpoint=${NER_ENDPOINT} \
    -Dteipublisher.context-path=${CONTEXT_PATH} \
    -Dteipublisher.proxy-caching=true"

RUN [ "java", "org.exist.start.Main", "client", "--no-gui", "-l", "-u", "admin", "-P", "" ]

EXPOSE 8080 8443
