# Leigod Plugin — SteamDeck 网络加速器 | 通用 Linux 移植版

[雷神加速器](https://www.leigod.com) 的 SteamDeck 插件兼容层，面向使用 systemd 的、
可变更系统分区的 **x86_64 Linux**。通过外部环境模拟 SteamDeck 硬件后，可使用手机
App 绑定并启动网络加速。

## 原理

| 机制 | 手段 |
|------|------|
| **硬件伪装** | systemd `BindReadOnlyPaths` 劫持 `/sys/class/dmi/id/product_name` → `Jupiter` |
| **系统伪装** | 同上劫持 `/etc/os-release` → `SteamOS` |
| **网卡伪装** | 创建 `dummy` 类型虚拟 `wlan0`，使用持久化的本机专属 MAC |
| **路径修复** | `/home/leigod` → `/opt/leigod` 符号链接 |
| **进程管理** | systemd `KillMode=control-group` 确保重启时清理所有子进程 |

> **本项目的技术定位：** 仅通过 systemd 的 `BindReadOnlyPaths` 和网络层配置（创建 dummy 接口）在**外部模拟** SteamDeck 运行环境。未对雷神核心二进制（`acc-gw.router.amd64`）进行任何逆向分析、修改或破解。

## 系统要求与支持范围

- **架构**：仅 x86_64（amd64）；
- **init**：正在运行的 systemd 249 或更高版本；
- **内核能力**：`dummy`、TUN（必须存在 `/dev/net/tun`）、netfilter/iptables；
- **用户空间依赖**：`curl`、`ip`、`ipset`、`iptables`、`pgrep`、
  `sha256sum`；安装脚本会按发行版安装对应软件包；
- **网络**：安装或构建时需要连接雷神下载服务器。

当前宿主机安装脚本只支持以下可变更系统：

| 系列 | 包管理器 | 状态 |
|---|---|---|
| Debian / Ubuntu | `apt-get` | 支持 |
| Fedora | `dnf` | 支持 |
| Arch Linux | `pacman` | 支持 |
| openSUSE | `zypper` | 支持 |

Bazzite、Fedora Silverblue/Kinoite、CoreOS、bootc 等 Atomic/不可变发行版不支持
直接运行本安装脚本。脚本会在修改系统前拒绝这些环境；建议使用独立的、可变更的
Linux 系统或虚拟机。

## 快速安装

```bash
git clone https://github.com/Husky0c/leigod-plugin-linux.git
cd leigod-plugin-linux
sudo ./install.sh
```

安装脚本会下载雷神文件，在执行或安装前使用仓库固定的 SHA-256 进行校验。校验失败时安装会立即终止，原有已安装文件不会被替换。

安装后打开手机雷神加速器 App → 绑定设备 → 开始加速。

首次启动会根据 `/etc/machine-id` 生成一个本地管理、单播 MAC，并保存到
`/var/lib/leigod/device-mac`。它不再复制 NetworkManager 可能随机化的物理网卡
MAC，因此重启服务或重新安装后设备身份保持不变。

## 下载安全

雷神当前提供的下载地址是明文 HTTP，传输层本身无法证明文件来源。因此本项目将允许执行的文件哈希固定在 [`checksums.sha256`](checksums.sha256) 中，并执行以下流程：

1. 下载到权限受限的临时目录；
2. 所有文件完成 SHA-256 校验；
3. 校验全部通过后，才在目标文件系统内原子替换；
4. 任一下载或校验失败时安全退出。

如果雷神更新远端文件，安装会因哈希变化而失败。这是预期的安全行为。维护者应通过可信、独立渠道取得并审核新文件后，再更新版本号和哈希；不要关闭或绕过校验。

为防止闭源升级程序绕过上述校验，`acc_upgrade_monitor` 默认不启动。建议通过本仓库的新版本更新。如果明确接受未经过本仓库固定哈希验证的自动更新风险，可使用 systemd drop-in 显式启用：

```ini
[Service]
Environment=LEIGOD_ENABLE_UPDATER=1
```

## 文件结构

```text
leigod-plugin-linux/
├── install.sh                    # 通用安装脚本
├── uninstall.sh                  # 通用卸载脚本
├── checksums.sha256              # 固定的上游文件 SHA-256
├── release.env                   # 版本与可复现构建时间戳
├── THIRD_PARTY_NOTICES.md        # 第三方文件及许可边界
├── scripts/
│   ├── fetch-assets.sh           # 下载、校验与原子安装
│   └── device-mac.sh             # 生成并持久化设备 MAC
├── opt/leigod/
│   ├── acc-gw.router.amd64       # 雷神加速主程序（下载时获取）
│   ├── acc_upgrade_monitor       # 升级程序副本（默认不启动）
│   ├── steamdeck_acc_monitor.sh  # 进程守护脚本
│   ├── leigod_uninstall.sh       # 安全卸载脚本
│   ├── fake_os-release           # 伪造 SteamOS 信息
│   ├── fake_product_name         # 伪造 Jupiter 硬件名
│   └── config/
│       ├── accelerator.ini       # 雷神加速器配置
│       ├── accelerator           # OpenWrt 兼容占位文件
│       ├── acc_version.ini       # 版本信息
│       ├── new_upgrade_conf.json # 升级策略配置
│       └── ipdatacloud_country.xdb  # IP 地理位置数据库（下载时获取）
├── systemd/
│   └── leigod_plugin.service     # systemd 服务单元
├── debian/                       # dpkg-deb 元数据和维护脚本
├── tests/                        # 自动测试
├── .github/workflows/            # CI 与源码 Release 工作流
└── packages/
    ├── build-deb.sh              # 构建 .deb 包
    └── build-tar.sh              # 构建 .tar.gz 包
```

## 服务管理

```bash
sudo systemctl status  leigod_plugin.service
sudo systemctl restart leigod_plugin.service
sudo systemctl stop    leigod_plugin.service
sudo journalctl -xeu   leigod_plugin.service
```

监控脚本直接写入 journald，不再无限追加自己的日志文件。systemd 负责日志轮转；
闭源程序需要的 `/tmp/acc` 位于 `PrivateTmp` 隔离空间、权限为 `0700`，其主日志默认
超过 50 MiB 时截断。服务锁位于权限为 `0700` 的 `/run/leigod`，并通过原子目录
创建；设备 MAC 位于 `/var/lib/leigod`，用于跨重装保持身份。

## 卸载

```bash
cd leigod-plugin-linux
sudo ./uninstall.sh
```

卸载脚本不会清空宿主机共享的 iptables 表。服务会先收到停止信号，以便核心程序清理其规则；如异常退出后网络状态仍有残留，安全做法是重启系统，不要执行 `iptables -t mangle -F`。

默认卸载会保留 `/var/lib/leigod/device-mac`。如需同时清除绑定身份：

```bash
sudo LEIGOD_PURGE_STATE=1 ./uninstall.sh
```

## 从零构建安装包

构建脚本同样会下载并校验固定哈希，校验失败时不会生成安装包。

```bash
cd packages
bash build-deb.sh
bash build-tar.sh
```

构建产物输出到 `packages/` 目录。

构建器使用固定的上游 SHA-256、统一文件时间戳、排序和数字所有者信息，确保相同
源码及相同 `release.env` 可以生成相同产物。CI 会验证 Shell 语法、MAC 稳定性、
下载篡改失败保护以及 TAR 包可复现性。

带版本标签的 GitHub Actions Release 只发布可复现的**源码包**。包含雷神二进制的
DEB/TAR 仅供本地构建；未取得权利人明确许可前，不应公开再分发。

## 常见问题

**Q: 下载文件提示 SHA-256 mismatch？**  
远端文件已经变化或传输内容遭到篡改。不要绕过校验；等待项目审核新版本并更新 `checksums.sha256`。

**Q: 加速无法启动，App 显示错误？**

```bash
journalctl -xeu leigod_plugin.service
```

**Q: 重启后加速失效？**  
这是正常行为。加速状态不会持久化，每次需要从 App 重新开启加速。

**Q: 可以用于 ARM 设备（树莓派）吗？**  
不能。雷神官方只提供了 amd64 二进制。

**Q: 更换网卡后绑定会丢失吗？**  
虚拟 `wlan0` 使用 `/var/lib/leigod/device-mac` 中的持久 MAC，与物理网卡无关。
如果系统本身已有名为 `wlan0` 的物理无线接口，脚本不会擅自修改它；绑定前需在
NetworkManager 中为该连接关闭 MAC 随机化。Issue
[#1](https://github.com/Husky0c/leigod-plugin-linux/issues/1) 记录了这一情况。

## 免责声明

本仓库**不含**雷神官方二进制文件，也未对雷神核心程序进行任何逆向分析、修改或破解。所有脚本仅通过 systemd 的 `BindReadOnlyPaths` 和网络层配置（创建 dummy 接口）在**外部模拟** SteamDeck 运行环境，使未修改的雷神官方二进制在普通 PC 上正常运行。

`acc-gw.router.amd64` 和 `ipdatacloud_country.xdb` 由安装/构建脚本下载并校验，
版权归雷神所有。仓库根目录 MIT License 只覆盖本项目原创代码，不覆盖雷神二进制、
数据库、配置或上游衍生内容；具体边界见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。使用及再分发前需遵守雷神
服务条款并取得必要授权。

本项目仅供学习研究。请遵守当地法律法规。

## 友链

- [LINUX DO](https://linux.do) - 友好的科技前沿爱好者社区
