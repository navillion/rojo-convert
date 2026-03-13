from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from exporter.writer import ExportWriter


class ExportWriterTests(unittest.TestCase):
    def test_single_selection_export_writes_rojo_tree_and_project_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory))
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

    def test_sanitized_child_names_preserve_original_instance_name(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory))
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

    def test_multiple_selection_export_creates_bundle_project(self) -> None:
        with tempfile.TemporaryDirectory() as temp_directory:
            writer = ExportWriter(Path(temp_directory))
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
