#!/bin/bash
set -euo pipefail

if [ "${1:-}" = "systemd" ]; then
  mkdir -p /run/systemd /var/log/journal
  export container=docker

  if [ -x /lib/systemd/systemd ]; then
    exec /lib/systemd/systemd
  elif [ -x /usr/lib/systemd/systemd ]; then
    exec /usr/lib/systemd/systemd
  elif [ -x /sbin/init ]; then
    exec /sbin/init
  fi
fi

exec "$@"
