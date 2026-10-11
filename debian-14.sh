#!/bin/bash
set -Eeuo pipefail
umask 022
WORK=/root/debian14-lxc-build
CACHE=/var/lib/vz/template/cache
IMAGE=debian-14-generic-amd64-daily.tar.xz
BASE=https://cloud.debian.org/images/cloud/forky/daily/latest
FINAL="$CACHE/debian-14-standard_amd64.tar.xz"
mkdir -p "$WORK"
exec 9>"$WORK/build.lock"
flock -n 9 || { echo 'Build lain masih berjalan.' >&2; exit 1; }
[[ $(id -u) == 0 ]] || { echo 'Jalankan sebagai root.' >&2; exit 1; }
for tool in curl tar xz sha512sum sfdisk python3 losetup mount umount flock chroot mknod; do
    command -v "$tool" >/dev/null || { echo "Tool belum tersedia: $tool" >&2; exit 1; }
done
LOOP=''
MOUNT="$WORK/mounted"
cleanup() {
    local rc=$?
    trap - EXIT
    if mountpoint -q "$MOUNT"; then
        if ! umount "$MOUNT"; then
            echo 'Unmount gagal; loop device dipertahankan untuk pemeriksaan.' >&2
            exit 1
        fi
    fi
    [[ -z "$LOOP" ]] || losetup -d "$LOOP"
    if (( rc != 0 )); then echo "GAGAL (exit $rc). File kerja disimpan di $WORK." >&2; fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
download() {
    curl -4 -fL --connect-timeout 15 --speed-limit 1024 --speed-time 90 \
        --retry 4 --retry-delay 3 --retry-connrefused "$@"
}
echo "[$(date -Is)] Memeriksa checksum Debian..."
download -o "$WORK/SHA512SUMS.new" "$BASE/SHA512SUMS"
mv "$WORK/SHA512SUMS.new" "$WORK/SHA512SUMS"
SUM=$(awk -v f="$IMAGE" '$2==f || $2=="*"f {print $1; exit}' "$WORK/SHA512SUMS")
[[ "$SUM" =~ ^[a-fA-F0-9]{128}$ ]] || { echo 'Checksum image tidak ditemukan.' >&2; exit 1; }
cd "$WORK"
if ! [[ -f "$IMAGE" ]] || ! printf '%s  %s\n' "$SUM" "$IMAGE" | sha512sum -c --status; then
    echo "[$(date -Is)] Mengunduh image (IPv4, resume)..."
    download -C - -o "$IMAGE" "$BASE/$IMAGE"
fi
printf '%s  %s\n' "$SUM" "$IMAGE" | sha512sum -c -
if ! [[ -f disk.raw && -f disk.sha512 && $(cat disk.sha512) == "$SUM" ]]; then
    echo "[$(date -Is)] Mengekstrak disk.raw ke disk host, bukan tmpfs..."
    tar --sparse -xJf "$IMAGE" -O disk.raw > disk.raw.partial
    mv disk.raw.partial disk.raw
    printf '%s\n' "$SUM" > disk.sha512
fi
echo "[$(date -Is)] Membaca tabel partisi..."
sfdisk --json disk.raw > partitions.json
read -r OFFSET LENGTH < <(python3 - <<'PY'
import json
t=json.load(open('partitions.json'))['partitiontable']
types={'0fc63daf-8483-4772-8e79-3d69d8477de4','4f68bce3-e8cd-4db1-96e7-fbcaf984b709','83'}
p=max((p for p in t['partitions'] if p['type'].lower() in types), key=lambda p:p['size'])
print(p['start']*t.get('sectorsize',512), p['size']*t.get('sectorsize',512))
PY
)
[[ "$OFFSET" =~ ^[0-9]+$ && "$LENGTH" =~ ^[0-9]+$ ]]
mkdir -p "$MOUNT" "$CACHE"
LOOP=$(losetup --find --show --read-only --offset "$OFFSET" --sizelimit "$LENGTH" "$WORK/disk.raw")
mount -t ext4 -o ro,noload "$LOOP" "$MOUNT"
[[ -f "$MOUNT/etc/debian_version" && -f "$MOUNT/usr/bin/dash" ]]
echo "[$(date -Is)] Menyalin rootfs dengan kepemilikan, ACL dan xattr..."
ROOTFS=$(mktemp -d "$WORK/rootfs.XXXXXX")
tar --numeric-owner --acls --xattrs -C "$MOUNT" -cpf - . | tar --numeric-owner --acls --xattrs -C "$ROOTFS" -xpf -
umount "$MOUNT"
losetup -d "$LOOP"
LOOP=''
# Container menggunakan kernel dan mount dari host; cloud-init VM dinonaktifkan.
: > "$ROOTFS/etc/fstab"
: > "$ROOTFS/etc/machine-id"
mkdir -p "$ROOTFS/etc/cloud"
touch "$ROOTFS/etc/cloud/cloud-init.disabled"
if [[ -f "$ROOTFS/var/lib/dbus/machine-id" && ! -L "$ROOTFS/var/lib/dbus/machine-id" ]]; then
    : > "$ROOTFS/var/lib/dbus/machine-id"
fi
echo "[$(date -Is)] Menyiapkan jaringan ifupdown untuk Proxmox..."
python3 - "$ROOTFS" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
p=r/'etc/resolv.conf'
if p.is_symlink(): p.unlink()
p.write_bytes(pathlib.Path('/etc/resolv.conf').read_bytes())
PY
mkdir -p "$ROOTFS/dev"
[[ -e "$ROOTFS/dev/null" ]] || mknod -m 666 "$ROOTFS/dev/null" c 1 3
[[ -e "$ROOTFS/dev/zero" ]] || mknod -m 666 "$ROOTFS/dev/zero" c 1 5
[[ -e "$ROOTFS/dev/random" ]] || mknod -m 666 "$ROOTFS/dev/random" c 1 8
[[ -e "$ROOTFS/dev/urandom" ]] || mknod -m 666 "$ROOTFS/dev/urandom" c 1 9
POLICY="$ROOTFS/usr/sbin/policy-rc.d"
if [[ -e "$POLICY" ]]; then mv "$POLICY" "$POLICY.build-backup"; fi
printf '#!/bin/sh\nexit 101\n' > "$POLICY"
chmod 755 "$POLICY"
chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true update
chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends ifupdown dhcpcd-base
chroot "$ROOTFS" apt-get clean
if [[ -e "$POLICY.build-backup" ]]; then
    mv "$POLICY.build-backup" "$POLICY"
else
    python3 - "$POLICY" <<'PY'
import pathlib,sys
pathlib.Path(sys.argv[1]).unlink()
PY
fi
mkdir -p "$ROOTFS/etc/network"
printf 'auto lo\niface lo inet loopback\n' > "$ROOTFS/etc/network/interfaces"
[[ -x "$ROOTFS/usr/sbin/ifup" ]]
echo "[$(date -Is)] Membuat template xz (2 thread, level 1)..."
OUTPUT=$(mktemp "$CACHE/.debian14.XXXXXX.tar.xz")
XZ_OPT='-T2 -1' tar --numeric-owner --acls --xattrs \
    --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./run/*' \
    --exclude='./tmp/*' --exclude='./etc/ssh/ssh_host_*' \
    -C "$ROOTFS" -cJf "$OUTPUT" .
xz -t "$OUTPUT"
tar -tJf "$OUTPUT" > "$WORK/template-files.txt"
grep -qx './etc/debian_version' "$WORK/template-files.txt"
grep -qx './usr/bin/dash' "$WORK/template-files.txt"
if [[ -e "$FINAL" ]]; then cp -a "$FINAL" "$FINAL.backup.$(date +%s)"; fi
mv "$OUTPUT" "$FINAL"
chmod 644 "$FINAL"
sha512sum "$FINAL" > "$WORK/template.sha512"
echo "[$(date -Is)] BERHASIL: $FINAL"
ls -lh "$FINAL"
