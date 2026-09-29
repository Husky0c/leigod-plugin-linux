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
│   ├── compat/
│   │   ├── ps                    # BusyBox 风格 ps 兼容层（新版上游需要）
│   │   └── uci                   # uci 兼容层，保存/镜像绑定令牌（新版上游需要）
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

监控脚本还会跟踪闭源程序 fork 出的 `-r web` 工作进程（手机 App 的本地接口）。该
进程会因上游缺陷（见 Issue #5）反复以 SIGABRT 退出，而主程序往往在旧进程仍占用端
口时立刻补拉一个新进程，把单次失败放大成崩溃循环。检测到这种循环后，脚本会先回收
整套加速进程（`-r daemon` 与 `-r web`）再重新拉起，并把 `/tmp/acc/log` 的末尾若干
行写入 journald；如果长时间无法稳定，则主动退出，让 systemd 在 `systemctl status`
中明确报错并限流，而不是把崩溃隐藏在“运行中”的状态里。启动时脚本还会把**绑定令牌是否存在**
写进 journald（只报位置、不打印令牌内容），方便判断「云端有记录但连不上」到底是设备侧没有
令牌，还是本地接口在崩溃循环。阈值可通过环境变量调整：
`LEIGOD_MAX_WEB_CRASHES`（默认 3 次）、`LEIGOD_WEB_CRASH_WINDOW`（默认 900 秒）、
`LEIGOD_MAX_WEB_RECOVERIES`（默认 5 次）。

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

**Q: `systemctl status` 里反复出现 `acc-gw.router.amd64 ... dumped core`？**

这是雷神闭源主程序的 `-r web` 工作进程在上游崩溃——未捕获的
`websocketpp::exception ... invalid state` 触发 SIGABRT（记录于 Issue
[#5](https://github.com/Husky0c/leigod-plugin-linux/issues/5)），不是本项目的脚本
崩溃。该进程负责手机 App 的本地接口，所以崩溃循环期间 App 会连不上：`5588` 端口虽
然在 LISTEN，但请求得不到响应（`curl` 报 `Empty reply from server`）。

监控脚本会记录并尝试自动恢复整个加速进程，可以这样查看：

```bash
journalctl -xeu leigod_plugin.service | grep -E 'Web helper|dumped core'
```

如果恢复后仍然反复出现，说明上游进程始终无法建立到调度服务器的连接。建议在同一台
机器上排查：本地代理 / 透明网关是否把 `box-turn.xxghh.biz`、`route-turn.xxghh.biz`
解析或转发到了不可用的地址（例如 Clash/Mihomo 的 fake-ip 段），以及到 `:5443` 的
TLS 连接能否正常完成。

**Q: 直接用官方的 `curl route-turn.xxghh.biz/plugin_install.sh | sudo sh` 行不行？**

不行，而且在普通 PC 上它**什么都不会装**。官方流程图（本仓库下载并阅读过该脚本，未执行）：

1. `plugin_install.sh` 先从 `http://119.3.40.126` 下载 `plugin_common.sh` 并 source 它；
2. `preinstall_check` 里只有三条分支：`/etc/openwrt_release` 存在 → openwrt；`/etc/image_version`、`/koolshare`、
   `/jffs/softcenter` 存在 → asus 梅林；否则 `is_steamdeck_decice`
   （判定条件：`/sys/class/dmi/id/product_name == Jupiter` **或** `/etc/os-release` 里出现 `steamdeck` 字样）；
3. 三条都不满足时，`${is_openwrt}`/`${is_asus}`/`${is_steamdeck}` 都是空值，三个 `if` 全部跳过，
   脚本直接结束 —— 不下载、不建服务、不提示。

本仓库存在的意义正是**在外部把第 2 步要的这些特征伪造出来**（`BindReadOnlyPaths` 注入
`product_name=Jupiter` 与 SteamOS 的 `/etc/os-release`，现在连 `VARIANT_ID=steamdeck` 也一并补上，
和你手改官方脚本检测逻辑等价），再自己装一套加固过的服务。

另外两点（都已实测）：

- 官方 release 路径 `http://119.3.40.126/acc-gw.router.amd64` 现在就是那个**带 OpenWrt 逻辑的新版**
  （`f81ec6a7…`，自报 1.3.0.01），也就是会崩的那个；
- 官方 **test 路径**里还放着旧的 SteamDeck 版二进制
  `http://119.3.40.126/router_plugin_new_test/steamdeck/acc-gw.router.amd64`
  （6138184 字节，Last-Modified 2026-04-28，SHA-256 `8e0adbd1b1ce0d37e6588ff222408fed66a3f8954fee27bc37a10e0bf6806d4d`）——
  正是本仓库上一版 pin 的哈希。如果将来想退回旧版，可以把 `checksums.sha256` 里
  `acc-gw.router.amd64` 的哈希改回该值，并用
  `LEIGOD_BASE_URL=http://119.3.40.126/router_plugin_new_test/steamdeck ./install.sh` 安装。



要区分两侧状态：

- **账号侧**：App 里能看到这台设备，说明云端还记着这次绑定（绑定键是本机持久化的虚拟网卡
  MAC，见 `device MAC`，换网卡/重装都不会变）。
- **设备侧**：App 要连上，需要同时满足
  1. 本地接口（`5588`）活着——新版上游的 `ps` 解析 bug 会让 `-r web` 每 5 秒崩一次
     （见上面的 BusyBox `ps` 条目，已由 `compat/ps` 修复）；
  2. 本地能读到**绑定令牌**——新版改成通过 `uci` 存取，普通发行版没有 `uci` 就存不下来，
     本仓库用 `compat/uci` 把令牌落在 `/opt/leigod/config/uci/accelerator`，并镜像到
     `/opt/leigod/config/accelerator.ini` 的 `[base] token`，供旧代码路径读取。该目录
     不会被重新安装覆盖，所以绑定可以跨重装保留。

监控脚本启动时会把令牌状态写进 journald（只报存在与否，不打印令牌内容）：

```bash
journalctl -u leigod_plugin.service | grep -E 'Binding token|No binding token'
```

- 显示 `Binding token present in: …` → 设备侧已有令牌，若仍连不上就看第 1 条（接口崩溃循环）。
- 显示 `No binding token stored yet` → 设备侧没有令牌，请在 App 里重新绑定一次
  （`systemctl restart leigod_plugin.service` 后再操作）。注意：旧版升级上来时，如果令牌
  只存在旧位置（例如 `config/accelerator`），重新安装会把该文件清空，需要重新绑定。



**Q: 上游更新后彻底跑不起来（OpenWrt / BusyBox 相关内容）？**

从 2026-09 的上游构建（自报 `acc version:1.3.0.01`，SHA-256
`f81ec6a7e1a5bcef8cb8d1bf233141ece7d54250881422ecc2814c98df819e23`）起，雷神把
路由/OpenWrt 的代码路径混了进来，闭源程序会：

- 用 `uci get accelerator.base.token` 读取绑定令牌（由 `compat/uci` 兼容层应答，
  令牌存放在 `config/uci/accelerator` 并镜像进 `accelerator.ini`）；
- 尝试读取 `/etc/board.json`（OpenWrt 板级数据库，普通发行版没有，只会产生一条 WARN）；
- 执行 `ps ax | grep acc-gw.router.amd64` 来查找自己的子进程，并按 **BusyBox 的
  `ps ax` 列格式**（`PID USER VSZ STAT COMMAND`）解析第 3 列。

最后一条是致命的：glibc/util-linux 发行版的 `ps ax` 是 `PID TTY STAT TIME COMMAND`，
于是解析到状态字符串（如 `Ss`）时抛出未捕获的 `std::invalid_argument`，进程直接
SIGABRT（`systemctl status` 里的 `dumped core`），或者主程序每 5 秒重新 fork 一次
`-r web` 子进程、手机 App 始终连不上。

本仓库为此提供了 `compat/ps`：一个只处理「列出全部进程」调用的兼容层，输出 BusyBox
风格的列并隐藏查询自身的 `sh`/`grep` 进程。监控脚本会把 `/opt/leigod/compat` 放到
`PATH` 最前面，因此重新安装（`sudo ./install.sh`）后即可生效：

```bash
journalctl -xeu leigod_plugin.service | grep -E 'Web helper|Invalid input|dumped core'
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
