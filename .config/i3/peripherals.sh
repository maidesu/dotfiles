#!/bin/sh
set -u
#set -x

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*"
}

wait_xrandr_output() {
  out="$1"
  i=0
  while ! xrandr --query 2>/dev/null | grep -q "^${out} connected"; do
    if [ "$i" -ge 100 ]; then
      log "wait_xrandr_output: $out timed out after ${i} loops (~$((i * 50))ms)"
      return 1
    fi
    i=$((i+1))
    sleep 0.05
  done
  log "wait_xrandr_output: $out ready after ${i} loops (~$((i * 50))ms)"
}

# wait until any of the named devices appears; print the first one found
wait_xinput_device() {
  i=0
  while :; do
    names=$(xinput list --name-only 2>/dev/null)
    for name in "$@"; do
      if printf '%s\n' "$names" | grep -Fxq "$name"; then
        log "wait_xinput_device: $name ready after ${i} loops (~$((i * 50))ms)" >&2
        printf '%s\n' "$name"
        return 0
      fi
    done
    if [ "$i" -ge 100 ]; then
      log "wait_xinput_device: none of [$*] after ${i} loops (~$((i * 50))ms)" >&2
      return 1
    fi
    i=$((i+1))
    sleep 0.05
  done
}

log "waiting for outputs"
wait_xrandr_output DP-2 || true
wait_xrandr_output DP-4 || true
wait_xrandr_output DP-0 || true
wait_xrandr_output HDMI-0 || true

log "applying display layout"
xrandr \
  --output DP-2 --mode 1920x1080 --rate 144 --pos -1920x0 --rotate normal \
  --output DP-4 --primary --mode 1920x1080 --rate 720 --pos 0x0 --rotate normal \
  --output DP-0 --mode 1920x1080 --rate 279.86 --pos 1920x0 --rotate normal \
  --output HDMI-0 --mode 1920x1080 --rate 60 --pos 0x-1080 --rotate normal || true

log "applying mouse settings"
if mouse=$(wait_xinput_device "Logitech X2 SUPERSTRIKE" "Logitech PRO X2 SUPERSTRIKE"); then
  xinput set-prop "pointer:$mouse" "libinput Accel Profile Enabled" 0 1 0 || true
  xinput set-prop "pointer:$mouse" "libinput Accel Speed" 0 || true
fi

log "applying wacom settings"
wait_xinput_device "Wacom Intuos Pro S Pen stylus" >/dev/null || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" Suppress 0 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" RawSample 1 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Area 0 0 8208 4617 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Area 0 0 8208 4617 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" MapToOutput HEAD-0 || true

#wait_xinput_device "Wacom One by Wacom S Pen stylus" || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" Suppress 0 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" Suppress 0 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" RawSample 1 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" RawSample 1 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" Area 0 0 4104 2309 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" Area 0 0 4104 2309 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" MapToOutput HEAD-0 || true

log "applying gpu settings"
nvidia-settings --load-config-only || true

log "applying wallpapers"
if [ -e "$HOME/.fehbg-off" ]; then
    hsetroot -solid '#000000' 2>/dev/null || xsetroot -solid black || true
else
    feh --bg-fill --randomize "$HOME"/.local/share/backgrounds/* || true
fi
