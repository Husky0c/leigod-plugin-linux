#!/bin/sh

# 通用进程守护脚本
# 默认只监控加速主进程。闭源自动升级进程默认禁用，避免绕过仓库中固定的
# SHA-256 校验。确有需要时可显式设置 LEIGOD_ENABLE_UPDATER=1。

run_env=$1

# 日志目录配置
LOG_DIR="/tmp/acc/log/"
LOG_FILE="$LOG_DIR/steamdeck_acc_monitor.log"

UPGRADE_FLAG="/tmp/acc/upgrade_flag"

# 创建日志目录（如果不存在）
mkdir -p "$LOG_DIR"

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 初始化日志
echo "=========================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting process monitor daemon" >> "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"

# 获取架构
arch=$(uname -m)
if [ "${arch}" = "x86_64" ]; then
    log_message "match x86_64 -> amd64"
    arch="amd64"
elif [ "${arch}" = "aarch64" ]; then
    log_message "match aarch64 -> arm64"
    arch="arm64"
elif [ "${arch}" = "mips" ]; then
    log_message "match mips -> mipsel"
    arch="mipsel"
elif [ "${arch}" = "armv7l" ]; then
    log_message "match armv7l -> arm"
    arch="arm"
else
    log_message "current arch not support, arch: ${arch}"
    exit 1
fi

# 获取 Steam Deck 安装目录
get_steamdeck_party() {
    BASE_PATH="/opt/leigod"
    log_message "steamdeck plugin install directory is $BASE_PATH"
}

# 调用函数获取安装目录
get_steamdeck_party

# 创建虚拟 wlan0 网卡（雷神需要它来获取设备号）
if ! ip link show wlan0 >/dev/null 2>&1; then
    # 获取真实物理网卡的固定 MAC 地址
    REAL_MAC=""
    for iface in wlp0s20f3 wlan0 eno2 eno1 ens32 ens33 ens34 ens35 ens36; do
        if [ -f "/sys/class/net/${iface}/address" ]; then
            REAL_MAC=$(cat "/sys/class/net/${iface}/address" 2>/dev/null)
            [ -n "$REAL_MAC" ] && break
        fi
    done
    # 如果都没找到，生成一个基于机器 ID 的固定 MAC
    if [ -z "$REAL_MAC" ]; then
        REAL_MAC="02:$(cat /etc/machine-id 2>/dev/null | md5sum | head -c 10 | sed 's/\(..\)/\1:/g;s/:$//')"
    fi
    ip link add wlan0 type dummy
    ip link set wlan0 address "$REAL_MAC"
    ip link set wlan0 up
    log_message "Created dummy wlan0 with MAC: $REAL_MAC"
fi

# 单例锁文件路径（防止重复运行）
LOCK_FILE="/var/run/acc_daemon.lock"

# 守护的进程列表
# 格式：进程名:匹配参数:启动命令
if [ "${run_env}" = "test" ]; then
    PROCESS_DATA="
    acc-gw.router.${arch}:-d debug -r daemon:${BASE_PATH}/acc-gw.router.${arch} -d debug -r daemon -m tun -p 5588
    "
    UPGRADE_PROCESS_DATA="
    acc_upgrade_monitor:-d debug -r upgrade:${BASE_PATH}/acc_upgrade_monitor -d debug -r upgrade
    "
else
    PROCESS_DATA="
    acc-gw.router.${arch}:-r daemon:${BASE_PATH}/acc-gw.router.${arch} -r daemon -m tun -p 5588
    "
    UPGRADE_PROCESS_DATA="
    acc_upgrade_monitor:-r upgrade:${BASE_PATH}/acc_upgrade_monitor -r upgrade
    "
fi

if [ "${LEIGOD_ENABLE_UPDATER:-0}" = "1" ]; then
    PROCESS_DATA="${PROCESS_DATA}${UPGRADE_PROCESS_DATA}"
    log_message "WARNING: automatic upstream updater enabled; downloaded updates are not verified by checksums.sha256"
else
    log_message "Automatic upstream updater disabled; update through the verified installer"
fi

# 检查是否已有实例在运行
if [ -f "$LOCK_FILE" ]; then
    if kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        log_message "[Monitor] Daemon is already running (PID: $(cat "$LOCK_FILE")). Exiting."
        exit 1
    else
        # 锁文件存在但进程已死，清理锁文件
        log_message "[Monitor] Removing stale lock file"
        rm -f "$LOCK_FILE"
    fi
fi

# 创建锁文件（写入当前PID）
echo $$ > "$LOCK_FILE"

# 检查进程是否存在（精确匹配参数）
is_process_running() {
    process_name="$1"
    pattern="$2"

    # 使用 pidof 获取进程PID
    pids=$(pidof "$process_name" 2>/dev/null)
    if [ -z "$pids" ]; then
        return 1
    fi

    # 遍历所有PID，检查命令行参数是否匹配
    for pid in $pids; do
        if [ -f "/proc/$pid/cmdline" ]; then
            # 读取进程命令行，将 \0 替换为空格
            cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline")
            if echo "$cmdline" | grep -qF -- "$pattern"; then
                return 0
            fi
        fi
    done
    return 1
}

log_message "Monitor daemon started (PID: $$)"
log_message "Monitoring processes:"

# 主循环
while true; do
    # 判断是否正在升级，如果在升级则退出，由 systemd 按策略处理
    if [ -f "$UPGRADE_FLAG" ]; then
        log_message "Upgrade flag detected; monitor exiting"
        exit 0
    fi

    echo "$PROCESS_DATA" | while IFS=":" read -r process_name pattern start_cmd; do
        # 跳过空行或空白行
        [ -z "$(echo "$process_name" | tr -d " ")" ] && continue

        # 去除可能的空格
        process_name=$(echo "$process_name" | xargs)
        pattern=$(echo "$pattern" | xargs)
        start_cmd=$(echo "$start_cmd" | xargs)

        # 检查进程是否存在
        if ! is_process_running "$process_name" "$pattern"; then
            log_message "Process not running: $process_name, starting..."
            log_message "Start command: $start_cmd"

            # 命令内容由上面的静态 PROCESS_DATA 构造，不接受外部输入。
            # shellcheck disable=SC2086
            $start_cmd >/dev/null 2>&1 </dev/null &

            # 短暂等待，让进程启动
            sleep 1

            # 验证进程是否成功启动
            if is_process_running "$process_name" "$pattern"; then
                log_message "Successfully started: $process_name"
            else
                log_message "Failed to start: $process_name"
            fi
        fi
    done

    # 每5秒检查一次
    sleep 5
done
