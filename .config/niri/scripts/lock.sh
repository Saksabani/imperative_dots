#!/usr/bin/env bash

for cmd in quickshell; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: $cmd not found"; exit 1;
  }
done

quickshell -p ~/.config/niri/scripts/quickshell/Lock.qml

