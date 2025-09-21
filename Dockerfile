FROM madpeteguy/jenkins-docker-slave-ssh:1.4.0

LABEL maintainer="Mad Pete Guy"

ENV DEBIAN_FRONTEND=noninteractive

RUN for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg || true; done

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    iptables \
    git \
    tini \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/tini /usr/local/bin/docker-init

RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get -qy autoremove && apt-get clean

COPY --from=docker:dind /usr/local/bin/dockerd-entrypoint.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME /var/lib/docker
EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
