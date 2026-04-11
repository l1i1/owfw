# 京东云亚瑟 AX1800 Pro OpenWrt 固件 (含 MgrServer)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) (master 分支) 自动编译的定制固件，内置 MgrServer 路由器管理后台。

**目标设备:** JDCloud RE-SS-01 (Qualcomm IPQ60xx)

## 📦 固件功能

### 核心组件

| 组件 | 说明 |
|------|------|
| **MgrServer** | 路由器管理后台 (Koa + React)，端口 `:80` |
| **LuCI** | OpenWrt 原生管理界面，端口 `:3500` |
| **Node.js 20.x** | MgrServer 运行时 |
| **Python3** | 25 个子包，脚本与工具链 |
| **sing-box** | 代理加速引擎 |
| **easytier** + luci-app-easytier | P2P 组网 + LuCI 插件 (预编译 IPK) |

### 网络核心

| 组件 | 说明 |
|------|------|
| **firewall4 + nftables** | nftables 防火墙 (含 offload) |
| **dnsmasq-full** | DNS/DHCP 服务器 |
| **odhcp6c** | IPv6 DHCP 客户端 |
| **swconfig** | 交换机配置 |
| **iwinfo / iw** | 无线信息工具 |
| **ip-full** | 完整 iproute2 工具集 |

### 硬件加速

| 组件 | 说明 |
|------|------|
| **NSS 驱动** | `kmod-qca-nss-drv` — 高通硬件转发 |
| **NSS ECM** | `kmod-qca-nss-ecm` — 连接管理 |
| **NSS Crypto** | `kmod-qca-nss-crypto` — 硬件加密 |
| **NSS Clients** | `kmod-qca-nss-clients` — 客户端支持 |
| **NSS IFB** | `kmod-nss-ifb` — 接口绑定 |
| **eBPF** | 内核 BPF syscall + JIT (基础支持) |

### 无线中继 / Mesh

| 组件 | 说明 |
|------|------|
| **wpad-mesh-openssl** | WPA3/SAE/Mesh (替代 wpad-basic) |
| **hostapd-openssl** | 企业级 AP |
| **relayd** | 无线中继 |
| **batman-adv + batctl** | Mesh 网络协议与管理工具 |
| **bridge** | 网桥工具 |
| **igmpproxy** | IGMP 代理 |
| **luci-proto-relay** | LuCI 中继配置插件 |
| **luci-proto-batman_adv** | LuCI batman-adv 配置插件 |
| **kmod-nft-bridge** | nftables 网桥支持 |

### USB 与存储

| 组件 | 说明 |
|------|------|
| **USB 2.0/3.0** | `kmod-usb-core`, `kmod-usb2`, `kmod-usb3` |
| **USB ACM** | `kmod-usb-acm` — 串口设备 |
| **USB Net** | `kmod-usb-net`, `kmod-usb-net-rndis` — 网络设备 |
| **USB Serial** | `kmod-usb-serial`, `kmod-usb-serial-option` — 调制解调器 |
| **ext4** | `/home` 分区自动挂载 |
| **UDF/ISO** | PXE 启动支持 |
| **wimlib / 7z** | Windows WIM 镜像处理 |

### 系统工具

`curl`, `wget`, `rsync`, `nano`, `ethtool`, `openssh-sftp-server`

## 🚀 编译

### 主固件构建

1. Fork 本仓库
2. 进入 `Actions` → `Build OpenWrt for JDCloud AX1800 Pro`
3. 点击 `Run workflow`
   - `mgrserver_repo` — MgrServer 仓库地址 (默认 `l1i1/MgrServer`)
   - `mgrserver_branch` — MgrServer 分支 (默认 `main`)
   - `ssh` — 设为 `true` 可开启 SSH 远程调试
4. 等待 2-4 小时
5. 在 `Releases` 页面下载固件

### 编译优化

- **EasyTier + luci-app-easytier**: 编译时直接提取 [官方预编译 IPK](https://github.com/EasyTier/luci-app-easytier/releases) 到 `files/`，无需首次启动安装，LuCI 插件也已内置
- **MgrServer**: 在 CI 中预编译后以文件形式注入固件，不占用 OpenWrt 编译时间

### 其他工作流

| 工作流 | 说明 |
|--------|------|
| `Build luci-app-modem IPK` | 编译 4G/5G 调制解调器管理插件 (Siriling 5G Modem Support) |
| `Compile Packages Only` | 单独编译 PassWall、xray-core、hysteria、Samba4、FileBrowser 等插件 IPK |
| `Test Runner` | 配置验证与下载测试 |

## 📥 刷机

### 首次刷入 (需已刷 Uboot)

1. 断电，按住 Reset 键后通电
2. 访问 Uboot Web 界面 (`192.168.1.1`)
3. 上传 `*-sysupgrade.bin` 固件
4. 等待刷写完成，自动重启

### 升级固件

1. 进入 OpenWrt → 系统 → 备份/升级
2. 上传 `*-sysupgrade.bin` 固件
3. 可选：勾选 "保留配置"
4. 点击升级

## ⚙️ 默认设置

| 项目 | 值 |
|------|-----|
| MgrServer | `http://192.168.1.1` (密码: `password`) |
| LuCI | `http://192.168.1.1:3500` |
| 用户名 | `root` |
| 密码 | 无（首次登录请设置） |
| 主机名 | `JDCloud` |
| 时区 | `Asia/Shanghai` |
| 软件源 | USTC 镜像 (首次启动自动配置) |

## 🔧 MgrServer

MgrServer 是独立于 LuCI 的路由器管理后台，提供：

- 系统快照与监控
- 网络 / WiFi 配置管理
- sing-box 代理加速管理
- easytier P2P 组网管理
- PXE 网络启动管理
- 文件管理与命令执行
- 分级权限 (admin / superadmin)

固件内置 MgrServer 运行时（Node.js + 预编译应用），首次启动时通过 uci-defaults 自动配置端口：MgrServer 占用 `:80`，LuCI 移至 `:3500`。

### 修改配置

```bash
uci set mgrserver.main.mgmt_password='your-password'
uci set mgrserver.main.port='80'
uci commit mgrserver
/etc/init.d/mgrserver restart
```

## 📁 项目结构

```
.
├── .github/workflows/
│   ├── build-openwrt.yml        # 主固件构建 (含 MgrServer + 预编译 IPK)
│   ├── build-modem-ipk.yml      # 调制解调器插件 IPK 编译
│   ├── compile-packages.yml     # 插件 IPK 编译
│   └── test-runner.yml          # 配置验证与下载测试
├── configs/
│   └── jdc-ax1800pro.config     # 设备 .config (含所有包选择)
├── scripts/
│   ├── diy-part1.sh             # Feed 源配置
│   └── diy-part2.sh             # 编译前定制 (主机名/时区/NSS 标志/权限)
├── files/
│   └── etc/
│       ├── banner               # 登录横幅
│       ├── config/mgrserver     # MgrServer UCI 配置
│       ├── init.d/mgrserver     # procd 服务脚本
│       └── uci-defaults/
│           ├── 97-opkg-mirror      # opkg 软件源替换为 USTC 镜像
│           ├── 98-home-partition   # /home 分区自动挂载
│           └── 99-mgrserver-ports  # MgrServer 端口配置
├── package/
│   └── utils/wimlib/            # wimlib 自定义包 (PXE WIM 支持)
├── feeds.conf.default           # Feed 源 (ImmortalWrt)
└── README.md
```

## ⚠️ 注意事项

### WiFi 性能
- 5GHz 发射功率建议 20-23dBm
- 推荐信道: 149 或 157

### 固件体积
- 内置 Node.js + MgrServer 增加约 40-60MB
- 如需精简，可在 workflow 中移除 MgrServer 构建步骤

### NSS 硬件加速
- NSS CONFIG 标志通过 `scripts/diy-part2.sh` 条件注入 `.config`
- 需确保 `kmod-qca-nss-drv=y` 在 `.config` 中启用

### eBPF
- 仅启用内核 BPF syscall/JIT 支持
- `kmod-sched-bpf` 未包含（qualcommax 目标编译 `act_bpf.ko` 失败）

### wpad 冲突
- `wpad-basic` 已显式禁用 (`=n`)，避免与 `wpad-mesh-openssl` 冲突

### 软件源
- 首次启动自动将 opkg 源替换为 USTC 镜像 (`97-opkg-mirror`)
- 如镜像不可用，手动编辑 `/etc/opkg/distfeeds.conf`

### 预编译 IPK
- EasyTier + luci-app-easytier 在编译时直接提取到 `files/` overlay，固件启动后即完整可用（无需首次启动安装）
- sing-box 同样在编译时提取，不占用 OpenWrt 编译时间

## 🙏 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [EasyTier](https://github.com/EasyTier/luci-app-easytier)
- [Siriling 5G Modem Support](https://github.com/Siriling/5G-Modem-Support)
