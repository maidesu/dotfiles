l()
{
    "$@" >/dev/null 2>&1 &
    disown
}
complete -o default -F _command l

as_off()
{
    systemctl --user stop \
        pipewire-pulse.socket pipewire.socket \
        pipewire-pulse.service pipewire.service \
        wireplumber.service wireplumber@.service \
        2>/dev/null || true

    systemctl --user mask --now \
        pipewire-pulse.socket pipewire.socket \
        pipewire-pulse.service pipewire.service \
        wireplumber.service wireplumber@.service \
        2>/dev/null || true
}

as_on()
{
    systemctl --user unmask \
        wireplumber.service wireplumber@.service \
        pipewire-pulse.service pipewire.service \
        pipewire-pulse.socket pipewire.socket \
        2>/dev/null || true

    systemctl --user start \
        wireplumber.service \
        pipewire.socket \
        pipewire-pulse.socket \
        2>/dev/null || true
}

as_rs()
{
    systemctl --user try-restart \
        wireplumber.service \
        pipewire.service \
        pipewire-pulse.service \
        2>/dev/null || true
}

as_st()
{
    local units=(
        pipewire.socket
        pipewire.service
        wireplumber.service
        pipewire-pulse.socket
        pipewire-pulse.service
    )

    local u en ac pid

    for u in "${units[@]}"; do
        en="$(systemctl --user is-enabled "$u" 2>/dev/null)"
        [ -n "$en" ] || en="unknown"

        ac="$(systemctl --user is-active "$u" 2>/dev/null)"
        [ -n "$ac" ] || ac="unknown"

        pid="$(systemctl --user show "$u" -p MainPID --value 2>/dev/null)"
        if [ -z "$pid" ] || [ "$pid" = "0" ]; then
            pid="-"
        fi

        printf "%-28s enabled=%-10s active=%-10s pid=%s\n" "$u" "$en" "$ac" "$pid"
    done
}


if [ -f ~/.git_functions ]; then
    . ~/.git_functions
fi
