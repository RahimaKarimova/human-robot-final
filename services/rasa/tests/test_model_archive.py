import io
import tarfile
import tempfile
import unittest
from pathlib import Path

from windows_model_storage import extract_regular_model


class ModelArchiveTests(unittest.TestCase):
    def test_regular_nested_file_extracts(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "model.tar.gz"
            with tarfile.open(archive, "w:gz") as output:
                entry = tarfile.TarInfo("components/test/model.json")
                entry.size = 2
                output.addfile(entry, io.BytesIO(b"{}"))
            target = Path(directory) / "output"
            target.mkdir()
            extract_regular_model(archive, target)
            self.assertEqual((target / "components/test/model.json").read_text(), "{}")

    def test_traversal_and_links_are_rejected(self):
        for name, kind in (("../outside", tarfile.REGTYPE), ("inside", tarfile.SYMTYPE), ("inside", tarfile.LNKTYPE)):
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / "model.tar.gz"
                with tarfile.open(archive, "w:gz") as output:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    entry.linkname = "../outside" if kind != tarfile.REGTYPE else ""
                    output.addfile(entry)
                target = Path(directory) / "output"
                target.mkdir()
                with self.assertRaises(ValueError):
                    extract_regular_model(archive, target)
