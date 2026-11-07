# VPS 节点部署与调优指南

新 VPS 上手指南：基础环境安装、SuRelay 节点部署、BBR/TCP 调优及 NQ/TQ 网络测试。

适用 Debian 12/13、Ubuntu 24.04。顺序：**安装依赖 → SuRelay 配节点 → BBR / TCP 调优 → NQ / TQ 测试**。

## 0  安装基础工具

使用 root 登录；普通用户可执行 `su -s /bin/sh - root` 切换（需 root 密码），不依赖 `sudo` 或已安装的 Bash。

```sh
apt-get update
apt-get install -y bash curl wget ca-certificates git iproute2 procps kmod
```

装好后，**单独执行下面一行，再运行后续脚本**；`sh` 不支持 `<(...)` 语法。

```sh
exec bash
```

其中 `procps` 提供 `sysctl`，`iproute2` 提供 `ip/tc`，`kmod` 提供 `modprobe/modinfo`。其他依赖按各脚本提示安装。

## 1  SuRelay 配置节点

```bash
bash <(wget -qO- https://raw.githubusercontent.com/suyi-92/SuRelay/main/install.sh)
```

1. 按向导填写 IP、端口和 SSH 公钥；无域名可关闭 CF 域名模式，仅保留 VLESS Reality。
2. 在云安全组放行实际的 SSH、VLESS TCP 端口；使用无 CF 在线订阅时，再放行订阅 HTTP 端口。
3. 保留当前 SSH 窗口，另开终端验证公钥登录成功后再继续；将输出的 `vless://` 链接或订阅导入客户端。

```bash
sr          # 管理菜单
sr status   # 查看状态
```

[SuRelay 项目说明](https://github.com/suyi-92/SuRelay)

## 2  BBR 与 TCP 调优

### 2.1 BBRv3（可选，先于 tcpfit）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/byJoey/Actions-bbr-v3/main/install.sh)
```

选择 **「安装或更新 BBR v3 最新版」→「BBR v3 标准版」**，安装成功后按提示重启，再连接 VPS。此操作会换内核；Docker / LXC / OpenVZ 跳过。

只需启用当前内核的 BBR，可直接运行下一节 tcpfit。搭配使用时，不要在 tcpfit 之后再次运行 BBR 脚本的队列切换或 TCP 优化。

[BBRv3 项目说明](https://github.com/byJoey/Actions-bbr-v3)

### 2.2 tcpfit

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Kylin010/tcpfit/main/tcpfit.sh)
```

选择 **「1. 一键调优」**：

- **带宽**：500 Mbps 填 `500`，1 Gbps 填 `1000`；未知可回车实测。
- **测速对端**：回车使用公共节点。
- **用途**：选择「1. 代理 / 加速」，确认预计流量后开始。

流量有限可选「2. 基础调优」，手填套餐带宽。带宽填 `0` 仅跳过整形，仍可能测速。

```bash
tcpfit status       # 查看状态
tcpfit shape --off  # 仅撤销整形
tcpfit rollback     # 回滚 tcpfit 参数，不卸载 BBRv3 内核
```

[tcpfit 介绍帖](https://www.nodeseek.com/post-865242-1) · [项目说明](https://github.com/Kylin010/tcpfit)

## 3  NQ / TQ 测试

### NQ

```bash
bash <(curl -sL https://run.NodeQuality.com)
```

可在命令末尾追加 `-4` / `-6`，选择 IPv4 / IPv6 测试。

[NQ 介绍帖](https://www.nodeseek.com/post-297125-1) · [项目说明](https://github.com/LloydAsp/NodeQuality)

### TQ

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh) --all
```

`--all` 包含测速，会消耗流量。可将它替换为下列参数，按需组合：

| 参数 | 用途 |
| --- | --- |
| 不加参数 | 默认三网质量检测 |
| `-v4` / `-v6` | 只测 IPv4 / IPv6 |
| `-bj` / `-sh` / `-gd` | 只测北京 / 上海 / 广东 |
| `--speedtest` | 质量检测后追加单线程测速 |
| `--only-speedtest` | 仅单线程测速 |
| `--no-rank-upload` | 关闭报告上传与排名，可与 `--all` 组合 |
| `--help` | 查看完整参数 |

[TQ 介绍帖](https://www.nodeseek.com/post-809052-1) · [项目说明](https://github.com/ibsgss/TcpQuality)

> 按 2026-11-06 的项目文档与源码整理；菜单、参数以当前脚本为准。
