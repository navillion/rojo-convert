from __future__ import annotations

import json
import re
from dataclasses import dataclass
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


@dataclass(frozen=True)
class ProjectMapping:
    studio_path: tuple[str, ...]
    filesystem_path: Path


@dataclass(frozen=True)
class ProjectPlacement:
    mapping_root: Path
    target_directory: Path
    ancestor_entries: tuple[dict[str, Any], ...]
    preserve_original_name: bool


class ExportWriter:
    def __init__(self, output_root: Path, project_root: Path | None = None) -> None:
        self.output_root = output_root.resolve()
        self.project_root = (project_root or Path.cwd()).resolve()
        self.project_file = self._find_project_file(self.project_root)
        self.project_mappings = self._load_project_mappings(self.project_file)

    def export(self, payload: dict[str, Any]) -> dict[str, Any]:
        selection = payload.get("selection")
        if not isinstance(selection, list) or not selection:
            raise ExportError("Payload must include a non-empty selection array.")

        self.output_root.mkdir(parents=True, exist_ok=True)

        warnings: list[str] = []
        created_paths: list[str] = []
        project_files: set[str] = set()
        mapped_paths: list[str] = []
        fallback_selection: list[dict[str, Any]] = []

        for node in selection:
            placement = self._find_existing_project_placement(node)

            if placement is None:
                fallback_selection.append(node)
                continue

            target_directory = self._write_into_existing_project(placement, node, warnings)
            mapped_paths.append(str(target_directory))
            created_paths.append(str(target_directory))

            if self.project_file is not None:
                project_files.add(str(self.project_file))

        fallback_result: dict[str, Any] | None = None
        if fallback_selection:
            if len(fallback_selection) == 1:
                fallback_result = self._export_single(fallback_selection[0])
            else:
                fallback_result = self._export_multiple(fallback_selection)

            created_paths.extend(fallback_result["createdPaths"])
            warnings.extend(fallback_result["warnings"])

            fallback_project_file = fallback_result.get("projectFile")
            if isinstance(fallback_project_file, str) and fallback_project_file:
                project_files.add(fallback_project_file)

        if fallback_result is not None:
            fallback_result["createdPaths"] = created_paths
            fallback_result["warnings"] = warnings
            fallback_result["projectFiles"] = sorted(project_files)
            return fallback_result

        bundle_path = mapped_paths[0] if len(mapped_paths) == 1 else str(self.project_root)
        project_file = ""
        if len(project_files) == 1:
            project_file = next(iter(project_files))

        return {
            "ok": True,
            "bundlePath": bundle_path,
            "projectFile": project_file,
            "createdPaths": created_paths,
            "warnings": warnings,
            "projectFiles": sorted(project_files),
        }

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

    def _find_existing_project_placement(self, node: dict[str, Any]) -> ProjectPlacement | None:
        if self.project_file is None or not self.project_mappings:
            return None

        self._validate_node(node)

        path_entries = list(node.get("mountPath", [])) + [
            {
                "name": node["name"],
                "className": node["className"],
            }
        ]
        studio_path = tuple(entry["name"] for entry in path_entries)

        best_mapping: ProjectMapping | None = None
        for mapping in self.project_mappings:
            if len(mapping.studio_path) > len(studio_path):
                continue

            if studio_path[: len(mapping.studio_path)] != mapping.studio_path:
                continue

            if best_mapping is None or len(mapping.studio_path) > len(best_mapping.studio_path):
                best_mapping = mapping

        if best_mapping is None:
            return None

        mapping_root = best_mapping.filesystem_path
        if mapping_root.suffix:
            return None
        if mapping_root.exists() and not mapping_root.is_dir():
            return None

        remaining_entries = path_entries[len(best_mapping.studio_path) :]
        if not remaining_entries:
            return ProjectPlacement(
                mapping_root=mapping_root,
                target_directory=mapping_root,
                ancestor_entries=tuple(),
                preserve_original_name=False,
            )

        current_directory = mapping_root
        ancestor_entries = tuple(remaining_entries[:-1])

        for ancestor in ancestor_entries:
            current_directory = current_directory / self._sanitize_component(ancestor["name"])

        root_directory_name = self._sanitize_component(remaining_entries[-1]["name"])
        return ProjectPlacement(
            mapping_root=mapping_root,
            target_directory=current_directory / root_directory_name,
            ancestor_entries=ancestor_entries,
            preserve_original_name=root_directory_name != remaining_entries[-1]["name"],
        )

    def _write_into_existing_project(
        self,
        placement: ProjectPlacement,
        node: dict[str, Any],
        warnings: list[str],
    ) -> Path:
        placement.mapping_root.mkdir(parents=True, exist_ok=True)
        self._ensure_intermediate_ancestors(placement.mapping_root, placement.ancestor_entries, warnings)

        if placement.target_directory.exists():
            warnings.append(
                f"Merging export for {node['name']} into existing path {placement.target_directory}; "
                "stale sibling files are not removed automatically."
            )

        self._write_instance_directory(
            placement.target_directory,
            node,
            warnings,
            preserve_original_name=placement.preserve_original_name,
            merge_existing=True,
        )
        return placement.target_directory

    def _ensure_intermediate_ancestors(
        self,
        mapping_root: Path,
        ancestor_entries: tuple[dict[str, Any], ...],
        warnings: list[str],
    ) -> None:
        current_directory = mapping_root

        for ancestor in ancestor_entries:
            ancestor_name = ancestor.get("name")
            ancestor_class = ancestor.get("className")
            if not isinstance(ancestor_name, str) or not ancestor_name:
                raise ExportError("Mapped ancestor entries must include a non-empty name.")
            if not isinstance(ancestor_class, str) or not ancestor_class:
                raise ExportError("Mapped ancestor entries must include a non-empty className.")

            directory_name = self._sanitize_component(ancestor_name)
            current_directory = current_directory / directory_name
            self._ensure_placeholder_directory(
                current_directory,
                ancestor_name,
                ancestor_class,
                warnings,
                preserve_original_name=directory_name != ancestor_name,
            )

    def _ensure_placeholder_directory(
        self,
        directory: Path,
        instance_name: str,
        class_name: str,
        warnings: list[str],
        *,
        preserve_original_name: bool,
    ) -> None:
        if directory.exists() and not directory.is_dir():
            raise ExportError(f"Expected {directory} to be a directory for mapped project placement.")

        if class_name in SCRIPT_FILE_NAMES:
            if not directory.exists():
                raise ExportError(
                    f"Cannot synthesize missing script ancestor {instance_name!r} inside existing project mapping."
                )
            return

        directory.mkdir(parents=True, exist_ok=True)

        meta_path = directory / "init.meta.json"
        meta: dict[str, Any] = {}
        meta_exists = meta_path.exists()

        if meta_exists:
            try:
                decoded = json.loads(meta_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                raise ExportError(f"Existing meta file {meta_path} is not valid JSON: {exc}") from exc

            if not isinstance(decoded, dict):
                raise ExportError(f"Existing meta file {meta_path} must contain a JSON object.")

            meta = dict(decoded)

        changed = False

        if class_name != "Folder" and "className" not in meta:
            meta["className"] = class_name
            changed = True

        if preserve_original_name:
            properties = dict(meta.get("properties") or {})
            if properties.get("Name") != instance_name:
                properties["Name"] = instance_name
                meta["properties"] = properties
                changed = True
                warnings.append(
                    f"Filesystem name for mapped ancestor {instance_name} was sanitized to {directory.name}; "
                    "the original Instance.Name was preserved in init.meta.json."
                )

        if meta and (changed or not meta_exists):
            self._write_json(meta_path, meta)

    def _write_instance_directory(
        self,
        directory: Path,
        node: dict[str, Any],
        warnings: list[str],
        *,
        preserve_original_name: bool,
        merge_existing: bool = False,
    ) -> None:
        self._validate_node(node)

        if directory.exists():
            if not directory.is_dir():
                raise ExportError(f"Expected {directory} to be a directory.")
            if not merge_existing:
                raise ExportError(f"Refusing to overwrite existing directory {directory}.")
        else:
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
                merge_existing=merge_existing,
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

    @staticmethod
    def _find_project_file(project_root: Path) -> Path | None:
        default_project = project_root / "default.project.json"
        if default_project.is_file():
            return default_project

        project_files = sorted(project_root.glob("*.project.json"))
        if project_files:
            return project_files[0]

        return None

    def _load_project_mappings(self, project_file: Path | None) -> list[ProjectMapping]:
        if project_file is None:
            return []

        try:
            payload = json.loads(project_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ExportError(f"Project file {project_file} is not valid JSON: {exc}") from exc

        tree = payload.get("tree")
        if not isinstance(tree, dict):
            return []

        mappings: list[ProjectMapping] = []
        self._collect_project_mappings(tree, tuple(), project_file.parent, mappings)
        mappings.sort(key=lambda mapping: len(mapping.studio_path))
        return mappings

    def _collect_project_mappings(
        self,
        node: dict[str, Any],
        studio_path: tuple[str, ...],
        project_directory: Path,
        mappings: list[ProjectMapping],
    ) -> None:
        path_value = node.get("$path")
        if isinstance(path_value, str):
            mappings.append(
                ProjectMapping(
                    studio_path=studio_path,
                    filesystem_path=(project_directory / path_value).resolve(),
                )
            )

        for key, child in node.items():
            if key.startswith("$"):
                continue
            if isinstance(child, dict):
                self._collect_project_mappings(child, studio_path + (key,), project_directory, mappings)


__all__ = ["ExportError", "ExportWriter"]
