# OpsKit

轻量、可直接使用的 macOS / Linux 开发与运维工具箱。保留通用工具；对特定服务器的防火墙配置单独标注风险。

## 快速使用

克隆仓库后无需统一安装：

| 工具 | 解决的问题 | 平台 |
| --- | --- | --- |
| [tunnels-status.py](./tunnels-status.py) | 查看本机运行中的 Secure MCP Tunnel：PID、Tunnel ID、目标 MCP URL、健康端口、控制面状态 | macOS |
| [watchit.sh](./watchit.sh) | 等待一个进程退出，再安全执行下一条命令 | macOS / Linux |
| [ipeye.sh](./ipeye.sh) | 记录本机局域网 IPv4，变化时输出或选择性邮件提醒 | macOS / Linux |
| [opencv.sh](./opencv.sh) | 用 pkg-config 编译单文件 OpenCV C/C++ 示例 | macOS / Linux |
| [setup_one_arm_nat_and_portmap.sh](./setup_one_arm_nat_and_portmap.sh) | 专用 Ubuntu 单臂网关的 NAT / 端口映射 | **专用环境，谨慎执行** |

### 查看 Tunnel 状态

```bash
python3 tunnels-status.py           # 根据终端宽度自适应
python3 tunnels-status.py --wide    # 全部列横向展示
python3 tunnels-status.py --compact # URL 独占一行
python3 tunnels-status.py --json    # 供程序调用
```

依赖 Python 3、macOS `ps`/`lsof`。如果 tunnel-client 的 Profile 使用真正的 YAML 语法，需要可选的 PyYAML；JSON 格式无需第三方模块。只查询本机健康接口，不打印 API Key。**Ready 并不等于 MCP 下游完成 OAuth 或工具调用。**

### 等待进程结束

```bash
bash watchit.sh 12345 python3 train.py
bash watchit.sh --interval 5 12345 bash -lc 'echo finished && date'
```

`PID` 必须在运行时已存在。命令及参数按原样传递，不使用 `eval`；若需要 shell 管道或复合命令，请显式通过 `bash -lc`。旧版 `watchit.sh PID "python train.py"` 的字符串调用形式需相应调整。

### 监测局域网 IP 变化

```bash
bash ipeye.sh
bash ipeye.sh --email admin@example.com
bash ipeye.sh --state-file /tmp/lan-ip --ip 192.0.2.1  # 仅用于验证
```

首次运行仅记录基准 IP，之后变化会输出 `Changed`；默认**不发送邮件**。邮件是可选功能，要求系统提供正常配置的 `sendmail` 命令，且邮件发送失败时不会推进状态文件。可自行通过 cron / launchd 周期性调用；脚本本身不会创建定时任务。默认状态文件在 `~/.local/state/utiscripts/lan-ip`。

### 编译 OpenCV

```bash
bash opencv.sh demo.cpp
bash opencv.sh "src/my demo.cpp" "build/demo"
```

需要 `pkg-config` 和 OpenCV 开发库；优先寻找 `opencv4`，再回退到 `opencv`。C++ 默认使用 C++17。可通过 `CC` / `CXX` 指定编译器；输出目录需已存在。

### 专用 Ubuntu 网关

```bash
bash setup_one_arm_nat_and_portmap.sh --dry-run  # 只展示配置，无任何修改
bash setup_one_arm_nat_and_portmap.sh --help
# 确认真实网卡/子网/映射、安排维护窗口后，才在目标 Ubuntu 主机执行：
sudo bash setup_one_arm_nat_and_portmap.sh --apply
```

**警告：** 此脚本保留了原有的 `eno2`、`172.16.75.0/24`、vLLM 端口映射及默认执行行为。无参数执行仍会改动 `sysctl`、`iptables`，且可能持久化规则。当前 SSH **DNAT 映射未启用**（相关代码被注释）；本机 SSH INPUT 放行是另一件事。请勿在未知服务器直接执行，无跨环境的实机验证或回滚保障。

## 验证

```bash
python3 -m unittest discover -s tests -v
```

GitHub Actions 对 macOS 和 Ubuntu 执行跨平台回归测试；防火墙脚本在测试中只运行 `--dry-run`，绝不应用规则。

## 清理记录与安全提示

2026-11 清理了旧校园网 Python 2 登录脚本、固定版本 MATLAB 启动器、旧树莓派 Wi-Fi 恢复脚本、不可配置的网段扫描器，以及重复的硬编码邮件脚本。源文件仍可在 Git 历史中找到，但**不要恢复含凭据的旧版脚本**。

历史版本曾包含硬编码密码。**删除当前文件并不能清除 Git 历史，也不能撤回被外部抓取的凭据。** 若该密码仍有效或在其他地方复用，应先轮换；如需彻底清除公开历史，请单独评估 Git 历史重写及所有克隆、缓存与协作者的影响。
