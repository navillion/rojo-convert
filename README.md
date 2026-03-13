# Rojo-convert

`Rojo-convert` is a Roblox Studio plugin plus a small localhost export service. The plugin serializes the current Studio selection, posts it to `127.0.0.1`, and the exporter writes a Rojo-compatible file tree on disk.

That split is intentional: Roblox plugins can use `HttpService` to talk to software on the same computer, but they do not have a supported API for arbitrary filesystem writes on their own. Rojo then consumes the written directories, `init*.lua` files, and `init.meta.json` files according to its documented sync rules.

## What it exports

- Folders and general instances as directories.
- `ModuleScript`, `LocalScript`, and `Script` as `init.lua`, `init.client.lua`, and `init.server.lua`.
- Modified instance properties, attributes, and tags into `init.meta.json`.
- A Rojo project file that mounts the exported selection back to the original Studio ancestry, such as `ReplicatedStorage.Tools`.

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

## Build and run

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

## Repo layout

- [plugin.project.json](/home/nav/rojo-convert/plugin.project.json) builds the plugin model with Rojo.
- [plugin/src/init.server.lua](/home/nav/rojo-convert/plugin/src/init.server.lua) creates the toolbar button and sends export requests.
- [plugin/src/ExportSerializer.lua](/home/nav/rojo-convert/plugin/src/ExportSerializer.lua) walks the selected instances and converts supported properties into Rojo JSON values.
- [exporter/server.py](/home/nav/rojo-convert/exporter/server.py) runs the localhost HTTP service.
- [exporter/writer.py](/home/nav/rojo-convert/exporter/writer.py) writes the Rojo tree and project file.
- [tests/test_writer.py](/home/nav/rojo-convert/tests/test_writer.py) covers the file layout logic.

## Limitations

- The exporter skips property types that Rojo does not support in project/meta files, such as instance references (`Ref`), `Region3`, `Region3int16`, `SharedString`, `MaterialColors`, and `OptionalCoordinateFrame`.
- Exported properties are intentionally sparse: the plugin uses modified properties instead of dumping every default value.
- If a Roblox instance name is invalid on the local filesystem, the exporter sanitizes the directory name and preserves the original `Name` through `init.meta.json`.

## References

- Rojo sync details: <https://rojo.space/docs/v7/sync-details/>
- Rojo project format: <https://rojo.space/docs/v7/project-format/>
- Rojo property encoding: <https://rojo.space/docs/v7/properties/>
- Roblox `HttpService` docs, including plugin localhost usage: <https://create.roblox.com/docs/cloud-services/http-service>
