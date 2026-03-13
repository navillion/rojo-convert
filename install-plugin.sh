#!/usr/bin/env bash
# This script helps install the plugin from WSL to Windows
set -euo pipefail

plugin_name="RojoConvert.rbxmx"
plugin_root="$(find /mnt/c/Users -maxdepth 4 -type d -path '*/AppData/Local/Roblox' | sort | head -n 1)"

if [ -z "$plugin_root" ]; then
	echo "Could not locate a Windows Roblox install under /mnt/c/Users" >&2
	exit 1
fi

plugin_dir="$plugin_root/Plugins"
plugin_path="$plugin_dir/$plugin_name"

rojo build plugin.project.json -o "$plugin_name"
mkdir -p "$plugin_dir"
rm -f "$plugin_path"
cp "$plugin_name" "$plugin_path"

echo "Installed $plugin_name to $plugin_path"
