# Ansible runner for the local platform (o2c-app ADR-018), built and started by
# scripts/ansible.sh with the Docker socket mounted: the playbooks drive the host's Docker
# (community.docker) and kind. Pinned: base image by digest, Python packages and the
# collection by version, the docker CLI, buildx and kind by version and SHA-256.
FROM python:3.12-slim-bookworm@sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70

COPY --from=ghcr.io/astral-sh/uv:0.13.1@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 /uv /usr/local/bin/uv

# docker CLI with buildx (community.docker.docker_image_build) and kind (kubeconfig)
ARG DOCKER_VERSION=29.8.0
ARG DOCKER_SHA256=cc21815cf1e2efed867dc9c8b96b46ffed8ea176ffab32b0aacb54726ded8f25
ARG BUILDX_VERSION=v0.38.0
ARG BUILDX_SHA256=4fe4cc38adf48169132749b6ca22a990928db0118e3407584ee553723115d287
ARG KIND_VERSION=v0.33.0
ARG KIND_SHA256=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN [ "$(dpkg --print-architecture)" = amd64 ] || { echo "amd64 only (pinned checksums)" >&2; exit 1; } \
  && apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*
RUN set -eux; cd /tmp; \
  fetch() { curl -fsSL --retry 3 -o "$2" "$1"; echo "$3  $2" | sha256sum -c -; }; \
  fetch "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" docker.tgz "$DOCKER_SHA256"; \
  tar -xzf docker.tgz --strip-components=1 -C /usr/local/bin docker/docker; \
  fetch "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" buildx "$BUILDX_SHA256"; \
  install -D -m 0755 buildx /usr/local/lib/docker/cli-plugins/docker-buildx; \
  fetch "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" kind "$KIND_SHA256"; \
  install -m 0755 kind /usr/local/bin/kind; \
  rm -f /tmp/docker.tgz /tmp/buildx /tmp/kind

COPY requirements.txt requirements.yml /tmp/ansible/
RUN uv pip install --system --no-cache -r /tmp/ansible/requirements.txt \
  && ansible-galaxy collection install -r /tmp/ansible/requirements.yml \
    -p /usr/share/ansible/collections

WORKDIR /work
