from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any


SCRIPT_FILE_NAMES = {
    "Script": "init.server.lua",
    "LocalScript": "init.client.lua",
    "ModuleScript": "init.lua",
}

INVALID_PATH_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1F]')
WINDOWS_RESERVED_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    "COM1",
    "COM2",
    "COM3",
    "COM4",
    "COM5",
    "COM6",
    "COM7",
    "COM8",
    "COM9",
    "LPT1",
    "LPT2",
    "LPT3",
    "LPT4",
    "LPT5",
    "LPT6",
    "LPT7",
    "LPT8",
    "LPT9",
}


class ExportError(Exception):
    """Raised when the exporter receives invalid data."""


class ExportWriter:
    def __init__(self, output_root: Path) -> None:
        self.output_root = output_root.resolve()

    def export(self, payload: dict[str, Any]) -> dict[str, Any]:
        selection = payload.get("selection")
        if not isinstance(selection, list) or not selection:
            raise ExportError("Payload must include a non-empty selection array.")

        self.output_root.mkdir(parents=True, exist_ok=True)

        if len(selection) == 1:
            return self._export_single(selection[0])

        return self._export_multiple(selection)

    def _export_single(self, node: dict[str, Any]) -> dict[str, Any]:
        warnings: list[str] = []
        root_directory_name = self._choose_available_name(self.output_root, node["name"])
        root_directory = self.output_root / root_directory_name

        self._write_instance_directory(root_directory, node, warnings, preserve_original_name=False)

        project_file = self.output_root / f"{root_directory_name}.project.json"
        project_payload = self._build_project(
            project_name=node["name"],
            selections=[(node, PurePosixPath(root_directory.name).as_posix())],
        )
        self._write_json(project_file, project_payload)

        return {
            "ok": True,
            "bundlePath": str(root_directory),
            "projectFile": str(project_file),
            "createdPaths": [str(root_directory), str(project_file)],
            "warnings": warnings,
        }

    def _export_multiple(self, selection: list[dict[str, Any]]) -> dict[str, Any]:
        warnings: list[str] = []
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        bundle_name = self._choose_available_name(self.output_root, f"RojoConvert-{timestamp}")
        bundle_directory = self.output_root / bundle_name
        bundle_directory.mkdir(parents=True, exist_ok=False)

        selections_for_project: list[tuple[dict[str, Any], str]] = []
        used_root_names: set[str] = set()
        created_paths: list[str] = [str(bundle_directory)]

        for node in selection:
            root_directory_name = self._choose_unique_component(node["name"], used_root_names)
            root_directory = bundle_directory / root_directory_name
            self._write_instance_directory(root_directory, node, warnings, preserve_original_name=False)
            selections_for_project.append((node, PurePosixPath(root_directory.name).as_posix()))
            created_paths.append(str(root_directory))

        project_file = bundle_directory / "default.project.json"
        project_payload = self._build_project(
            project_name=bundle_directory.name,
            selections=selections_for_project,
        )
        self._write_json(project_file, project_payload)
        created_paths.append(str(project_file))

        return {
            "ok": True,
            "bundlePath": str(bundle_directory),
            "projectFile": str(project_file),
            "createdPaths": created_paths,
            "warnings": warnings,
        }

    def _build_project(
        self,
        project_name: str,
        selections: list[tuple[dict[str, Any], str]],
    ) -> dict[str, Any]:
        tree: dict[str, Any] = {"$className": "DataModel"}

        for node, relative_path in selections:
            self._validate_node(node)
            cursor = tree

            for ancestor in node.get("mountPath", []):
                if not isinstance(ancestor, dict):
                    raise ExportError("Each mountPath entry must be an object.")

                ancestor_name = ancestor.get("name")
                ancestor_class = ancestor.get("className")
                if not isinstance(ancestor_name, str) or not ancestor_name:
                    raise ExportError("mountPath entries must include a non-empty name.")
                if not isinstance(ancestor_class, str) or not ancestor_class:
                    raise ExportError("mountPath entries must include a non-empty className.")

                if ancestor_name not in cursor:
                    cursor[ancestor_name] = {"$className": ancestor_class}

                cursor = cursor[ancestor_name]

            root_name = node["name"]
            if root_name in cursor:
                raise ExportError(f"Selection root collision at {root_name!r}.")

            cursor[root_name] = {
                "$className": node["className"],
                "$path": relative_path,
            }

        return {
            "name": project_name,
            "emitLegacyScripts": True,
            "tree": tree,
        }

    def _write_instance_directory(
        self,
        directory: Path,
        node: dict[str, Any],
        warnings: list[str],
        *,
        preserve_original_name: bool,
    ) -> None:
        self._validate_node(node)
        directory.mkdir(parents=True, exist_ok=False)

        properties = dict(node.get("properties") or {})
        if preserve_original_name:
            properties["Name"] = node["name"]
            warnings.append(
                f"Filesystem name for {node['name']} was sanitized to {directory.name}; "
                "the original Instance.Name was preserved in init.meta.json."
            )

        class_name = node["className"]
        script_file_name = SCRIPT_FILE_NAMES.get(class_name)
        if script_file_name is not None:
            source = node.get("source", "")
            if not isinstance(source, str):
                raise ExportError(f"Expected script source for {node['name']} to be a string.")
            self._write_text(directory / script_file_name, source)

        meta: dict[str, Any] = {}
        if script_file_name is None and class_name != "Folder":
            meta["className"] = class_name
        if properties:
            meta["properties"] = properties
        if meta:
            self._write_json(directory / "init.meta.json", meta)

        children = node.get("children", [])
        if not isinstance(children, list):
            raise ExportError(f"Expected children for {node['name']} to be an array.")

        used_child_names: set[str] = set()
        for child in sorted(children, key=self._child_sort_key):
            if not isinstance(child, dict):
                raise ExportError(f"Child nodes for {node['name']} must be objects.")

            child_directory_name = self._choose_unique_component(child["name"], used_child_names)
            child_directory = directory / child_directory_name
            self._write_instance_directory(
                child_directory,
                child,
                warnings,
                preserve_original_name=child_directory_name != child["name"],
            )

    @staticmethod
    def _write_json(path: Path, payload: dict[str, Any]) -> None:
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    @staticmethod
    def _write_text(path: Path, source: str) -> None:
        path.write_text(source, encoding="utf-8", newline="\n")

    @staticmethod
    def _child_sort_key(node: dict[str, Any]) -> tuple[str, str, str]:
        return (
            node["name"].casefold(),
            node["className"].casefold(),
            node["name"],
        )

    @classmethod
    def _choose_available_name(cls, parent: Path, preferred_name: str) -> str:
        base = cls._sanitize_component(preferred_name)
        candidate = base
        suffix = 2

        while (parent / candidate).exists() or (parent / f"{candidate}.project.json").exists():
            candidate = f"{base}-{suffix}"
            suffix += 1

        return candidate

    @classmethod
    def _choose_unique_component(cls, preferred_name: str, used_names: set[str]) -> str:
        base = cls._sanitize_component(preferred_name)
        candidate = base
        suffix = 2

        while candidate.casefold() in used_names:
            candidate = f"{base}-{suffix}"
            suffix += 1

        used_names.add(candidate.casefold())
        return candidate

    @classmethod
    def _sanitize_component(cls, value: str) -> str:
        if not isinstance(value, str) or not value:
            return "Selection"

        sanitized = INVALID_PATH_CHARS.sub("_", value).strip()
        sanitized = sanitized.rstrip(" .")

        if not sanitized:
            sanitized = "Selection"

        if sanitized.upper() in WINDOWS_RESERVED_NAMES:
            sanitized = f"_{sanitized}"

        return sanitized

    @staticmethod
    def _validate_node(node: dict[str, Any]) -> None:
        if not isinstance(node, dict):
            raise ExportError("Each selection node must be an object.")

        if not isinstance(node.get("name"), str) or not node["name"]:
            raise ExportError("Each node must include a non-empty name.")

        if not isinstance(node.get("className"), str) or not node["className"]:
            raise ExportError(f"Node {node['name']!r} is missing className.")

        mount_path = node.get("mountPath", [])
        if not isinstance(mount_path, list):
            raise ExportError(f"Node {node['name']!r} must include mountPath as an array.")

        properties = node.get("properties")
        if properties is not None and not isinstance(properties, dict):
            raise ExportError(f"Node {node['name']!r} has invalid properties.")


__all__ = ["ExportError", "ExportWriter"]

