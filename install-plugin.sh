#!/usr/bin/env bash
set -euo pipefail

plugin_name="RojoConvert.rbxmx"

find_rojo() {
	if [ -x "${HOME}/.rokit/bin/rojo" ]; then
		printf '%s\n' "${HOME}/.rokit/bin/rojo"
		return
	fi

	if command -v rojo >/dev/null 2>&1; then
		command -v rojo
		return
	fi

	echo "Could not find Rojo. Install it with Rokit or add it to PATH." >&2
	exit 1
}

build_plugin() {
	local rojo_bin
	rojo_bin="$(find_rojo)"
	"$rojo_bin" build plugin.project.json -o "$plugin_name"
}

install_macos() {
	local plugin_dir
	local installed_plugins_dir=""

	plugin_dir="${HOME}/Documents/Roblox/Plugins"

	while IFS= read -r candidate; do
		installed_plugins_dir="$candidate"
		break
	done < <(find "${HOME}/Documents/Roblox" -maxdepth 3 -type d -name InstalledPlugins 2>/dev/null | sort)

	mkdir -p "$plugin_dir"
	cp "$plugin_name" "$plugin_dir/$plugin_name"
	echo "Installed $plugin_name to $plugin_dir/$plugin_name"

	if [ -n "$installed_plugins_dir" ]; then
		mkdir -p "$installed_plugins_dir"
		cp "$plugin_name" "$installed_plugins_dir/$plugin_name"
		echo "Copied $plugin_name to $installed_plugins_dir/$plugin_name"
	fi
}

install_windows_wsl() {
	local plugin_root
	local plugin_dir

	plugin_root="$(find /mnt/c/Users -maxdepth 4 -type d -path '*/AppData/Local/Roblox' | sort | head -n 1)"

	if [ -z "$plugin_root" ]; then
		echo "Could not locate a Windows Roblox install under /mnt/c/Users" >&2
		exit 1
	fi

	plugin_dir="$plugin_root/Plugins"
	mkdir -p "$plugin_dir"
	cp "$plugin_name" "$plugin_dir/$plugin_name"
	echo "Installed $plugin_name to $plugin_dir/$plugin_name"
}

main() {
	build_plugin

	case "$(uname -s)" in
		Darwin)
			install_macos
			;;
		Linux)
			if [ -d /mnt/c/Users ]; then
				install_windows_wsl
			else
				echo "Linux install is only supported for WSL right now." >&2
				exit 1
			fi
			;;
		*)
			echo "Unsupported platform: $(uname -s)" >&2
			exit 1
			;;
	esac
}

main "$@"
