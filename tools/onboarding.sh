#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo 'Run as root'
    exit 1
fi

NEW_HOSTNAME="${1:-}"

if [ -z "$NEW_HOSTNAME" ]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

SSH_PORT='61337'
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

echo '[1/9] Configure hostname...'

hostnamectl set-hostname "$NEW_HOSTNAME"

echo '[2/9] Disable systemd-resolved...'

systemctl disable --now systemd-resolved >/dev/null 2>&1 || true

rm -f /etc/resolv.conf

cat > /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
EOF

chattr +i /etc/resolv.conf 2>/dev/null || true

echo '[3/9] Disable IPv6...'

cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system >/dev/null

echo '[4/9] Configure SSH...'

mkdir -p /etc/ssh/sshd_config.d
find /etc/ssh/sshd_config.d -type f -delete

SSHD_CONFIG='/etc/ssh/sshd_config'

sed -i '/^#\?AddressFamily/d' "$SSHD_CONFIG"
sed -i '/^#\?Port /d' "$SSHD_CONFIG"
sed -i '/^#\?PasswordAuthentication /d' "$SSHD_CONFIG"
sed -i '/^#\?PrintLastLog /d' "$SSHD_CONFIG"

cat >> "$SSHD_CONFIG" <<EOF

AddressFamily inet
Port ${SSH_PORT}
PasswordAuthentication no
PrintLastLog no
EOF

sshd -t

systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

echo '[5/9] Install packages...'

export DEBIAN_FRONTEND=noninteractive

apt -qq update >/dev/null
apt -qq install -y zsh git curl sudo figlet >/dev/null 2>&1

echo '[6/9] Configure MOTD...'

chmod -x /etc/update-motd.d/* 2>/dev/null || true

HOST_ASCII="$(figlet -f slant -w 1000 "$NEW_HOSTNAME")"

cat > /etc/motd <<EOF
${HOST_ASCII}

===============================================================================

  WARNING: Unauthorized access, hacking, or any attempt to gain access without
  permission is strictly PROHIBITED. All activity is logged. Violators will be
  prosecuted to the fullest extent of the law.

===============================================================================

EOF

echo '[7/9] Install Oh My Zsh...'

USER_HOME="$(eval echo "~${TARGET_USER}")"

sudo -u "$TARGET_USER" sh -c '
export RUNZSH=no
export CHSH=no
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh >/dev/null 2>&1
'

echo '[8/9] Configure .zshrc...'

cat > "${USER_HOME}/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"

plugins=(git)

source $ZSH/oh-my-zsh.sh

autoload -U colors && colors

PROMPT="%{$fg[green]%}%n%{$reset_color%}@%{$fg[green]%}%m%{$reset_color%}:%{$fg[blue]%}%~%{$reset_color%}# "

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
EOF

chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.zshrc"

echo '[9/9] Set zsh as default shell...'

chsh -s "$(command -v zsh)" "$TARGET_USER" >/dev/null 2>&1

echo
echo '====================================='
echo 'Configuration completed successfully'
echo '====================================='
echo "Hostname: ${NEW_HOSTNAME}"
echo "SSH port: ${SSH_PORT}"
echo 'Password authentication: disabled'
echo 'PrintLastLog: disabled'
echo 'AddressFamily: inet'
echo 'IPv6: disabled'
echo 'DNS: 1.1.1.1'
echo 'MOTD: custom'
echo 'Shell: zsh + Oh My Zsh'
echo
echo 'WARNING: Ensure SSH key authentication works before disconnecting.'
