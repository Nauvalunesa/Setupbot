#!/bin/bash
set -e
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_SUFFIX="$(date +%F_%H-%M-%S)"
echo "[*] Detecting OS & package manager..."
# 1. Detect Package Manager & SFTP Path
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    SFTP_PATH="/usr/lib/openssh/sftp-server"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    SFTP_PATH="/usr/libexec/openssh/sftp-server"
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    SFTP_PATH="/usr/libexec/openssh/sftp-server"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    SFTP_PATH="/usr/lib/ssh/sftp-server"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    SFTP_PATH="/usr/lib/ssh/sftp-server"
else
    # Fallback default
    PKG_MGR="unknown"
    SFTP_PATH="/usr/lib/openssh/sftp-server"
fi
# 2. Install openssh-server if missing
if ! command -v sshd >/dev/null 2>&1; then
    echo "[*] Installing openssh-server via $PKG_MGR..."
    case $PKG_MGR in
        apt) apt update && apt install -y openssh-server ;;
        dnf) dnf install -y openssh-server ;;
        yum) yum install -y openssh-server ;;
        apk) apk add openssh ;;
        pacman) pacman -Sy --noconfirm openssh ;;
        *) echo "[!] Cannot install automatically, package manager unknown." ;;
    esac
fi
# 3. Backup sshd_config
[ -f "$SSHD_CONFIG" ] && cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.${BACKUP_SUFFIX}"
# 4. Handle Debian/Ubuntu overrides in sshd_config.d
if [ -d "/etc/ssh/sshd_config.d" ]; then
    echo "[*] Disabling sshd_config.d overrides (Debian/Ubuntu Specific)..."
    # Kita tidak hapus, tapi kita pindahkan agar tidak dibaca oleh SSH
    mkdir -p /etc/ssh/sshd_config_disabled
    mv /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config_disabled/ 2>/dev/null || true
fi
# 5. Reset and Apply Config (Clean Method)
echo "[*] Applying universal SSH configuration..."
# Ambil config asli tanpa parameter yang mau kita ubah
grep -vE "^Port|^PermitRootLogin|^PasswordAuthentication|^PubkeyAuthentication|^KbdInteractiveAuthentication|^Subsystem\s+sftp" "$SSHD_CONFIG" > "${SSHD_CONFIG}.tmp" || true
# Tambahkan pengaturan kita
cat >> "${SSHD_CONFIG}.tmp" <<EOF
# === SSH AUTO SETUP BY BOT ===
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
Subsystem sftp $SFTP_PATH
EOF
mv "${SSHD_CONFIG}.tmp" "$SSHD_CONFIG"
chmod 644 "$SSHD_CONFIG"
# 6. Restart SSH Service (Debian/Universal Smart Restart)
echo "[*] Restarting SSH service..."
if command -v systemctl >/dev/null 2>&1; then
    # Cek jika menggunakan ssh.socket (Debian 12+)
    if systemctl is-active --quiet ssh.socket; then
        systemctl stop ssh.socket || true
    fi
    # Cek nama service yang ada
    if systemctl list-unit-files | grep -q '^ssh.service'; then
        SVC="ssh"
    else
        SVC="sshd"
    fi
    systemctl unmask $SVC || true
    systemctl enable $SVC || true
    systemctl restart $SVC
elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart || rc-service ssh restart || true
else
    /etc/init.d/ssh restart || /etc/init.d/sshd restart || true
fi
# 7. Verification
echo "[*] Result:"
sshd -t && echo "Config OK" || echo "Config Error"
grep -iE 'permitrootlogin|passwordauthentication' "$SSHD_CONFIG" | grep -v "^#"
echo "[✓] SSH setup completed."
