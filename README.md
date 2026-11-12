# VPS 节点部署与调优指南

新 VPS 上手指南：基础环境安装、SuRelay 节点部署、BBR/TCP 调优及 NQ/TQ 网络测试。

适用 Debian 12/13、Ubuntu 24.04。顺序：**安装依赖 → SuRelay 配节点 → BBR / TCP 调优 → NQ / TQ 测试**。

## 0  SSH 连接与基础工具

### 重置 SSH 主机密钥记录

重装 VPS 后若提示 `REMOTE HOST IDENTIFICATION HAS CHANGED!`，先在服务商控制台核对新指纹（ED25519 可用 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` 查看）。

只重置单个端口时，在**本机终端**选一条执行，将地址和端口换成实际值。

```sh
ssh-keygen -R 203.0.113.10           # 默认端口 22
ssh-keygen -R '[203.0.113.10]:2222'  # 非默认端口
```

**重置指定主机的所有端口**

在**本机终端**执行下方命令（需 Python 3.7 或更新版本）。将 `203.0.113.10` 换成连接时使用的 IP 或主机名。若同时用 IP 和域名连接过，分别执行一次。

命令会先备份 `known_hosts`，再清理该地址在默认端口和各自定义端口的普通主机密钥记录，包含哈希记录。若配置了 `UserKnownHostsFile`，将第二个参数换成对应路径。

```sh
python3 - '203.0.113.10' "$HOME/.ssh/known_hosts" <<'PY'
import base64
import hmac
import re
import sys
import tempfile
from io import BytesIO
from pathlib import Path
from shutil import copymode

host = sys.argv[1].lower().encode()
path = Path(sys.argv[2]).expanduser().resolve()
addresses = {host} | {b"[%s]:%d" % (host, port) for port in range(1, 65536)}


def matches(address):
    if not address.startswith(b"|1|"):
        return address.lower() in addresses
    try:
        _, _, encoded_salt, encoded_hash = address.split(b"|")
        salt = base64.b64decode(encoded_salt, validate=True)
        digest = base64.b64decode(encoded_hash, validate=True)
    except ValueError:
        return False
    return len(salt) == len(digest) == 20 and any(
        hmac.digest(salt, candidate, "sha1") == digest for candidate in addresses
    )


def remove_host(line):
    field = re.match(rb"[ \t]*([^ \t\r\n]+)[ \t]", line)
    if not field or field[1].startswith((b"#", b"@")):
        return line
    kept = b",".join(name for name in field[1].split(b",") if not matches(name))
    if not kept:
        return b""
    return line[:field.start(1)] + kept + line[field.end(1):]


try:
    original = path.read_bytes()
except FileNotFoundError:
    print(f"没有找到 {path}")
    sys.exit(0)

updated = b"".join(remove_host(line) for line in BytesIO(original))
if updated == original:
    print(f"没有找到 {sys.argv[1]} 的记录")
    sys.exit(0)

with tempfile.TemporaryDirectory(dir=path.parent) as directory:
    replacement = Path(directory) / path.name
    replacement.write_bytes(updated)
    copymode(path, replacement)
    with tempfile.NamedTemporaryFile(
        dir=path.parent, prefix=f"{path.name}.bak-", delete=False
    ) as backup:
        backup.write(original)
    if path.read_bytes() != original:
        sys.exit("记录文件已变化，请重新执行")
    replacement.replace(path)

print(f"已清理 {sys.argv[1]} 的记录，备份位于 {backup.name}")
PY
```

重连时核对指纹，一致后再接受新密钥。

### 安装基础工具

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
