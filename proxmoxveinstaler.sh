#!/bin/bash
set -euo pipefail

echo "==========================================="
echo " 🌟 Nauval Proxmox VE Installer (FINAL SAFE) 🌟"
echo " No-Subscription + SSL + Anti-Stuck"
echo " ⚠️ NETWORK TIDAK DISENTUH"
echo "==========================================="
sleep 2

# ==============================
# ✅ VALIDASI OS (STRICT: harus Debian 12 Bookworm)
# ==============================
if [ ! -f /etc/os-release ]; then
    echo "❌ Tidak ditemukan /etc/os-release. Batalkan."
    exit 1
fi

. /etc/os-release

if [ "${ID:-}" != "debian" ]; then
    echo "❌ Script ini hanya untuk Debian (ID=$ID terdeteksi)."
    exit 1
fi

CODENAME="${VERSION_CODENAME:-}"

if [ "$CODENAME" != "bookworm" ] && [ "$CODENAME" != "trixie" ]; then
    echo "❌ Codename '${CODENAME:-tidak diketahui}' tidak didukung."
    echo "   Proxmox VE 8 -> Debian 12 (Bookworm)"
    echo "   Proxmox VE 9 -> Debian 13 (Trixie)"
    exit 1
fi

if [ "$CODENAME" = "bookworm" ]; then
    PVE_SUITE="bookworm"
    PVE_MAJOR="8"
else
    PVE_SUITE="trixie"
    PVE_MAJOR="9"
fi

echo "✅ OS terverifikasi: Debian ($CODENAME) -> akan install Proxmox VE $PVE_MAJOR"

# ==============================
# ⏳ WAIT APT LOCK
# ==============================
echo "⏳ Waiting apt lock..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 2; done

# ==============================
# 🔥 ANTI HANG IFUPDOWN2
# ==============================
echo "🛑 Disable network reload..."
ln -sf /bin/true /usr/sbin/ifreload
export IFUPDOWN_SKIP_RELOAD=1
export DEBIAN_FRONTEND=noninteractive

# ==============================
# 🧹 HAPUS ENTERPRISE REPO (SEBELUM INSTALL)
# ==============================
echo "🧹 Remove enterprise repo..."
rm -f /etc/apt/sources.list.d/pve-enterprise.list || true

# ==============================
# 📦 PASTIKAN REPO DASAR DEBIAN BOOKWORM LENGKAP
# (Ini bagian penting yang hilang di script lama — kalau sources.list
#  tidak lengkap/salah, paket dependency Proxmox seperti libaio1,
#  libfuse3-3, libgnutlsxx30, perlapi-5.36.0 tidak akan ketemu)
# ==============================
echo "📦 Menulis ulang sources.list dasar Debian ($PVE_SUITE)..."
cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s) 2>/dev/null || true

cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $PVE_SUITE main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $PVE_SUITE-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $PVE_SUITE-security main contrib non-free non-free-firmware
EOF

# ==============================
# 🚀 UPDATE SYSTEM
# ==============================
apt update
apt full-upgrade -y
apt install -y curl wget gnupg2 ca-certificates lsb-release

# ==============================
# 🌍 INFO SYSTEM
# ==============================
PUB_IP=$(curl -4 -s ifconfig.me || echo "0.0.0.0")
HOSTNAME=$(hostname)

echo "✅ Hostname: $HOSTNAME"
echo "✅ IP publik: $PUB_IP"

# ==============================
# 🔧 HOST FIX
# ==============================
sed -i "/$HOSTNAME/d" /etc/hosts
echo "$PUB_IP $HOSTNAME" >> /etc/hosts

# ==============================
# 📡 SET REPO NO-SUBSCRIPTION
# ==============================
echo "deb http://download.proxmox.com/debian/pve $PVE_SUITE pve-no-subscription" \
> /etc/apt/sources.list.d/pve-install-repo.list

if [ "$PVE_SUITE" = "trixie" ]; then
    wget -q "https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg" \
        -O "/etc/apt/trusted.gpg.d/proxmox-archive-keyring.gpg"
else
    wget -q "https://enterprise.proxmox.com/debian/proxmox-release-${PVE_SUITE}.gpg" -O- \
    | gpg --dearmor -o "/etc/apt/trusted.gpg.d/proxmox-release-${PVE_SUITE}.gpg"
fi

apt update

# ==============================
# 🖥️ INSTALL PROXMOX
# ==============================
apt install -y proxmox-default-kernel

if ! apt install -y proxmox-ve postfix open-iscsi chrony; then
    echo "⚠️ Install pertama gagal, mencoba perbaikan dependency otomatis..."
    apt --fix-broken install -y
    apt install -y proxmox-ve postfix open-iscsi chrony
fi

# ==============================
# 🔒 FIX SSL
# ==============================
apt install --reinstall -y ca-certificates
update-ca-certificates -f

# ==============================
# 🔕 REMOVE SUBSCRIPTION POPUP
# ==============================
sed -i "s/data.status !== 'Active'/false/g" \
/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js || true

systemctl restart pveproxy

# ==============================
# ⚡ OPTIONAL PERFORMANCE
# ==============================
systemctl disable --now pve-ha-lrm 2>/dev/null || true
systemctl disable --now pve-ha-crm 2>/dev/null || true

# ==============================
# 🔑 REGENERATE CERT
# ==============================
pvecm updatecerts -f || true
systemctl restart pveproxy || true

# ==============================
# 🎉 DONE
# ==============================
echo "==========================================="
echo "🎉 Proxmox VE install selesai!"
echo "🌍 Akses: https://$PUB_IP:8006"
echo "==========================================="
echo ""
echo "✅ TANPA repo enterprise"
echo "✅ Network tidak diubah"
echo "⚠️ Reboot disarankan (kernel Proxmox baru butuh reboot untuk aktif)"
