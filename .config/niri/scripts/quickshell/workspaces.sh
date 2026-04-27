#!/usr/bin/env bash

# ============================================================================
# NIRI WORKSPACE DAEMON (translated from Hyprland workspaces.sh)
# Listens to Niri's event stream and writes workspace state JSON for TopBar
# ============================================================================

# 1. ZOMBIE PREVENTION
for pid in $(pgrep -f "quickshell/workspaces.sh"); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

cleanup() {
    pkill -P $$ 2>/dev/null
}
trap cleanup EXIT SIGTERM SIGINT

# --- Special Cleanup for Network/Bluetooth ---
BT_PID_FILE="$HOME/.cache/bt_scan_pid"
if [ -f "$BT_PID_FILE" ]; then
    kill $(cat "$BT_PID_FILE") 2>/dev/null
    rm -f "$BT_PID_FILE"
fi
(timeout 2 bluetoothctl scan off > /dev/null 2>&1) &

# Configuration
SETTINGS_FILE="$HOME/.config/niri/settings.json"
for cmd in jq niri; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf '[{"id":1,"state":"active","tooltip":"Missing %s"}]\n' "$cmd" > /tmp/qs_workspaces.json
    exit 0
  }
done

SEQ_END=$(jq -r '.workspaceCount // 8' "$SETTINGS_FILE" 2>/dev/null)
if ! [[ "$SEQ_END" =~ ^[0-9]+$ ]]; then
    SEQ_END=8
fi

print_workspaces() {
    # Get workspace data from Niri
    local ws_json
    ws_json=$(timeout 2 niri msg --json workspaces 2>/dev/null)

    if [ -z "$ws_json" ]; then return; fi

    # Generate the same JSON format that TopBar expects
    echo "$ws_json" | jq --arg end "$SEQ_END" -c '
        # Build a map of workspace name/index -> workspace data
        (map({ (.name // (.idx | tostring)): . }) | add // {}) as $ws_map
        |
        # Iterate from 1 to SEQ_END, matching named workspaces
        [range(1; ($end | tonumber) + 1)] | map(
            . as $i |
            ($i | tostring) as $name |
            (
                if ($ws_map[$name] != null and $ws_map[$name].is_focused == true) then "active"
                elif ($ws_map[$name] != null and ($ws_map[$name].active_window_id != null)) then "occupied"
                else "empty"
                end
            ) as $state |
            {
                id: $i,
                state: $state,
                tooltip: (if $ws_map[$name] != null then ($ws_map[$name].name // "Empty") else "Empty" end)
            }
        )
    ' > /tmp/qs_workspaces.tmp

    mv /tmp/qs_workspaces.tmp /tmp/qs_workspaces.json
}

# Print initial state
print_workspaces

# ============================================================================
# 2. THE EVENT LISTENER
# Listen to Niri's event stream (replaces socat on Hyprland socket)
# ============================================================================
while true; do
    niri msg --json event-stream 2>/dev/null | jq -c '.' 2>/dev/null | while read -r event; do
        # Check if it's a workspace-related event
        case "$event" in
            *"WorkspacesChanged"*|*"WorkspaceActivated"*|*"WindowOpenedOrChanged"*|*"WindowClosed"*|*"WindowFocusChanged"*)
                # Debounce: discard events arriving within 50ms
                while read -t 0.05 -r extra_event; do
                    continue
                done

                print_workspaces
                ;;
        esac
    done
    sleep 1
done
