#!/bin/bash
set -e

echo "[🔥] SSH UNIVERSAL (NO FIREWALL)"

SSHD_DIR="/etc/ssh/sshd_config.d"
CUSTOM_CONF="$SSHD_DIR/99-universal.conf"

# ================================
# Detect package manager + SFTP
# ================================
if command -v apt >/dev/null 2>&1; then
    INSTALL="apt update && apt install -y openssh-server"
    SFTP="/usr/lib/openssh/sftp-server"
elif command -v dnf >/dev/null 2>&1; then
    INSTALL="dnf install -y openssh-server"
    SFTP="/usr/libexec/openssh/sftp-server"
elif command -v yum >/dev/null 2>&1; then
    INSTALL="yum install -y openssh-server"
    SFTP="/usr/libexec/openssh/sftp-server"
elif command -v pacman >/dev/null 2>&1; then
    INSTALL="pacman -Sy --noconfirm openssh"
    SFTP="/usr/lib/ssh/sftp-server"
elif command -v apk >/dev/null 2>&1; then
    INSTALL="apk add openssh"
    SFTP="/usr/lib/ssh/sftp-server"
else
    INSTALL=""
    SFTP="/usr/lib/openssh/sftp-server"
fi

# ================================
# Install SSH if missing
# ================================
if ! command -v sshd >/dev/null 2>&1; then
    echo "[*] Installing OpenSSH..."
    eval "$INSTALL" || echo "[!] Install failed"
fi

# ================================
# Ensure config dir exists
# ================================
mkdir -p "$SSHD_DIR"

# ================================
# Disable cloud-init override
# ================================
if [ -f "/etc/ssh/sshd_config.d/50-cloud-init.conf" ]; then
    echo "[*] Disable cloud-init override"
    mv /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/50-cloud-init.conf.bak || true
fi

# ================================
# Write universal config
# ================================
echo "[*] Writing SSH config..."

cat > "$CUSTOM_CONF" <<EOF
# === UNIVERSAL SSH CONFIG (NO FIREWALL) ===

Port 22

PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes

KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

Subsystem sftp $SFTP
EOF

chmod 644 "$CUSTOM_CONF"

# ================================
# Ensure root password exists
# ================================
if passwd -S root 2>/dev/null | grep -q "NP"; then
    echo "[!] Root no password → set: root"
    echo "root:root" | chpasswd
fi

# ================================
# Fix permission
# ================================
chmod 700 /root 2>/dev/null || true

# ================================
# Restart SSH (ALL DISTRO SAFE)
# ================================
echo "[*] Restarting SSH..."

if command -v systemctl >/dev/null 2>&1; then

    # Stop socket (Debian 12+)
    systemctl stop ssh.socket 2>/dev/null || true

    systemctl unmask ssh 2>/dev/null || true
    systemctl unmask sshd 2>/dev/null || true

    if systemctl list-unit-files | grep -q '^sshd.service'; then
        SVC="sshd"
    else
        SVC="ssh"
    fi

    systemctl daemon-reexec || true
    systemctl enable $SVC || true
    systemctl restart $SVC

elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart || rc-service ssh restart || true

else
    /etc/init.d/sshd restart || /etc/init.d/ssh restart || true
fi

# ================================
# Verification
# ================================
echo "[*] Testing config..."

if sshd -t; then
    echo "[✓] Config OK"
else
    echo "[✗] Config ERROR"
fi

echo "[*] Active config:"
sshd -T | grep -E 'permitrootlogin|passwordauthentication|usepam'

echo "[🔥] DONE - SSH READY (NO FIREWALL MODE)"
