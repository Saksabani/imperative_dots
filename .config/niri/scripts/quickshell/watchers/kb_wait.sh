#!/usr/bin/env bash
# Niri keyboard layout change waiter (replaces socat on Hyprland socket)

for cmd in jq niri; do
  command -v "$cmd" >/dev/null 2>&1 || { 
    echo "ERROR: $cmd not found"; exit 1; 
  }
done
PIPE="/tmp/qs_kb_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

# Listen to Niri event stream for keyboard layout changes
niri msg --json event-stream 2>/dev/null | grep --line-buffered "KeyboardLayoutsChanged" > "$PIPE" &

read -r _ < "$PIPE"
sleep 0.05
