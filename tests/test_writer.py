from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from exporter.writer import ExportWriter


class ExportWriterTests(unittest.TestCase):
    def test_existing_project_mapping_marks_partial_ancestors_ignore_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            root = Path(temp_directory)
            (root / "default.project.json").write_text(
                json.dumps(
                    {
                        "name": "test-project",
                        "tree": {
                            "$className": "DataModel",
                            "ReplicatedStorage": {
                                "Shared": {
                                    "$path": "src/shared",
                                }
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )

            writer = ExportWriter(root / "exports", project_root=root)
            payload = {
                "selection": [
                    {
                        "name": "Hammer",
                        "className": "Tool",
                        "mountPath": [
                            {"name": "ReplicatedStorage", "className": "ReplicatedStorage"},
                            {"name": "Shared", "className": "Folder"},
                            {"name": "Tools", "className": "Folder"},
                        ],
                        "children": [],
                    }
                ]
            }

            result = writer.export(payload)

            hammer_directory = root / "src" / "shared" / "Tools" / "Hammer"
            shared_meta = json.loads((root / "src" / "shared" / "init.meta.json").read_text(encoding="utf-8"))
            tools_meta = json.loads((root / "src" / "shared" / "Tools" / "init.meta.json").read_text(encoding="utf-8"))
            hammer_meta = json.loads((hammer_directory / "init.meta.json").read_text(encoding="utf-8"))

            self.assertEqual(Path(result["bundlePath"]), hammer_directory)
            self.assertTrue(shared_meta["ignoreUnknownInstances"])
            self.assertTrue(tools_meta["ignoreUnknownInstances"])
            self.assertNotIn("ignoreUnknownInstances", hammer_meta)

    def test_existing_project_mapping_places_export_inside_src_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            root = Path(temp_directory)
            (root / "default.project.json").write_text(
                json.dumps(
                    {
                        "name": "test-project",
                        "tree": {
                            "$className": "DataModel",
                            "ReplicatedStorage": {
                                "Shared": {
                                    "$path": "src/shared",
                                }
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )

            writer = ExportWriter(root / "exports", project_root=root)
            payload = {
                "selection": [
                    {
                        "name": "Tools",
                        "className": "Folder",
                        "mountPath": [
                            {"name": "ReplicatedStorage", "className": "ReplicatedStorage"},
                            {"name": "Shared", "className": "Folder"},
                        ],
                        "children": [
                            {
                                "name": "Hammer",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            }
                        ],
                    }
                ]
            }

            result = writer.export(payload)

            mapped_directory = root / "src" / "shared" / "Tools"
            self.assertEqual(Path(result["bundlePath"]), mapped_directory)
            self.assertEqual(result["projectFile"], str(root / "default.project.json"))
            self.assertTrue((mapped_directory / "Hammer" / "init.meta.json").is_file())
            self.assertFalse((root / "exports" / "Tools").exists())

    def test_missing_project_mapping_falls_back_to_exports(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            root = Path(temp_directory)
            (root / "default.project.json").write_text(
                json.dumps(
                    {
                        "name": "test-project",
                        "tree": {
                            "$className": "DataModel",
                            "ReplicatedStorage": {
                                "Shared": {
                                    "$path": "src/shared",
                                }
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )

            writer = ExportWriter(root / "exports", project_root=root)
            payload = {
                "selection": [
                    {
                        "name": "Cache",
                        "className": "Folder",
                        "mountPath": [
                            {"name": "ServerStorage", "className": "ServerStorage"},
                        ],
                        "children": [],
                    }
                ]
            }

            result = writer.export(payload)

            fallback_directory = root / "exports" / "Cache"
            fallback_project = root / "exports" / "Cache.project.json"
            self.assertEqual(Path(result["bundlePath"]), fallback_directory)
            self.assertEqual(Path(result["projectFile"]), fallback_project)
            self.assertTrue(fallback_directory.is_dir())
            self.assertTrue(fallback_project.is_file())

    def test_single_selection_export_writes_rojo_tree_and_project_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Tools",
                        "className": "Folder",
                        "mountPath": [
                            {"name": "ReplicatedStorage", "className": "ReplicatedStorage", "isService": True}
                        ],
                        "children": [
                            {
                                "name": "Hammer",
                                "className": "Tool",
                                "mountPath": [],
                                "properties": {
                                    "RequiresHandle": False,
                                    "Tags": ["Starter"],
                                },
                                "children": [
                                    {
                                        "name": "ClientBootstrap",
                                        "className": "LocalScript",
                                        "mountPath": [],
                                        "source": 'print("ready")\n',
                                        "children": [],
                                    }
                                ],
                            },
                            {
                                "name": "Wrench",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)

            root_directory = Path(result["bundlePath"])
            project_file = Path(result["projectFile"])

            self.assertTrue(root_directory.is_dir())
            self.assertEqual(root_directory.name, "Tools")
            self.assertTrue((root_directory / "Hammer" / "init.meta.json").is_file())
            self.assertTrue((root_directory / "Hammer" / "ClientBootstrap" / "init.client.lua").is_file())
            self.assertTrue((root_directory / "Wrench" / "init.meta.json").is_file())
            self.assertTrue(project_file.is_file())

            hammer_meta = json.loads((root_directory / "Hammer" / "init.meta.json").read_text(encoding="utf-8"))
            self.assertEqual(hammer_meta["className"], "Tool")
            self.assertEqual(hammer_meta["properties"]["RequiresHandle"], False)
            self.assertEqual(hammer_meta["properties"]["Tags"], ["Starter"])

            project_payload = json.loads(project_file.read_text(encoding="utf-8"))
            self.assertEqual(project_payload["tree"]["ReplicatedStorage"]["Tools"]["$path"], "Tools")
            self.assertTrue(project_payload["tree"]["ReplicatedStorage"]["$ignoreUnknownInstances"])

    def test_single_child_export_marks_project_ancestors_ignore_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Hammer",
                        "className": "Tool",
                        "mountPath": [
                            {"name": "ReplicatedStorage", "className": "ReplicatedStorage"},
                            {"name": "Tools", "className": "Folder"},
                        ],
                        "children": [],
                    }
                ]
            }

            result = writer.export(payload)
            project_file = Path(result["projectFile"])
            project_payload = json.loads(project_file.read_text(encoding="utf-8"))

            replicated_storage = project_payload["tree"]["ReplicatedStorage"]
            tools = replicated_storage["Tools"]

            self.assertTrue(replicated_storage["$ignoreUnknownInstances"])
            self.assertTrue(tools["$ignoreUnknownInstances"])
            self.assertEqual(tools["Hammer"]["$path"], "Hammer")

    def test_sanitized_child_names_preserve_original_instance_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Bad:Folder",
                        "className": "Folder",
                        "mountPath": [],
                        "children": [
                            {
                                "name": "A*",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "A?",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)
            root_directory = Path(result["bundlePath"])

            child_directories = sorted(path for path in root_directory.iterdir() if path.is_dir())
            self.assertEqual([path.name for path in child_directories], ["A_", "A_-2"])

            first_meta = json.loads((child_directories[0] / "init.meta.json").read_text(encoding="utf-8"))
            second_meta = json.loads((child_directories[1] / "init.meta.json").read_text(encoding="utf-8"))

            self.assertEqual(first_meta["properties"]["Name"], "A*")
            self.assertEqual(second_meta["properties"]["Name"], "A?")

    def test_duplicate_child_names_preserve_original_instance_name_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Root",
                        "className": "Folder",
                        "mountPath": [],
                        "children": [
                            {
                                "name": "Part",
                                "className": "Part",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "Part",
                                "className": "Part",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)
            root_directory = Path(result["bundlePath"])
            child_directories = sorted(path for path in root_directory.iterdir() if path.is_dir())

            self.assertEqual([path.name for path in child_directories], ["Part", "Part-2"])

            first_meta = json.loads((child_directories[0] / "init.meta.json").read_text(encoding="utf-8"))
            second_meta = json.loads((child_directories[1] / "init.meta.json").read_text(encoding="utf-8"))

            self.assertNotIn("Name", first_meta.get("properties", {}))
            self.assertEqual(second_meta["properties"]["Name"], "Part")

    def test_duplicate_child_names_can_keep_deduped_filesystem_name_in_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "preserveOriginalDuplicateNames": False,
                "selection": [
                    {
                        "name": "Root",
                        "className": "Folder",
                        "mountPath": [],
                        "children": [
                            {
                                "name": "Part",
                                "className": "Part",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "Part",
                                "className": "Part",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)
            root_directory = Path(result["bundlePath"])
            child_directories = sorted(path for path in root_directory.iterdir() if path.is_dir())

            self.assertEqual([path.name for path in child_directories], ["Part", "Part-2"])

            second_meta = json.loads((child_directories[1] / "init.meta.json").read_text(encoding="utf-8"))
            self.assertEqual(second_meta["properties"]["Name"], "Part-2")

    def test_writer_preserves_input_child_order_for_duplicate_name_assignment(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Root",
                        "className": "Folder",
                        "mountPath": [],
                        "children": [
                            {
                                "name": "Dup",
                                "className": "Part",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "Dup",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "Dup",
                                "className": "Model",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)
            root_directory = Path(result["bundlePath"])
            first_meta = json.loads((root_directory / "Dup" / "init.meta.json").read_text(encoding="utf-8"))
            second_meta = json.loads((root_directory / "Dup-2" / "init.meta.json").read_text(encoding="utf-8"))
            third_meta = json.loads((root_directory / "Dup-3" / "init.meta.json").read_text(encoding="utf-8"))

            self.assertEqual(first_meta["className"], "Part")
            self.assertEqual(second_meta["className"], "Tool")
            self.assertEqual(third_meta["className"], "Model")

    def test_sanitized_duplicate_names_still_preserve_original_name_when_duplicate_mode_is_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "preserveOriginalDuplicateNames": False,
                "selection": [
                    {
                        "name": "Bad:Folder",
                        "className": "Folder",
                        "mountPath": [],
                        "children": [
                            {
                                "name": "A*",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                            {
                                "name": "A?",
                                "className": "Tool",
                                "mountPath": [],
                                "children": [],
                            },
                        ],
                    }
                ]
            }

            result = writer.export(payload)
            root_directory = Path(result["bundlePath"])
            child_directories = sorted(path for path in root_directory.iterdir() if path.is_dir())

            first_meta = json.loads((child_directories[0] / "init.meta.json").read_text(encoding="utf-8"))
            second_meta = json.loads((child_directories[1] / "init.meta.json").read_text(encoding="utf-8"))

            self.assertEqual(first_meta["properties"]["Name"], "A*")
            self.assertEqual(second_meta["properties"]["Name"], "A?")

    def test_multiple_selection_export_creates_bundle_project(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory), project_root=Path(temp_directory))
            payload = {
                "selection": [
                    {
                        "name": "Shared",
                        "className": "Folder",
                        "mountPath": [{"name": "ReplicatedStorage", "className": "ReplicatedStorage"}],
                        "children": [],
                    },
                    {
                        "name": "Bootstrap",
                        "className": "ModuleScript",
                        "mountPath": [{"name": "ReplicatedFirst", "className": "ReplicatedFirst"}],
                        "source": "return {}\n",
                        "children": [],
                    },
                ]
            }

            result = writer.export(payload)
            bundle_directory = Path(result["bundlePath"])
            project_file = bundle_directory / "default.project.json"

            self.assertTrue(bundle_directory.is_dir())
            self.assertTrue((bundle_directory / "Shared").is_dir())
            self.assertTrue((bundle_directory / "Bootstrap" / "init.lua").is_file())
            self.assertTrue(project_file.is_file())

            project_payload = json.loads(project_file.read_text(encoding="utf-8"))
            self.assertEqual(project_payload["tree"]["ReplicatedStorage"]["Shared"]["$path"], "Shared")
            self.assertEqual(project_payload["tree"]["ReplicatedFirst"]["Bootstrap"]["$path"], "Bootstrap")


if __name__ == "__main__":
    unittest.main()
