sil()
{
    "$@" >/dev/null 2>&1 &
    disown
}

as_off()
{
    systemctl --user stop pipewire-pulse.service pipewire-pulse.socket pipewire.service pipewire.socket wireplumber.service 2>/dev/null || true
    systemctl --user mask --now pipewire-pulse.service pipewire-pulse.socket pipewire.service pipewire.socket wireplumber.service wireplumber@.service 2>/dev/null || true
}

as_on()
{
    systemctl --user unmask pipewire-pulse.service pipewire-pulse.socket pipewire.service pipewire.socket wireplumber.service wireplumber@.service 2>/dev/null || true
    systemctl --user start pipewire.socket pipewire.service wireplumber.service pipewire-pulse.socket pipewire-pulse.service 2>/dev/null || true
}


if [ -f ~/.git_functions ]; then
    . ~/.git_functions
fi
