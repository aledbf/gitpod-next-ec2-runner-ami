FROM gitpod/workspace-base

ENV DOCKER_BUILDKIT=1

USER root

ENV AWS_VERSION=2.15.0
ENV SHELLCHECK_VERSION=v0.9.0
ENV SHFMT_VERSION=3.7.0

RUN install-packages \
    curl \
    ca-certificates \
    net-tools \
    jq \
    unzip \
    curl \
    docker-buildx-plugin

RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_VERSION}.zip" -o "awscliv2.zip" \
  && unzip -qo awscliv2.zip \
  && ./aws/install --update \
  && rm -rf awscliv2.zip

RUN SHELLCHECK_TGZ="shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  && curl -fsSLO "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${SHELLCHECK_TGZ}" \
  && tar  --extract --strip-components=1 --file="${SHELLCHECK_TGZ}" "shellcheck-${SHELLCHECK_VERSION}/shellcheck" \
  && mv shellcheck /usr/local/bin/shellcheck \
  && chmod +x /usr/local/bin/shellcheck \
  && rm -rf "${SHELLCHECK_TGZ}"

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg -o - | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
  && install-packages packer

RUN curl -fsSL "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64" -o /usr/local/bin/shfmt \
  && chmod +x /usr/local/bin/shfmt

RUN install-packages pip \
  && pip install pre-commit --no-cache-dir

USER gitpod
