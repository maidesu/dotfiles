l()
{
    setsid -f "$@" </dev/null >/dev/null 2>&1
}
complete -o default -F _command l

au()
{
    local sockets=(
        pipewire.socket
        pipewire-pulse.socket
    )
    local services=(
        pipewire.service
        pipewire-pulse.service
        wireplumber.service
    )
    local u en ac pid

    case $1 in
        off)
            systemctl --user mask --now \
                "${sockets[@]}" "${services[@]}" \
                2>/dev/null || true
            systemctl --user try-restart xdg-desktop-portal.service \
                2>/dev/null || true
            ;;
        on)
            systemctl --user unmask \
                "${sockets[@]}" "${services[@]}" \
                2>/dev/null || true
            systemctl --user start "${sockets[@]}" 2>/dev/null || true
            systemctl --user try-restart xdg-desktop-portal.service \
                2>/dev/null || true
            ;;
        rs)
            systemctl --user try-restart "${services[@]}" 2>/dev/null || true
            systemctl --user try-restart xdg-desktop-portal.service \
                2>/dev/null || true
            ;;
        st)
            for u in "${sockets[@]}" "${services[@]}"; do
                en="$(systemctl --user is-enabled "$u" 2>/dev/null)"
                [ -n "$en" ] || en="unknown"

                ac="$(systemctl --user is-active "$u" 2>/dev/null)"
                [ -n "$ac" ] || ac="unknown"

                pid="$(systemctl --user show "$u" -p MainPID --value 2>/dev/null)"
                if [ -z "$pid" ] || [ "$pid" = "0" ]; then
                    pid="-"
                fi

                printf "%-28s enabled=%-10s active=%-10s pid=%s\n" \
                    "$u" "$en" "$ac" "$pid"
            done
            ;;
        *)
            printf "usage: au {off|on|rs|st}\n" >&2
            return 2
            ;;
    esac

    pkill -x -SIGUSR2 i3status-rs 2>/dev/null || true
}

u()
{
    local node_major
    local status=0

    run_update()
    {
        printf '\n==> %s\n' "$*"
        "$@" || status=$?
    }

    run_update sudo apt update
    run_update sudo apt full-upgrade --auto-remove

    command -v flatpak >/dev/null 2>&1 &&
        run_update sudo flatpak update

    if ! command -v nvm >/dev/null 2>&1 &&
        [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    fi
    if command -v nvm >/dev/null 2>&1; then
        node_major="$(nvm current 2>/dev/null |
            sed -nE 's/^v([0-9]+)(\..*)?$/\1/p')"
        if [ -n "$node_major" ]; then
            run_update nvm install --default \
                --reinstall-packages-from=current "$node_major"
            run_update nvm install-latest-npm
        fi
    fi
    command -v npm >/dev/null 2>&1 &&
        run_update npm update -g

    command -v poetry >/dev/null 2>&1 &&
        run_update poetry self update

    if ! command -v rustup >/dev/null 2>&1 &&
        [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
    command -v rustup >/dev/null 2>&1 &&
        run_update rustup update

    if command -v fwupdmgr >/dev/null 2>&1; then
        run_update sudo fwupdmgr refresh
        run_update sudo fwupdmgr update
    fi

    if [ -x "$HOME/scripts/postinstall.sh" ]; then
        run_update sudo "$HOME/scripts/postinstall.sh" py
        run_update sudo "$HOME/scripts/postinstall.sh" osu
    fi

    unset -f run_update
    return "$status"
}


if [ -f ~/.git_functions ]; then
    . ~/.git_functions
fi
