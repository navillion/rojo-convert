#!/usr/bin/env bash
set -euo pipefail

plugin_name="RojoConvert.rbxmx"

win_local_app_data="$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('LocalApplicationData')" | tr -d '\r')"
plugin_dir="$(wslpath -u "$win_local_app_data")/Roblox/Plugins"
plugin_path="$plugin_dir/$plugin_name"

rojo build plugin.project.json -o "$plugin_name"
mkdir -p "$plugin_dir"
rm -f "$plugin_path"
cp "$plugin_name" "$plugin_path"

echo "Installed $plugin_name to $plugin_path"
