l()
{
    "$@" </dev/null >/dev/null 2>&1 & disown
}
complete -o default -F _command l

lsid()
{
    setsid "$@" </dev/null >/dev/null 2>&1 &
}
complete -o default -F _command lsid

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
            ;;
        on)
            systemctl --user unmask \
                "${sockets[@]}" "${services[@]}" \
                2>/dev/null || true
            systemctl --user start "${sockets[@]}" 2>/dev/null || true
            ;;
        rs)
            systemctl --user try-restart "${services[@]}" 2>/dev/null || true
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


if [ -f ~/.git_functions ]; then
    . ~/.git_functions
fi
