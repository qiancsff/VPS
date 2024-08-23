#!/bin/bash
set -euo pipefail

# 日志文件
LOG_FILE="/var/log/setup_script.log"

# 捕获错误并记录
trap 'log "Script failed"; exit 1' ERR

# 函数：记录日志
log() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# 函数：检查是否以 root 权限运行
check_root() {
  if [ "$EUID" -ne 0 ]; then
    log "Script must be run as root. Exiting."
    echo "This script must be run as root. Exiting."
    exit 1
  fi
}

# 函数：备份文件
backup_file() {
  local file="$1"
  [ -f "$file" ] && cp "$file" "$file.bak" && log "Backed up $file to $file.bak"
}

# 函数：恢复文件
restore_file() {
  local file="$1"
  [ -f "$file.bak" ] && mv "$file.bak" "$file" && log "Restored $file from $file.bak"
}

# 函数：添加 SSH 公钥
add_ssh_key() {
  local key="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAmvPv8zk2iIdd24OQgwVWIWx1aedcN0kGu9AuUu2je2ujHwPPRB4xlZatZjw0ZTSYr6cJSKbMqGElQC3HetbwvAF0u1fctZlIm5mMYbPaE5La5fz717c//oAD4GbNAvXeeM0xG+zhSPxEXqRMcM0W4L5YWLsyagTvJdBpm5XQnW9ILhBylGdbCzYbiicfiRpIzrRhOrAxlnyXFjUa3eUVESfB4k2ou7xagvxWhcH7GEe5T2BSGeaXrCSrQkL4M0JkxFegGYW3o+9XvdMArYtUtu44YYARIyPpC4gi+QHVV3ep+xEVv4K2n2v4lfpJ6/t3fDhYsbQH6VJAu7op8Lid8w=="
  local authorized_keys="/root/.ssh/authorized_keys"

  mkdir -p /root/.ssh
  if ! grep -qF "$key" "$authorized_keys"; then
    echo "$key" >> "$authorized_keys"
    chmod 600 "$authorized_keys"
    chmod 700 /root/.ssh/
    log "SSH key added to $authorized_keys"
  else
    log "SSH key already present in $authorized_keys"
  fi
}


# 函数：更新系统设置
update_system() {
  apt update -y && apt upgrade -y

  # 设置 locale 和时区
  sed -i '/zh_CN.UTF-8/s/^#//' /etc/locale.gen
  locale-gen zh_CN.UTF-8
  update-locale LANG=zh_CN.UTF-8
  timedatectl set-timezone Asia/Shanghai

  # 更新 .bashrc
  cat <<EOF >> /root/.bashrc
export LS_OPTIONS='--color=auto'
eval "\$(dircolors)"
alias ls='ls \$LS_OPTIONS'
alias ll='ls \$LS_OPTIONS -l'
alias l='ls \$LS_OPTIONS -lA'
EOF
  source /root/.bashrc
  log "System updated: locale, timezone, and bash aliases configured"
}

# 函数：安装并配置 fail2ban
configure_fail2ban() {
  if ! dpkg -l | grep -q fail2ban; then
    apt install fail2ban -y
    log "fail2ban installed"
  fi

  # 复制默认的配置文件
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

  # 修改 fail2ban.conf 文件中的 allowipv6
  sed -i 's/#allowipv6 = auto/allowipv6 = auto/' /etc/fail2ban/fail2ban.conf
  sed -i 's/backend = auto/backend = systemd/' /etc/fail2ban/jail.local
  sed -i 's/^bantime  = .*/bantime  = 30d/' /etc/fail2ban/jail.local
  sed -i 's/^findtime  = .*/findtime  = 30d/' /etc/fail2ban/jail.local
  sed -i 's/^maxretry = .*/maxretry = 1/' /etc/fail2ban/jail.local
  sed -i 's/^mode = normal/mode = aggressive/' /etc/fail2ban/jail.local
  sed -i -E 's/(banaction\s*=\s*).*$/\1nftables-multiport/' /etc/fail2ban/jail.local
  sed -i -E 's/(banaction_allports\s*=\s*).*$/\1nftables-allports/' /etc/fail2ban/jail.local
  
  systemctl restart fail2ban
  log "fail2ban configured and service restarted"
}

# 函数：启动 nftables
start_nftables() {
  systemctl start nftables
  systemctl enable nftables
  log "nftables service started and enabled"
}

# 执行脚本
log "Script started"
check_root
add_ssh_key
update_system
configure_fail2ban
start_nftables
log "Script completed"

cat << EOF >> /etc/ssh/sshd_config
Port 2233
PasswordAuthentication no
PubkeyAuthentication yes
EOF
systemctl restart ssh


