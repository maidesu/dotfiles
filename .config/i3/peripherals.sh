#!/bin/sh
set -u
#set -x

wait_xrandr_output() {
  out="$1"
  i=0
  while ! xrandr --query 2>/dev/null | grep -q "^${out} connected"; do
    i=$((i+1))
    [ "$i" -gt 100 ] && return 1
    sleep 0.05
  done
}

wait_xinput_device() {
  name="$1"
  i=0
  while ! xinput list --name-only 2>/dev/null | grep -Fxq "$name"; do
    i=$((i+1))
    [ "$i" -gt 100 ] && return 1
    sleep 0.05
  done
}

# wait for outputs
wait_xrandr_output DP-2 || true
wait_xrandr_output DP-4 || true
wait_xrandr_output DP-0 || true
wait_xrandr_output HDMI-0 || true

# displays: left=DP-2@144, middle=DP-4@279.86 primary, right=DP-0@60
xrandr \
  --output DP-2 --mode 1920x1080 --rate 144 --pos -1920x0 --rotate normal \
  --output DP-4 --primary --mode 1920x1080 --rate 279.86 --pos 0x0 --rotate normal \
  --output DP-0 --mode 1920x1080 --rate 60 --pos 1920x0 --rotate normal \
  --output HDMI-0 --mode 1360x768 --rate 60 --pos 560x-768 --rotate normal || true

# mouse accel off (Logitech)
wait_xinput_device "Logitech USB Receiver" || true
xinput set-prop "Logitech USB Receiver" "libinput Accel Profile Enabled" 0 1 0 || true
xinput set-prop "Logitech USB Receiver" "libinput Accel Speed" 0 || true

# wacom raw-ish + area + map-to middle (DP-4)
wait_xinput_device "Wacom Intuos Pro S Pen stylus" || true
wait_xinput_device "Wacom Intuos Pro S Pen eraser" || true
wait_xinput_device "Wacom Intuos Pro S Pad pad" || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Suppress 0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" Suppress 0 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" RawSample 1 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" RawSample 1 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" Area 0 0 12000 6750 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" Area 0 0 12000 6750 || true

xsetwacom --set "Wacom Intuos Pro S Pen stylus" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pen eraser" MapToOutput HEAD-0 || true
xsetwacom --set "Wacom Intuos Pro S Pad pad" MapToOutput HEAD-0 || true

nvidia-settings \
  --assign SyncToVBlank=0 \
  --assign AllowVRR=0 \
  --assign GPUPowerMizerMode=1
