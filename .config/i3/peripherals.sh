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

wait_xinput_device() {
  name="$1"
  i=0
  while ! xinput list --name-only 2>/dev/null | grep -Fxq "$name"; do
    if [ "$i" -ge 100 ]; then
      log "wait_xinput_device: $name timed out after ${i} loops (~$((i * 50))ms)"
      return 1
    fi
    i=$((i+1))
    sleep 0.05
  done
  log "wait_xinput_device: $name ready after ${i} loops (~$((i * 50))ms)"
}

log "waiting for outputs"
wait_xrandr_output DP-2 || true
wait_xrandr_output DP-4 || true
wait_xrandr_output DP-0 || true
wait_xrandr_output HDMI-0 || true

log "applying display layout"
xrandr \
  --output DP-2 --mode 1920x1080 --rate 144 --pos -1920x0 --rotate normal \
  --output DP-4 --primary --mode 1920x1080 --rate 279.86 --pos 0x0 --rotate normal \
  --output DP-0 --mode 1920x1080 --rate 60 --pos 1920x0 --rotate normal \
  --output HDMI-0 --mode 1360x768 --rate 60 --pos 560x-768 --rotate normal || true

log "applying mouse settings"
wait_xinput_device "Logitech X2 SUPERSTRIKE" || true
xinput set-prop "pointer:Logitech X2 SUPERSTRIKE" "libinput Accel Profile Enabled" 0 1 0 || true
xinput set-prop "pointer:Logitech X2 SUPERSTRIKE" "libinput Accel Speed" 0 || true

log "applying wacom settings"
wait_xinput_device "Wacom Intuos Pro S Pen stylus" || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" Suppress 0 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" RawSample 1 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Area 0 0 8400 4725 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Area 0 0 8400 4725 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" MapToOutput HEAD-0 || true

#wait_xinput_device "Wacom One by Wacom S Pen stylus" || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" Suppress 0 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" Suppress 0 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" RawSample 1 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" RawSample 1 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" Area 11000 7137 15200 9500 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" Area 11000 7137 15200 9500 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" MapToOutput HEAD-0 || true

xsetwacom --set "Wacom One by Wacom S Pen stylus" Rotate half || true
xsetwacom --set "Wacom One by Wacom S Pen eraser" Rotate half || true

log "applying gpu settings"
nvidia-settings \
  --assign SyncToVBlank=0 \
  --assign AllowFlipping=1 \
  --assign GPUPowerMizerMode=1

log "applying wallpapers"
feh --bg-fill --randomize "$HOME"/.local/share/backgrounds/* || true
