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
    && LEIGOD_SKIP_SYSTEMD=1 ./install.sh \
    && ln -sf /etc/systemd/system/leigod_plugin.service /etc/systemd/system/default.target.wants/leigod_plugin.service

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["systemd"]
