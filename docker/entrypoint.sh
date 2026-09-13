#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# 模拟 systemd 的 BindReadOnlyPaths：将伪造的文件绑定挂载到系统路径
# 需要容器具有 CAP_SYS_ADMIN 能力
# ------------------------------------------------------------

# 确保目标目录存在（/sys/class/dmi/id 可能不存在）
mkdir -p /sys/class/dmi/id

# 挂载伪造的 product_name
if [ -f /opt/leigod/fake_product_name ]; then
    mount --bind /opt/leigod/fake_product_name /sys/class/dmi/id/product_name
    mount -o remount,ro /sys/class/dmi/id/product_name
    echo "Mounted /opt/leigod/fake_product_name -> /sys/class/dmi/id/product_name"
else
    echo "Warning: /opt/leigod/fake_product_name not found, skipping"
fi

# 挂载伪造的 os-release（覆盖容器原有的 /etc/os-release）
if [ -f /opt/leigod/fake_os-release ]; then
    mount --bind /opt/leigod/fake_os-release /etc/os-release
    mount -o remount,ro /etc/os-release
    echo "Mounted /opt/leigod/fake_os-release -> /etc/os-release"
else
    echo "Warning: /opt/leigod/fake_os-release not found, skipping"
fi

# 执行传入的命令（例如：/opt/leigod/steamdeck_acc_monitor.sh）
exec "$@"