# Rojo-convert

`Rojo-convert` is a Roblox Studio plugin plus a small localhost export service. The plugin serializes the current Studio selection, posts it to `127.0.0.1`, and the exporter writes a Rojo-compatible file tree on disk.

That split is intentional: Roblox plugins can use `HttpService` to talk to software on the same computer, but they do not have a supported API for arbitrary filesystem writes on their own. Rojo then consumes the written directories, `init*.lua` files, and `init.meta.json` files according to its documented sync rules.

## What it exports

- Folders and most instances as directories.
- `ModuleScript`, `LocalScript`, and `Script` as `init.lua`, `init.client.lua`, and `init.server.lua`.
- Modified instance properties, attributes, and tags into `init.meta.json`.
- A Rojo project file that mounts the exported selection back to the original Studio ancestry, such as `ReplicatedStorage.Tools`.
- If the exporter is running from a folder that already contains `default.project.json`, selections are written directly into the nearest mapped Rojo `$path` instead of `exports/`.
- MeshParts are exported with a `RojoMeshId` attribute and `RojoMeshPart` tag so the plugin can re-apply their mesh data when Rojo syncs them back into Studio.

Example export for a selected `ReplicatedStorage.Tools` folder:

```text
exports/
  Tools/
    Hammer/
      init.meta.json
      ClientBootstrap/
        init.client.lua
    Wrench/
      init.meta.json
  Tools.project.json
```
## Basic Installation
1. You can copy and paste the [RojoConvert.rbxmx](RojoConvert.rbxmx) file into your plugin directory (`C:\Users\<username>\AppData\Local\Roblox\Versions\<version>\Plugins` on Windows)
2. Start the python export server in a terminal:
  ```bash
  python3 -m exporter.server --output ./exports
  ```
3. Select any object on ROBLOX Studio and click the `Rojo-convert` button in the `Plugins` toolbar to convert it!
  - If you don't already have a Rojo project, the exporter will create a new `exports/` directory in the current working directory and place the converted files there.

## Building it yourself
1. Build the plugin model:

   ```bash
   rojo build plugin.project.json -o RojoConvert.rbxmx
   ```
2. Start the localhost export service:

   ```bash
   python3 -m exporter.server --output ./exports
   ```
3. Install `RojoConvert.rbxmx` as a Studio plugin.
4. In Studio, select one or more instances and click the `Rojo-convert` button in the `Plugins` toolbar.
5. Check Studio's Output window for the export path and generated `.project.json` file.

If the current working directory contains a Rojo project, exports target the mapped `src/...` path automatically. If no matching `$path` exists for the selected Studio ancestry, the exporter falls back to `./exports`.

## Tips
- Place the rojo-exporter service in the root of your Rojo project, so it can write directly to the mapped `$path` instead of `exports/`
     - You don't need to keep the plugin source files; they're just for building it yourself.

## Limitations

- The exporter skips property types that Rojo does not support in project/meta files, such as instance references (`Ref`), `Region3`, `Region3int16`, `SharedString`, `MaterialColors`, and `OptionalCoordinateFrame`.
- Exported properties are intentionally sparse: the plugin uses modified properties instead of dumping every default value.
- If a Roblox instance name is invalid on the local filesystem, the exporter sanitizes the directory name and preserves the original `Name` through `init.meta.json`.
- Project-aware placement merges into existing directories and overwrites the exported files it owns, but it does not delete unrelated stale siblings automatically.

## Resources

- Rojo sync details: [https://rojo.space/docs/v7/sync-details/](https://rojo.space/docs/v7/sync-details/)
- Rojo project format: [https://rojo.space/docs/v7/project-format/](https://rojo.space/docs/v7/project-format/)
- Rojo property encoding: [https://rojo.space/docs/v7/properties/](https://rojo.space/docs/v7/properties/)
- Roblox `HttpService` docs, including plugin localhost usage: [https://create.roblox.com/docs/cloud-services/http-service](https://create.roblox.com/docs/cloud-services/http-service)
