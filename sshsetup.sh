#!/bin/bash
set -e

echo "[🔥] SSH UNIVERSAL FORCE MODE (NO FACTORY CONFIG)"

SSHD_CONFIG="/etc/ssh/sshd_config"

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
# 🔥 REMOVE semua override config
# ================================
echo "[*] Removing ALL override configs..."

rm -rf /etc/ssh/sshd_config.d 2>/dev/null || true
mkdir -p /etc/ssh/sshd_config.d

# cloud-init killer
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null || true

# ================================
# 🔥 FORCE disable factory config
# ================================
if [ -f "/usr/share/factory/etc/ssh/sshd_config" ]; then
    echo "[*] Disabling factory ssh config..."
    mv /usr/share/factory/etc/ssh/sshd_config \
       /usr/share/factory/etc/ssh/sshd_config.bak 2>/dev/null || true
fi

# ================================
# 🔥 WRITE CLEAN CONFIG (MAIN FILE)
# ================================
echo "[*] Writing clean sshd_config..."

cat > "$SSHD_CONFIG" <<EOF
# === SSH UNIVERSAL FORCE CONFIG ===

Port 22

PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes

KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

Subsystem sftp $SFTP
EOF

chmod 644 "$SSHD_CONFIG"

# ================================
# Ensure root password exists
# ================================
if passwd -S root 2>/dev/null | grep -q "NP"; then
    echo "[!] Root no password → set: root"
    echo "root:root" | chpasswd
fi

# ================================
# Fix root shell (ANTI BUG)
# ================================
usermod -s /bin/bash root 2>/dev/null || true

# ================================
# 🔥 FORCE systemd override (ANTI ALL DISTRO)
# ================================
if command -v systemctl >/dev/null 2>&1; then

    echo "[*] Creating systemd override..."

    mkdir -p /etc/systemd/system/sshd.service.d

    cat > /etc/systemd/system/sshd.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/sbin/sshd -D -f /etc/ssh/sshd_config
EOF

    # stop socket (Debian 12+)
    systemctl stop ssh.socket 2>/dev/null || true

    systemctl daemon-reexec || true
    systemctl daemon-reload

    systemctl restart sshd 2>/dev/null || systemctl restart ssh
else
    killall sshd 2>/dev/null || true
    /sbin/sshd
fi

# ================================
# VERIFY
# ================================
echo "[*] Verifying..."

/sbin/sshd -T | grep -E 'permitrootlogin|passwordauthentication|usepam'

echo "[🔥] DONE - FORCE MODE ACTIVE"
