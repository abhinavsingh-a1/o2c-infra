# Jenkins for the O2C promotion pipelines (o2c-app ADR-018), built by the Ansible role
# "jenkins". Pinned: the LTS base image by digest, every plugin by version (plugins.txt,
# dependencies included) and every tool by version and SHA-256.
FROM jenkins/jenkins:2.580.1-lts-jdk21@sha256:a660310e39ade10631f774bacd5219de767dfd08947ea5c32a739b5e5bb382c1

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# kubectl within one minor version of the kind cluster (v1.35); argocd and cosign as on the
# platform (Argo CD v3.5.5) and in release.yml (cosign v3.1.3); docker CLI as Docker Desktop
ARG KUBECTL_VERSION=v1.35.9
ARG KUBECTL_SHA256=3cfeaf80be482b435b0aa214aff6e0b2c312ee23c0ff20810c75517b6004c6eb
ARG HELM_VERSION=v4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
ARG GH_VERSION=2.102.0
ARG GH_SHA256=bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386
ARG ARGOCD_VERSION=v3.5.5
ARG ARGOCD_SHA256=c3ddfa606fc3e89ab14f55bda6600b207c355b028f8eaabe69b817a4c4621aba
ARG COSIGN_VERSION=v3.1.3
ARG COSIGN_SHA256=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71
ARG DOCKER_VERSION=29.8.0
ARG DOCKER_SHA256=cc21815cf1e2efed867dc9c8b96b46ffed8ea176ffab32b0aacb54726ded8f25

# make (o2c-app make eval), jq (JSON in the pipelines)
RUN [ "$(dpkg --print-architecture)" = amd64 ] || { echo "amd64 only (pinned checksums)" >&2; exit 1; } \
  && apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl jq make \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; cd /tmp; \
  fetch() { curl -fsSL --retry 3 -o "$2" "$1"; echo "$3  $2" | sha256sum -c -; }; \
  fetch "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" kubectl "$KUBECTL_SHA256"; \
  install -m 0755 kubectl /usr/local/bin/kubectl; \
  fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" helm.tgz "$HELM_SHA256"; \
  tar -xzf helm.tgz --strip-components=1 -C /usr/local/bin linux-amd64/helm; \
  fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" gh.tgz "$GH_SHA256"; \
  tar -xzf gh.tgz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"; \
  fetch "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" argocd "$ARGOCD_SHA256"; \
  install -m 0755 argocd /usr/local/bin/argocd; \
  fetch "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" cosign "$COSIGN_SHA256"; \
  install -m 0755 cosign /usr/local/bin/cosign; \
  fetch "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" docker.tgz "$DOCKER_SHA256"; \
  tar -xzf docker.tgz --strip-components=1 -C /usr/local/bin docker/docker; \
  rm -f /tmp/kubectl /tmp/helm.tgz /tmp/gh.tgz /tmp/argocd /tmp/cosign /tmp/docker.tgz

# uv (o2c-app: uv sync, uv run; yamllint through uvx); Python itself comes from uv
COPY --from=ghcr.io/astral-sh/uv:0.13.1@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 /uv /uvx /usr/local/bin/

# The Ansible role copies the JCasC secrets in here before Jenkins starts
RUN install -d -o jenkins -g jenkins -m 0700 /run/secrets

USER jenkins
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration as code, outside JENKINS_HOME so the image's version always applies
COPY casc.yaml /var/jenkins_casc/casc.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_casc/casc.yaml \
  JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
