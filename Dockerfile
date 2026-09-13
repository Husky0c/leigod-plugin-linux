FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    dbus \
    iproute2 \
    ipset \
    iptables \
    net-tools \
    procps \
    sudo \
    systemd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace

RUN chmod +x /workspace/install.sh /workspace/uninstall.sh \
    /workspace/opt/leigod/steamdeck_acc_monitor.sh \
    /workspace/opt/leigod/leigod_uninstall.sh \
    && mkdir -p /opt/leigod /home /tmp/acc/log /etc/systemd/system/default.target.wants \
    && cd /workspace \
    && LEIGOD_INSTALLED_IN_CONTAINER=1 ./install.sh

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/opt/leigod/steamdeck_acc_monitor.sh"]
