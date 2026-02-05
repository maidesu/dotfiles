#!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/postinstall.log
exec > >(tee -a "$LOG") 2>&1


die()
{
    echo "ERROR: $*" >&2
    exit 1
}

require_root()
{
    [[ $EUID -eq 0 ]] || die "Run this script as root (e.g. sudo ./postinstall.sh)."
}

detect_os()
{
    CODENAME=$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)
    VERSION_ID=$(awk -F= '/^VERSION_ID=/{gsub(/"/,""); print $2}' /etc/os-release)

    # Workaround: testing does not set this
    if [[ -z "$VERSION_ID" ]]; then
        case "$CODENAME" in
            forky) VERSION_ID="14" ;;
            duke) VERSION_ID="15" ;;
            *) die "VERSION_ID is not set properly." ;;
        esac
    fi

    echo "Codename: $CODENAME"
    echo "VERSION_ID: $VERSION_ID"
}

detect_user()
{
    TARGET_USER="${SUDO_USER:-}"
    TARGET_HOME=""
    [[ -n "$TARGET_USER" ]] || die "Run with sudo from your user (so SUDO_USER is set)."
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "Could not resolve home for $TARGET_USER"
}

run_as_user()
{
    sudo -u "$TARGET_USER" -H bash -lc "$*"
}


step_apt_sources()
{
    mv -f /etc/apt/sources.list /etc/apt/sources.list.bak || true
    touch /etc/apt/sources.list~

    cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: $CODENAME ${CODENAME}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.debian.org/debian-security/
Suites: ${CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

    apt update
    apt -y full-upgrade --auto-remove
}

step_nvidia_sources()
{
    apt install -y ca-certificates gnupg wget

    # NVIDIA publishes Debian repos under debian12/debian13 naming.
    case "$VERSION_ID" in
        12) NVIDIA_DEB="debian12" ;;
        13) NVIDIA_DEB="debian13" ;;
        14) NVIDIA_DEB="debian13" ;;  # Workaround nvidia is slow
        *) die "Unsupported Debian VERSION_ID=$VERSION_ID for automatic NVIDIA repo setup." ;;
    esac

    CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
    CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_DEB}/x86_64/${CUDA_KEYRING_DEB}"

    wget -q "$CUDA_KEYRING_URL" -O "/tmp/${CUDA_KEYRING_DEB}"
    dpkg -i "/tmp/${CUDA_KEYRING_DEB}"
    apt -f install -y
    apt update
}

step_base_packages()
{
    apt install -y linux-headers-amd64
    apt install -y "linux-headers-$(uname -r)" || true

    apt install -y \
        firmware-misc-nonfree \
        firmware-realtek \
        build-essential \
        cmake \
        pkg-config \
        ninja-build \
        meson \
        clang \
        clangd \
        lldb \
        gdb \
        openssl \
        curl \
        mesa-utils \
        llvm \
        vim \
        htop \
        ethtool \
        dos2unix \
        nftables \
        jq \
        ripgrep \
        dnsutils \
        traceroute \
        iproute2 \
        apt-file \
        apt-utils \
        xxd

#    apt install -y intel-microcode || true
    apt install -y amd64-microcode || true
}

step_r8125()
{
    apt install -y dkms mokutil
    apt install -y r8125-dkms

    /usr/sbin/dkms autoinstall -k "$(uname -r)" || die "DKMS install failed."
    /usr/sbin/dkms status || true

    cat >/etc/modprobe.d/blacklist-r8169.conf <<'EOF'
blacklist r8169
EOF
}

step_nvidia_driver()
{
    apt install -y dkms mokutil

    cat >/etc/modprobe.d/nvidia-kms.conf <<'EOF'
options nvidia-drm modeset=1
EOF

    apt install -y nvidia-open

    /usr/sbin/dkms autoinstall -k "$(uname -r)" || die "DKMS install failed."
    /usr/sbin/dkms status || true

    cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    apt full-upgrade -y --auto-remove
}

step_i3()
{
    apt install i3-wm i3status i3lock xorg xserver-xorg xterm xinput feh
}

step_disable_wol()
{
    install -d -m 0755 /etc/systemd/network

    cat >/etc/systemd/network/10-disable-wol.link <<'EOF'
[Match]
Type=ether

[Link]
WakeOnLan=no
EOF
}

step_disable_wayland()
{
    if [[ -f /etc/gdm3/daemon.conf ]]; then
        if grep -q '^#WaylandEnable=false' /etc/gdm3/daemon.conf; then
            sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/daemon.conf
        elif ! grep -q '^WaylandEnable=' /etc/gdm3/daemon.conf; then
            sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/daemon.conf
        fi
    fi
}

step_skip_grub()
{
    apt purge -y os-prober || true
    install -d -m 0755 /etc/default/grub.d
    cat >/etc/default/grub.d/01-skip-other-os.cfg <<'EOF'
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISABLE_OS_PROBER=true
EOF
}

step_mok_pub()
{
    if [[ -f /var/lib/dkms/mok.pub ]]; then
        echo "Found /var/lib/dkms/mok.pub, importing with mokutil..."
        mokutil --import /var/lib/dkms/mok.pub || {
            echo "mokutil import failed or is already imported."
        }
        echo "On next reboot: 'Enroll MOK'"
    else
        echo "No /var/lib/dkms/mok.pub found."
    fi
}

step_bash_functions()
{
    run_as_user 'grep -q "### BASH FUNCTIONS ###" "$HOME/.bashrc" 2>/dev/null || cat >>"$HOME/.bashrc" <<'"'"'EOF'"'"'
### BASH FUNCTIONS ###
if [ -f ~/.bash_functions ]; then
    . ~/.bash_functions
fi
### /BASH FUNCTIONS ###
EOF'
}

step_python()
{
    # Build deps for compiling CPython via pyenv
    apt install -y \
        curl ca-certificates \
        build-essential \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libncurses-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
        libffi-dev liblzma-dev libgdbm-dev libnss3-dev uuid-dev

    # Persist pyenv + ~/.local/bin for the target user
    run_as_user 'grep -q "### PYENV ###" "$HOME/.bashrc" 2>/dev/null || cat >>"$HOME/.bashrc" <<'"'"'EOF'"'"'
### PYENV ###
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
export PATH="$HOME/.local/bin:$PATH"
### /PYENV ###
EOF'

    run_as_user 'grep -q "### PYENV ###" "$HOME/.profile" 2>/dev/null || cat >>"$HOME/.profile" <<'"'"'EOF'"'"'
### PYENV ###
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
export PATH="$HOME/.local/bin:$PATH"
### /PYENV ###
EOF'

    # Install / update pyenv via pyenv.run (pinned), then install requested Pythons + Poetry
    local tmp="/tmp/step_python.${TARGET_USER}.$$"
    cat >"$tmp" <<'EOS'
set -euo pipefail

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# pin pyenv version
export PYENV_GIT_TAG="v2.6.17"

if [[ ! -d "$PYENV_ROOT" ]]; then
  curl -fsSL https://pyenv.run | bash
else
  # already installed: update in a controlled way
  (cd "$PYENV_ROOT" && git fetch --tags && git checkout "$PYENV_GIT_TAG") || true
fi

# Ensure pyenv is active in this shell
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Install requested Python versions (skip if already installed)
for v in 3.9.25 3.10.19 3.11.14 3.12.12 3.13.11; do
  pyenv install -s "$v"
done

# Set default (global) python
pyenv global 3.13.11
pyenv rehash

# Install Poetry using the default python
python -m pip install --upgrade pip setuptools wheel
curl -sSL https://install.python-poetry.org | python -

# Sanity prints
python --version
poetry --version
EOS

    chmod 0755 "$tmp"
    run_as_user "bash '$tmp'"
    rm -f "$tmp"
}

step_docker()
{
    local docker_codename="$CODENAME"
    case "$docker_codename" in
        forky|duke) docker_codename="trixie" ;;  # Workaround: docker codename is behind
    esac

    apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $docker_codename stable
EOF

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker || true

    groupadd docker 2>/dev/null || true
    usermod -aG docker "$TARGET_USER" || true
}

step_vscodium()
{
    apt install -y ca-certificates curl gnupg

    # Keyring
    local keyring="/usr/share/keyrings/vscodium-archive-keyring.gpg"
    local key_url="https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"

    curl -fsSL "$key_url" | gpg --dearmor -o "$keyring"
    chmod 0644 "$keyring"

    # Source list
    cat >/etc/apt/sources.list.d/vscodium.list <<'EOF'
deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main
EOF

    apt update
    apt install -y codium
}

step_app_packages()
{
    apt install -y \
        fastfetch \
        nvidia-cuda-toolkit \
        alsa-utils \
        alsa-tools \
        ffmpeg \
        mpv \
        yt-dlp \
        baobab \
        gimp \
        notepadqq \
        chromium \
        maim \
        slop \
        xclip

    dpkg --add-architecture i386 || true
    apt update
    apt install -y nvidia-driver-libs:i386 steam-installer steam-devices
}

step_deb_packages()
{
    apt install -y ca-certificates curl

    # Discord
    local discord_url="https://discord.com/api/download?platform=linux&format=deb"
    local discord_deb="/tmp/discord.deb"
    curl -fL --retry 3 --retry-delay 1 "$discord_url" -o "$discord_deb"
    apt install -y "$discord_deb"
    rm -f "$discord_deb"
}

step_appimages()
{
    apt install -y ca-certificates curl

    local bin_dir="/usr/local/bin"
    local opt_dir="/opt"

    # Chatterino
    local chatterino_url="https://chatterino.fra1.digitaloceanspaces.com/bin/2.5.4/Chatterino-x86_64.AppImage"
    local chatterino_tmpdir
    chatterino_tmpdir="$(mktemp -d)"
    local chatterino_appimage="$chatterino_tmpdir/chatterino.AppImage"
    local chatterino_optdir="$opt_dir/chatterino"
    local chatterino_wrapper="$bin_dir/chatterino"

    curl -fL --retry 3 --retry-delay 1 "$chatterino_url" -o "$chatterino_appimage"
    chmod +x "$chatterino_appimage"

    ( cd "$chatterino_tmpdir" && ./chatterino.AppImage --appimage-extract >/dev/null )

    rm -rf "$chatterino_optdir"
    mv "$chatterino_tmpdir/squashfs-root" "$chatterino_optdir"
    chmod +x "$chatterino_optdir/AppRun"

    cat >"$chatterino_wrapper" <<'EOF'
#!/usr/bin/env bash
exec /opt/chatterino/AppRun "$@"
EOF
    chmod 0755 "$chatterino_wrapper"

    rm -rf "$chatterino_tmpdir"


    # osu!
    local osu_url
    osu_url="$(
        curl -fsSL https://api.github.com/repos/ppy/osu/releases \
        | jq -r '
            map(select(.prerelease == true))
            | sort_by(.published_at)
            | last
            | .assets[]
            | select(.name | test("AppImage$"))
            | .browser_download_url
        ' 2>/dev/null
    )"

    if [[ -z "$osu_url" || "$osu_url" == "null" ]]; then
        osu_url="https://github.com/ppy/osu/releases/latest/download/osu.AppImage"
    fi

    local osu_tmpdir
    osu_tmpdir="$(mktemp -d)"
    local osu_appimage="$osu_tmpdir/osu.AppImage"
    local osu_optdir="$opt_dir/osu"
    local osu_wrapper="$bin_dir/osu"

    curl -fL --retry 3 --retry-delay 1 "$osu_url" -o "$osu_appimage"
    chmod +x "$osu_appimage"

    ( cd "$osu_tmpdir" && ./osu.AppImage --appimage-extract >/dev/null )

    rm -rf "$osu_optdir"
    mv "$osu_tmpdir/squashfs-root" "$osu_optdir"
    chmod +x "$osu_optdir/AppRun"

    cat >"$osu_wrapper" <<'EOF'
#!/usr/bin/env bash
exec /opt/osu/AppRun "$@"
EOF
    chmod 0755 "$osu_wrapper"

    rm -rf "$osu_tmpdir"
}

step_osu_game()
{
    apt install -y gamemode

    if getent group gamemode >/dev/null; then
        usermod -aG gamemode "$TARGET_USER"
    fi

    run_as_user 'mkdir -p "$HOME/.local/bin"

cat >"$HOME/.local/bin/osu2" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
export __GL_SYNC_TO_VBLANK=0
export __GL_GSYNC_ALLOWED=0
export __GL_VRR_ALLOWED=0
export __GL_MaxFramesAllowed=1
export __GL_YIELD="USLEEP"
export SDL_VIDEODRIVER=x11

exec gamemoderun osu "$@" >/dev/null 2>&1
EOF

chmod 0755 "$HOME/.local/bin/osu2"
'
}

finalize()
{
    systemctl daemon-reload || true

    udevadm control --reload || true
    udevadm trigger || true
    udevadm trigger --subsystem-match=net || true

    depmod -a || true

    update-initramfs -u -k all

    update-grub
}


main()
{
    require_root
    detect_os
    detect_user

    step_apt_sources
    step_nvidia_sources

    step_base_packages

    #step_r8125
    step_disable_wol

    #step_disable_wayland
    #step_i3

    step_skip_grub

    step_nvidia_driver
    step_mok_pub

    step_bash_functions

    step_python
    step_docker

    step_vscodium

    step_app_packages
    step_deb_packages
    step_appimages

    step_osu_game

    finalize
}

main "$@"
