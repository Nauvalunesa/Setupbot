#!/bin/bash
# Setup NAT otomatis untuk vmbr1 (192.168.11.1/24)
# Akan deteksi iface default gateway, lalu apply iptables rules
# By Nauval style: modular + robust

set -euo pipefail

# --- Detect default interface ---
PUB_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

if [[ -z "$PUB_IFACE" ]]; then
    echo "❌ Tidak bisa deteksi interface publik (default gateway)."
    exit 1
fi

echo "✅ Interface publik terdeteksi: $PUB_IFACE"
VM_IFACE="vmbr1"
VM_SUBNET="192.168.11.0/24"

# --- Enable IP forwarding ---
echo "🔧 Aktifkan IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- NAT outbound ---
iptables -t nat -A POSTROUTING -s $VM_SUBNET -o $PUB_IFACE -j MASQUERADE

# --- Forward rules ---
iptables -A FORWARD -i $VM_IFACE -o $PUB_IFACE -j ACCEPT
iptables -A FORWARD -i $PUB_IFACE -o $VM_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "✅ NAT & forwarding rules sudah diterapkan."

# --- Save rules (auto sf konfigurasi) ---
if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "📦 Menginstall iptables-persistent..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y iptables-persistent netfilter-persistent
fi

echo "💾 Menyimpan rules via netfilter-persistent..."
netfilter-persistent save

echo "🎉 Selesai. VM/LXC di $VM_IFACE ($VM_SUBNET) bisa akses internet via $PUB_IFACE."
