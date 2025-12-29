#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root (e.g. sudo ./postinstall.sh)" >&2
    exit 1
fi


# ============================================================
# OS detection
# ============================================================
echo "=== Detecting Debian codename ==="
CODENAME=$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)
VERSION_ID=$(awk -F= '/^VERSION_ID=/{gsub(/"/,""); print $2}' /etc/os-release)
echo "Codename: $CODENAME"
echo "VERSION_ID: $VERSION_ID"


# ============================================================
# APT sources
# ============================================================
echo "=== Configuring APT sources (main + contrib + non-free + non-free-firmware) ==="
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
EOF

apt update


# ============================================================
# Packages
# ============================================================
echo "=== Installing packages ==="
apt install -y \
    firmware-misc-nonfree \
    firmware-realtek \
    linux-headers-$(uname -r) \
    build-essential \
    cmake \
    dkms \
    mokutil \
    openssl \
    ca-certificates gnupg \
    wget curl git \
    mesa-utils \
    llvm \
    vim \
    htop \
    ethtool \
    notepadqq \
    chromium


# ============================================================
# NVIDIA repo setup
# ============================================================
echo "=== Add NVIDIA repo keyring ==="
# NVIDIA publishes Debian repos under debian12/debian13 naming.
case "$VERSION_ID" in
    12) NVIDIA_DEB="debian12" ;;
    13) NVIDIA_DEB="debian13" ;;
    *)
        echo "Unsupported Debian VERSION_ID=$VERSION_ID for automatic NVIDIA repo setup." >&2
        echo "Install a newer driver via your preferred method (NVIDIA repo / backports / sid)." >&2
        exit 1
        ;;
esac

CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DEB}/x86_64/${CUDA_KEYRING_DEB}"

wget -q "$CUDA_KEYRING_URL" -O "/tmp/${CUDA_KEYRING_DEB}"
dpkg -i "/tmp/${CUDA_KEYRING_DEB}"
apt -f install -y
apt update


# ============================================================
# Realtek RTL8125: prefer r8125 over r8169
# ============================================================
echo "=== Install r8125-dkms ==="
apt install -y r8125-dkms


# ============================================================
# NVIDIA driver install
# ============================================================
echo "=== NVIDIA driver (Open kernel modules) ==="
apt install -y nvidia-open


# ============================================================
# Kernel module configuration
# ============================================================
echo "=== Blacklist r8169 ==="
cat >/etc/modprobe.d/blacklist-r8169.conf <<'EOF'
blacklist r8169
EOF

echo "=== Blacklist nouveau (avoid binding the GPU) ==="
cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

echo "=== Force nvidia-drm KMS (modeset=1) ==="
cat >/etc/modprobe.d/nvidia-kms.conf <<'EOF'
options nvidia-drm modeset=1
EOF


# ============================================================
# Disable Wake-on-LAN persistently (systemd .link)
#
# This prevents the NIC staying partially powered in S5 for WoL,
# which is what caused the dual-boot "NIC vanishes from lspci" state.
# ============================================================
echo "=== Disable Wake-on-LAN persistently via systemd .link ==="

install -d -m 0755 /etc/systemd/network

cat >/etc/systemd/network/10-disable-wol.link <<'EOF'
[Match]
Type=ether

[Link]
WakeOnLan=no
EOF

# Reload udev rules immediately; link file will apply on next reboot.
udevadm control --reload
udevadm trigger --subsystem-match=net || true


# ============================================================
# DKMS + Secure Boot MOK
# ============================================================
echo "=== Ensure DKMS builds modules for current kernel ==="
/usr/sbin/dkms autoinstall -k "$(uname -r)" || true
/usr/sbin/dkms status || true

echo "=== Rebuild initramfs for module configuration changes ==="
update-initramfs -u

echo "=== Import DKMS-generated MOK for Secure Boot ==="
if [[ -f /var/lib/dkms/mok.pub ]]; then
    echo "Found /var/lib/dkms/mok.pub, importing with mokutil..."
    mokutil --import /var/lib/dkms/mok.pub || {
        echo "mokutil import failed or is already imported."
    }
    echo
    echo ">>> On next reboot you MUST use the blue MOK manager screen to 'Enroll MOK'"
    echo ">>> and enter the password you set when mokutil prompted you."
    echo
else
    echo "No /var/lib/dkms/mok.pub found."
fi


# ============================================================
# Set display manager
# ============================================================
echo "=== Force GDM to use Xorg (WaylandEnable=false) ==="
if [[ -f /etc/gdm3/daemon.conf ]]; then
    if grep -q '^#WaylandEnable=false' /etc/gdm3/daemon.conf; then
        sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/daemon.conf
    elif ! grep -q '^WaylandEnable=' /etc/gdm3/daemon.conf; then
        sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/daemon.conf
    fi
fi


echo "=== Summary / Next steps ==="
echo "1) Reboot."
echo "2) On the blue MOK screen, choose 'Enroll MOK' and complete it (for DKMS/NVIDIA)."
echo "3) Back in Debian, verify:"
echo "   - mokutil --sb-state  (SecureBoot enabled)"
echo "   - nvidia-smi          (driver loaded)"
echo "4) Check disks with df -h to confirm your new partition layout is sane."
echo "5) If video broken, check:"
echo "   - dmesg -T | egrep -i 'NVRM|nvidia|secure|lockdown|key' | tail -200"
echo
echo "Script finished."
