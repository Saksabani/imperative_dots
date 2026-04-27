#!/usr/bin/env bash
# Niri keyboard layout fetcher (replaces hyprctl devices -j)
if ! command -v jq >/dev/null 2>&1 || ! command -v niri >/dev/null 2>&1; then
	echo "US"
	exit 0
fi

layout=$(niri msg --json keyboard-layouts 2>/dev/null | jq -r '.names[.current_idx] // empty' | head -n1)
[[ -z "$layout" || "$layout" == "null" ]] && layout="US"
echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
