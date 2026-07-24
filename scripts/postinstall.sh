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
    apt install -y ca-certificates

    mv -f /etc/apt/sources.list /etc/apt/sources.list.bak || true
    touch /etc/apt/sources.list~

    cat >/etc/apt/sources.list.d/debian.sources <<EOF
Types: deb deb-src
URIs: https://deb.debian.org/debian
Suites: $CODENAME ${CODENAME}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: https://security.debian.org/debian-security
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
        btop \
        ethtool \
        dos2unix \
        7zip \
        bluez \
        fwupd \
        fwupd-amd64-signed \
        systemd-oomd \
        nftables \
        jq \
        ripgrep \
        dnsutils \
        traceroute \
        mtr-tiny \
        whois \
        nmap \
        tcpdump \
        iproute2 \
        rfkill \
        lsof \
        strace \
        iotop \
        pv \
        tree \
        ncdu \
        plocate \
        smartmontools \
        nvme-cli \
        lm-sensors \
        libsensors-dev \
        lshw \
        usbutils \
        pciutils \
        dmidecode \
        attr \
        quota \
        evtest \
        apt-file \
        apt-utils \
        xxd

    # Don't reset my Wacom tablet mid-play, thanks.
    systemctl disable --now fwupd-refresh.timer

    case "$(lscpu | awk -F: '/Vendor ID/{gsub(/^[ \t]+/, "", $2); print $2}')" in
        AuthenticAMD) apt install -y amd64-microcode || true ;;
        GenuineIntel) apt install -y intel-microcode || true ;;
        *) echo "Unknown CPU vendor; skipping CPU microcode package." ;;
    esac
}

step_gpg()
{
    apt install -y \
        gnupg \
        pinentry-curses

    run_as_user 'grep -q "### GPG TTY ###" "$HOME/.bashrc" 2>/dev/null || cat >>"$HOME/.bashrc" <<'"'"'EOF'"'"'
### GPG TTY ###
if [ -t 1 ]; then
    export GPG_TTY="$(tty)"
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
fi
### /GPG TTY ###
EOF'
}

step_keyring()
{
    apt install -y \
        gnome-keyring \
        libpam-gnome-keyring
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
    apt install -y \
        i3-wm \
        i3blocks \
        i3lock \
        xorg \
        xserver-xorg \
        xterm \
        xinput \
        feh \
        dex \
        kitty \
        arc-theme \
        thunar \
        thunar-archive-plugin \
        xarchiver \
        lightdm \
        lightdm-gtk-greeter \
        lightdm-gtk-greeter-settings \
        mate-polkit \
        pipewire-audio \
        pavucontrol \
        xdg-desktop-portal \
        xdg-desktop-portal-gtk \
        dbus-user-session

    if command -v update-alternatives >/dev/null && command -v kitty >/dev/null; then
        update-alternatives --set x-terminal-emulator /usr/bin/kitty || true
    fi

    if [[ -x /usr/sbin/lightdm ]]; then
        echo /usr/sbin/lightdm >/etc/X11/default-display-manager
        systemctl enable lightdm.service || true
    fi

    run_as_user 'cat >"$HOME/.xsession" <<'"'"'EOF'"'"'
#!/bin/sh
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
exec i3
EOF
chmod 0755 "$HOME/.xsession"

mkdir -p "$HOME/.config/kitty"
grep -q "^enable_audio_bell " "$HOME/.config/kitty/kitty.conf" 2>/dev/null \
  && sed -i "s/^enable_audio_bell .*/enable_audio_bell no/" "$HOME/.config/kitty/kitty.conf" \
  || printf "%s\n" "enable_audio_bell no" >>"$HOME/.config/kitty/kitty.conf"

if grep -q "xterm-color|\\*-256color)" "$HOME/.bashrc" 2>/dev/null; then
  sed -i "s/xterm-color|\\*-256color)/xterm-color|\\*-256color|xterm-kitty)/" "$HOME/.bashrc"
fi
'
}

step_disable_wol()
{
    install -d -m 0755 /etc/systemd/network

    cat >/etc/systemd/network/10-disable-wol.link <<'EOF'
[Match]
Type=ether

[Link]
WakeOnLan=off
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

step_power_profile()
{
    apt install -y power-profiles-daemon

    if command -v powerprofilesctl >/dev/null; then
        powerprofilesctl set performance || true
        powerprofilesctl get || true
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

step_preempt_full()
{
    install -d -m 0755 /etc/default/grub.d
    cat >/etc/default/grub.d/02-preempt-full.cfg <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT:+${GRUB_CMDLINE_LINUX_DEFAULT} }preempt=full"
EOF
}

step_peripheral_read_rules()
{
    install -d -m 0755 /etc/udev/rules.d
    cat >/etc/udev/rules.d/70-osu-kms-input.rules <<'EOF'
# Wooting 60HE v2 keyboard
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="31e3", ATTRS{idProduct}=="1342", TAG+="uaccess"

# Wooting UwU keypad
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="31e3", ATTRS{idProduct}=="1512", TAG+="uaccess"

# Logitech X2 SUPERSTRIKE mouse
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c54d", TAG+="uaccess"

# Wacom PTK-470
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="03f5", TAG+="uaccess"
SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="03f5", TAG+="uaccess"
EOF

    udevadm control --reload-rules
    udevadm trigger --action=add --subsystem-match=input
    udevadm trigger --action=add --subsystem-match=hidraw
    udevadm settle
}

step_swapfile()
{
    local swapfile="/swapfile"
    local swap_size="4G"

    if grep -q "^$swapfile[[:space:]]" /proc/swaps; then
        echo "$swapfile is already active."
    else
        if [[ -e "$swapfile" ]]; then
            [[ -f "$swapfile" && ! -L "$swapfile" ]] ||
                die "$swapfile exists but is not a regular file."
            [[ "$(blkid -p -s TYPE -o value "$swapfile" 2>/dev/null)" == "swap" ]] ||
                die "$swapfile exists but is not initialized as swap."
            chmod 0600 "$swapfile"
        else
            fallocate -l "$swap_size" "$swapfile"
            chmod 0600 "$swapfile"
            mkswap "$swapfile"
        fi

        swapon "$swapfile"
    fi

    if ! grep -Eq "^[[:space:]]*$swapfile[[:space:]]" /etc/fstab; then
        printf "%s none swap sw 0 0\n" "$swapfile" >>/etc/fstab
    fi
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

    # Persist pyenv for the target user
    run_as_user 'grep -q "### PYENV ###" "$HOME/.bashrc" 2>/dev/null || cat >>"$HOME/.bashrc" <<'"'"'EOF'"'"'
### PYENV ###
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
### /PYENV ###
EOF'

    # Install the latest stable pyenv release, then install requested Pythons + Poetry
    local tmp="/tmp/step_python.${TARGET_USER}.$$"
    cat >"$tmp" <<'EOS'
set -euo pipefail

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$HOME/.local/bin:$PATH"

latest_pyenv_tag="$(
  git ls-remote --tags https://github.com/pyenv/pyenv.git 'v*' \
    | awk '$2 !~ /\^\{\}$/ {
        sub("refs/tags/", "", $2)
        if ($2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print $2
      }' \
    | sort -V \
    | tail -n1
)"

if [[ -z "$latest_pyenv_tag" ]]; then
  echo "Could not determine the latest stable pyenv release." >&2
  exit 1
fi

if [[ ! -d "$PYENV_ROOT" ]]; then
  curl -fsSL https://pyenv.run | env PYENV_GIT_TAG="$latest_pyenv_tag" bash
fi

if [[ ! -d "$PYENV_ROOT/.git" ]]; then
  echo "$PYENV_ROOT exists but is not a Git checkout." >&2
  exit 1
fi

if [[ -n "$(git -C "$PYENV_ROOT" status --porcelain --untracked-files=no)" ]]; then
  echo "$PYENV_ROOT has local changes; refusing to update it." >&2
  exit 1
fi

current_tag="$(git -C "$PYENV_ROOT" describe --tags --exact-match 2>/dev/null || true)"
if [[ "$current_tag" != "$latest_pyenv_tag" ]]; then
  echo "Updating pyenv from ${current_tag:-unknown revision} to $latest_pyenv_tag..."
  git -C "$PYENV_ROOT" fetch --depth=1 origin tag "$latest_pyenv_tag"
  git -C "$PYENV_ROOT" checkout --detach "$latest_pyenv_tag"
else
  echo "pyenv is already at $latest_pyenv_tag."
fi

# pyenv-update only supports branch checkouts, so update plugin repositories directly.
for plugin in "$PYENV_ROOT"/plugins/*; do
  [[ -d "$plugin/.git" ]] || continue
  if [[ -n "$(git -C "$plugin" status --porcelain --untracked-files=no)" ]]; then
    echo "$plugin has local changes; refusing to update it." >&2
    exit 1
  fi

  branch="$(git -C "$plugin" symbolic-ref --quiet --short HEAD || true)"
  if [[ "$branch" != master && "$branch" != main ]]; then
    echo "$plugin is not on a supported update branch." >&2
    exit 1
  fi

  echo "Updating $plugin..."
  git -C "$plugin" fetch --tags origin "$branch"
  git -C "$plugin" merge --ff-only "origin/$branch"
done

# Ensure pyenv is active in this shell
export PATH="$PYENV_ROOT/bin:$HOME/.local/bin:$PATH"
eval "$(pyenv init -)"

# Install requested Python versions (skip if already installed)
available_versions="$(pyenv install --list | sed 's/^[[:space:]]*//')"

for minor in 3.10 3.11 3.12 3.13 3.14; do
  latest="$(
    printf '%s\n' "$available_versions" \
      | grep -E "^${minor}\.[0-9]+$" \
      | sort -V \
      | tail -n1
  )"

  if [ -z "$latest" ]; then
    echo "No installable version found for Python $minor" >&2
    exit 1
  fi

  echo "Installing $latest"
  pyenv install -s "$latest"
done

# Set default (global) python
default_minor="3.14"
default="$(
  printf '%s\n' "$available_versions" \
    | grep -E "^${default_minor}\.[0-9]+$" \
    | sort -V \
    | tail -n1
)"
pyenv global "$default"
pyenv rehash

# Install or update Poetry using the default python
python -m pip install --upgrade pip setuptools wheel
if ! command -v poetry >/dev/null 2>&1; then
  curl -sSL https://install.python-poetry.org | python -
fi
poetry self update --no-interaction
pyenv rehash

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
deb [arch=amd64 signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main
EOF

    apt update
    apt install -y codium
}

step_app_packages()
{
    apt install -y \
        fastfetch \
        alsa-utils \
        alsa-tools \
        ffmpeg \
        mpv \
        yt-dlp \
        gimp \
        notepadqq \
        chromium \
        maim \
        xclip
}

step_steam()
{
    dpkg --add-architecture i386 || true
    apt update

    apt install -y nvidia-driver-libs:i386 steam-installer steam-devices
}

step_flatpak()
{
    flatpak_run_wrapper()
    {
        flatpak install -y flathub "$1"

        cat >"$2" <<EOF
#!/bin/sh
exec flatpak run "$1" "\$@"
EOF
        chmod 0755 "$2"
    }

    apt install -y flatpak

    local bin_dir="/usr/local/bin"
    install -d -m 0755 "$bin_dir"

    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    flatpak_run_wrapper com.chatterino.chatterino "$bin_dir/chatterino"
    flatpak_run_wrapper com.discordapp.Discord "$bin_dir/discord"

    unset -f flatpak_run_wrapper
}

step_appimages()
{
    apt install -y ca-certificates curl jq

    local bin_dir="/usr/local/bin"
    local opt_dir="/opt"
    install -d -m 0755 "$bin_dir" "$opt_dir"

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

    cat >"$osu_wrapper" <<EOF
#!/usr/bin/env bash
exec "$osu_optdir/AppRun" "\$@"
EOF
    chmod 0755 "$osu_wrapper"

    rm -rf "$osu_tmpdir"
}

step_gamemode()
{
    apt install -y gamemode

    if getent group gamemode >/dev/null; then
        usermod -aG gamemode "$TARGET_USER"
    fi

    run_as_user 'mkdir -p "$HOME/.local/bin"

cat >"$HOME/.local/bin/osu" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
export OSU_DISABLE_ERROR_REPORTING=1

export SDL_VIDEODRIVER=x11
export SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR=1

unset SDL_IM_MODULE
unset GTK_IM_MODULE
unset QT_IM_MODULE
unset CLUTTER_IM_MODULE
unset XMODIFIERS

export SDL_PEN_MOUSE_EVENTS=1
export SDL_PEN_TOUCH_EVENTS=0

export SDL_AUDIODRIVER=alsa
#export MAI_ALSA_PCM=osu
export MAI_ALSA_PCM=hw_board
export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-16
#export MAI_ALSA_PCM=hw_e30
#export OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-64

export __GL_SYNC_TO_VBLANK=0
export __GL_GSYNC_ALLOWED=0
export __GL_VRR_ALLOWED=0
export __GL_MaxFramesAllowed=1
export __GL_YIELD=NOTHING
export __GL_THREADED_OPTIMIZATIONS=0

exec gamemoderun /usr/local/bin/osu "$@"
EOF

chmod 0755 "$HOME/.local/bin/osu"
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
    local preset="${1:-default}"

    require_root
    detect_os
    detect_user

    case "$preset" in
        default)
            step_apt_sources
            step_nvidia_sources

            step_base_packages
            step_gpg
            step_keyring

            step_swapfile

            step_disable_wol

            step_disable_wayland
            step_power_profile
            step_i3

            step_skip_grub
            step_preempt_full

            step_nvidia_driver
            step_mok_pub

            step_bash_functions

            step_python
            step_docker

            step_vscodium

            step_app_packages
            step_steam
            step_flatpak
            step_appimages

            step_gamemode

            finalize
            ;;
        all)
            step_apt_sources
            step_nvidia_sources

            step_base_packages
            step_gpg
            step_keyring

            step_swapfile

            step_r8125
            step_disable_wol

            step_disable_wayland
            step_power_profile
            step_i3

            step_skip_grub
            step_preempt_full

            step_peripheral_read_rules

            step_nvidia_driver
            step_mok_pub

            step_bash_functions

            step_python
            step_docker

            step_vscodium

            step_app_packages
            step_steam
            step_flatpak
            step_appimages

            step_gamemode

            finalize
            ;;
        osu)
            step_appimages
            ;;
        py)
            step_python
            ;;
        *)
            die "Unknown preset '$preset'. Use: default, all, osu, py."
            ;;
    esac
}

main "$@"
