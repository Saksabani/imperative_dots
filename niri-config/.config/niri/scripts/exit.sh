#!/usr/bin/env bash
# Niri exit script (replaces hyprctl dispatch exit)

systemctl --user stop graphical-session.target
systemctl --user stop graphical-session-pre.target

sleep 0.5

niri msg action quit
