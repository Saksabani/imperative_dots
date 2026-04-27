#!/usr/bin/env bash

# ============================================================================
# NIRI SETTINGS WATCHER
# Watches settings.json and .env for changes and applies them to the
# Niri KDL config or environment as needed.
# ============================================================================

# File paths
SETTINGS_FILE="$HOME/.config/niri/settings.json"
NIRI_CONFIG="$HOME/.config/niri/config.kdl"
WEATHER_SCRIPT="$(dirname "$0")/quickshell/calendar/weather.sh"
ENV_FILE="$(dirname "$0")/quickshell/calendar/.env"

ZSH_RC="$HOME/.zshrc"

for cmd in jq inotifywait niri; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: $cmd not found"; exit 1;
  }
done

# Ensure required files/directories exist
mkdir -p "$(dirname "$SETTINGS_FILE")"
mkdir -p "$(dirname "$ENV_FILE")"
[ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"

# Cache directory for state tracking (prevents unnecessary writes)
CACHE_DIR="$HOME/.cache/settings_watcher"
RELOAD_TOKEN="$CACHE_DIR/reload.token"
mkdir -p "$CACHE_DIR"

schedule_niri_reload() {
    local token
    token="$(date +%s%3N)"
    echo "$token" > "$RELOAD_TOKEN"

    (
        sleep 0.5
        [[ -f "$RELOAD_TOKEN" ]] || exit 0
        [[ "$(cat "$RELOAD_TOKEN" 2>/dev/null)" == "$token" ]] || exit 0
        niri msg action reload-config >/dev/null 2>&1 || true
    ) &
}

apply_general_to_config() {
    local lang="$1"
    local kb_opt="$2"
    local guide_startup="$3"
    local wp_dir="$4"
    local tmp_file
    local tmp_file2

    tmp_file="${NIRI_CONFIG}.tmp"
    tmp_file2="${NIRI_CONFIG}.tmp2"

    cp "$NIRI_CONFIG" "$tmp_file" || return 1

    if [[ -n "$lang" && "$lang" != "null" ]]; then
        sed -i -E "s|^([[:space:]]*)layout \"[^\"]*\"|\\1layout \"$lang\"|" "$tmp_file"
    fi

    if [[ -n "$kb_opt" && "$kb_opt" != "null" ]]; then
        sed -i -E "s|^([[:space:]]*)options \"[^\"]*\"|\\1options \"$kb_opt\"|" "$tmp_file"
    else
        sed -i -E "s|^([[:space:]]*)options \"[^\"]*\"|\\1options \"\"|" "$tmp_file"
    fi

    if [[ "$guide_startup" == "true" ]]; then
        sed -i -E 's|^([[:space:]]*)//[[:space:]]*spawn-sh-at-startup "~/.config/niri/scripts/qs_manager.sh toggle guide &"|\1spawn-sh-at-startup "~/.config/niri/scripts/qs_manager.sh toggle guide &"|' "$tmp_file"
    elif [[ "$guide_startup" == "false" ]]; then
        sed -i -E 's|^([[:space:]]*)spawn-sh-at-startup "~/.config/niri/scripts/qs_manager.sh toggle guide &"|\1// spawn-sh-at-startup "~/.config/niri/scripts/qs_manager.sh toggle guide &"|' "$tmp_file"
    fi

    if [[ -n "$wp_dir" && "$wp_dir" != "null" ]]; then
        if grep -qE '^([[:space:]]*)WALLPAPER_DIR "' "$tmp_file"; then
            sed -i -E "s|^([[:space:]]*)WALLPAPER_DIR \"[^\"]*\"|\\1WALLPAPER_DIR \"$wp_dir\"|" "$tmp_file"
        else
            awk -v wp="$wp_dir" '
                /^environment[[:space:]]*\{/ && !done {
                    print
                    print "    WALLPAPER_DIR \"" wp "\""
                    done=1
                    next
                }
                { print }
            ' "$tmp_file" > "$tmp_file2" && mv -f "$tmp_file2" "$tmp_file"
        fi

        [ -f "$ZSH_RC" ] && sed -i "s|^export WALLPAPER_DIR=.*|export WALLPAPER_DIR=\"$wp_dir\"|" "$ZSH_RC"
    fi

    mv -f "$tmp_file" "$NIRI_CONFIG"
}

echo "Started watching settings directories for changes..."

inotifywait -m -q --event close_write --format '%w%f' "$(dirname "$SETTINGS_FILE")" "$(dirname "$ENV_FILE")" | while read -r filepath; do

    # ---------------------------------------------------------
    # SETTINGS JSON TRIGGER
    # ---------------------------------------------------------
    if [[ "$filepath" == "$SETTINGS_FILE" ]]; then
        echo "Settings file modified. Checking for specific changes..."

        # 1. Capture current states
        NEW_GENERAL=$(jq -c '{language, kbOptions, openGuideAtStartup, wallpaperDir}' "$SETTINGS_FILE" 2>/dev/null)
        NEW_MONITORS=$(jq -c '.monitors' "$SETTINGS_FILE" 2>/dev/null)

        # 2. Update General Settings if changed
        if [[ "$NEW_GENERAL" != "$(cat "$CACHE_DIR/general" 2>/dev/null)" ]]; then
            echo "General settings changed. Applying to Niri config..."

            LANG=$(jq -r '.language // empty' "$SETTINGS_FILE")
            KB_OPT=$(jq -r '.kbOptions // empty' "$SETTINGS_FILE")
            GUIDE_STARTUP=$(jq -r '.openGuideAtStartup' "$SETTINGS_FILE")
            WP_DIR=$(jq -r '.wallpaperDir // empty' "$SETTINGS_FILE")

            if apply_general_to_config "$LANG" "$KB_OPT" "$GUIDE_STARTUP" "$WP_DIR"; then
                schedule_niri_reload
            fi

            echo "$NEW_GENERAL" > "$CACHE_DIR/general"
        fi

        # 3. Update Monitor Configuration if changed
        if [[ "$NEW_MONITORS" != "$(cat "$CACHE_DIR/monitors" 2>/dev/null)" ]]; then
            echo "Monitor config changed in settings.json."
            # Niri does NOT support hot-reloading monitor config like Hyprland.
            # The user must restart Niri or edit config.kdl manually.
            # We save the state for reference and notify the user.

            MONITOR_COUNT=$(jq '.monitors | length' "$SETTINGS_FILE" 2>/dev/null)
            if [[ "$MONITOR_COUNT" -gt 0 ]]; then
                notify-send "Monitor Config" "Monitor layout saved to settings.json. Edit config.kdl and restart Niri to apply." 2>/dev/null
            fi

            echo "$NEW_MONITORS" > "$CACHE_DIR/monitors"
        fi

    # ---------------------------------------------------------
    # .ENV WEATHER TRIGGER
    # ---------------------------------------------------------
    elif [[ "$filepath" == "$ENV_FILE" ]]; then
        echo ".env updated! Forcing weather cache refresh..."
        if [ -x "$WEATHER_SCRIPT" ]; then
            "$WEATHER_SCRIPT" --getdata &
        else
            bash "$WEATHER_SCRIPT" --getdata &
        fi
    fi
done
