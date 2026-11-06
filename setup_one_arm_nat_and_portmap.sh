#!/usr/bin/env bash
# setup_one_arm_nat_and_portmap.sh
# Ubuntu 20.04 | 单臂路由(eno2) + NAT + DNAT(SSH/vLLM) + FORWARD 放行
# 幂等：使用 iptables -C 检查后再添加

set -euo pipefail

# === 基本参数（按需修改） ===
IF="eno2"                       # 网关机对外/对内唯一网口
SUBNET="172.16.75.0/24"        # 内网网段
GW_IP="172.16.75.202"          # 本机内网IP（仅注释用）

# 本机（202）SSH 端口；如果不想脚本动 INPUT 规则，设为 0
LOCAL_SSH_PORT=21016

# 端口映射清单（外部端口  内网IP:内网端口）
# SSH
MAPS_SSH=(
  "21011 172.16.75.201 21016"
  "21013 172.16.75.203 21016"
  "21014 172.16.75.204 21016"
)
# vLLM
MAPS_VLLM=(
  "10001 172.16.75.201 10000"
  "10003 172.16.75.203 10000"
  "10004 172.16.75.204 10000"
)

# 是否为本机 SSH 放行 INPUT（防呆）
ALLOW_LOCAL_SSH_INPUT=1

# 是否尝试持久化（安装了 netfilter-persistent 才会保存）
PERSIST=1

say() { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m[✗] %s\033[0m\n" "$*" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_sysctl() {
  say "配置 sysctl：开启转发 & 关闭 rp_filter（单臂发夹必备）"
  sudo sed -i \
    -e 's/^#\?net\.ipv4\.ip_forward=.*/net.ipv4.ip_forward=1/' \
    -e 's/^#\?net\.ipv4\.conf\.all\.rp_filter=.*/net.ipv4.conf.all.rp_filter=0/' \
    -e "/^net\.ipv4\.conf\.${IF}\.rp_filter=/d" \
    /etc/sysctl.conf || true
  echo "net.ipv4.conf.${IF}.rp_filter=0" | sudo tee -a /etc/sysctl.conf >/dev/null
  sudo sysctl -p >/dev/null
}

iptables_add_once() {
  # $@ is the full iptables args (without sudo iptables)
  if sudo iptables -C "$@" 2>/dev/null; then
    : # exists
  else
    sudo iptables -A "$@"
  fi
}

iptables_nat_add_once() {
  # $@ is the full iptables -t nat args for -C/-A (e.g. "PREROUTING -i IF ...")
  if sudo iptables -t nat -C "$@" 2>/dev/null; then
    : # exists
  else
    sudo iptables -t nat -A "$@"
  fi
}

setup_nat_and_forward_base() {
  say "设置 NAT: MASQUERADE (o ${IF})"
  iptables_nat_add_once POSTROUTING -o "${IF}" -j MASQUERADE

  say "设置 FORWARD: 基础放行规则（内→外 NEW+回包 + 全局回包）"
  iptables_add_once FORWARD -i "${IF}" -o "${IF}" -s "${SUBNET}" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

  iptables_add_once FORWARD -i "${IF}" -o "${IF}" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
}

map_port() {
  # args: <wan_port> <dst_ip> <dst_port>
  local WAN_PORT="$1" DST_IP="$2" DST_PORT="$3"
  say "映射 ${WAN_PORT} -> ${DST_IP}:${DST_PORT}"

  # DNAT
  iptables_nat_add_once PREROUTING -i "${IF}" -p tcp --dport "${WAN_PORT}" \
    -j DNAT --to-destination "${DST_IP}:${DST_PORT}"

  # FORWARD 精确放行（外→内 NEW + 回包）
  iptables_add_once FORWARD -i "${IF}" -o "${IF}" -p tcp -d "${DST_IP}" --dport "${DST_PORT}" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
}

allow_local_ssh() {
  if (( ALLOW_LOCAL_SSH_INPUT == 1 )) && (( LOCAL_SSH_PORT > 0 )); then
    say "确保本机 SSH(${LOCAL_SSH_PORT}) 入站不受影响（INPUT 放行）"
    if ! sudo iptables -C INPUT -p tcp --dport "${LOCAL_SSH_PORT}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null; then
      sudo iptables -I INPUT 1 -p tcp --dport "${LOCAL_SSH_PORT}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
    fi
    if ! sudo iptables -C OUTPUT -p tcp --sport "${LOCAL_SSH_PORT}" -m conntrack --ctstate ESTABLISHED -j ACCEPT 2>/dev/null; then
      sudo iptables -I OUTPUT 1 -p tcp --sport "${LOCAL_SSH_PORT}" -m conntrack --ctstate ESTABLISHED -j ACCEPT
    fi
  fi
}


persist_rules() {
  if (( PERSIST == 1 )); then
    if has_cmd netfilter-persistent; then
      say "保存规则到 iptables-persistent"
      sudo netfilter-persistent save || warn "保存失败（但不影响当前生效）"
    else
      warn "未检测到 netfilter-persistent，改为保存到 /etc/iptables/rules.v4（需你自建 systemd 恢复）"
      sudo mkdir -p /etc/iptables
      sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
      warn "可参考你笔记里的 systemd iptables-restore.service 实现开机自动恢复。"
    fi
  fi
}

main() {
  [[ $EUID -eq 0 ]] || warn "提示：非 root 运行，脚本会对每条命令自动 sudo。"

  ensure_sysctl
  setup_nat_and_forward_base
  allow_local_ssh

  # say "写入 SSH 端口映射"
  # for triple in "${MAPS_SSH[@]}"; do
  #   map_port $triple
  # done

  say "写入 vLLM 端口映射"
  for triple in "${MAPS_VLLM[@]}"; do
    map_port $triple
  done

  persist_rules

  say "完成！当前配置："
  say "SSH 端口映射：未启用（main 中相关循环已注释）"
  printf "  vLLM : %s\n" "${MAPS_VLLM[@]}"
  say "测试示例：curl http://<202地址>:10001/v1/models"
}

show_plan() {
  printf 'READ ONLY: no firewall, sysctl or persistent configuration changes.\n'
  printf 'Interface: %s | Subnet: %s | Gateway: %s\n' "$IF" "$SUBNET" "$GW_IP"
  printf 'Local SSH INPUT: %s (port %s) | Persistence: %s\n' \
    "$ALLOW_LOCAL_SSH_INPUT" "$LOCAL_SSH_PORT" "$PERSIST"
  printf 'vLLM DNAT mappings (enabled by default execution):\n'
  printf '  %s\n' "${MAPS_VLLM[@]}"
  printf 'SSH DNAT mappings: disabled (not applied by main).\n'
}

case "${1:-}" in
  "")
    main ;;
  --apply)
    main ;;
  --dry-run)
    show_plan ;;
  --help|-h)
    cat <<'HELP'
Usage: setup_one_arm_nat_and_portmap.sh [--dry-run|--apply|--help]

  --dry-run  Print configured interface, subnet and active port mappings.
             Does not change the firewall, sysctl, or any files.
  --apply    Apply configured rules (same behavior as invoking without args).
  --help     Show this help.

WARNING: Intended only for the hard-coded Ubuntu one-arm gateway topology.
Running it modifies iptables/sysctl and may persist rules across reboots.
Verify the interface, subnet, port mappings and maintenance window first.
HELP
    ;;
  *)
    err "不支持的参数：$1（使用 --help 查看用法）"
    exit 2 ;;
esac
