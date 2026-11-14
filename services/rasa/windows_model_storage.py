"""Local compatibility for Rasa 3.6's extended Windows paths on Python 3.10.22.

Use normal paths and Python's data filter; reject every non-file/directory entry.
The original Rasa version/metadata checks still run after extraction.
"""
import tarfile
from pathlib import Path


def extract_regular_model(archive_path, destination):
    root = Path(destination).resolve()
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            target = (root / member.name).resolve()
            if not target.is_relative_to(root) or not (member.isfile() or member.isdir()):
                raise ValueError("Unsupported model archive member.")
        archive.extractall(root, filter="data")


def install_windows_compatibility():
    import sys
    if sys.platform == "win32":
        from rasa.engine.storage.local_model_storage import LocalModelStorage

        def extract_model(archive_path, destination):
            extract_regular_model(archive_path, destination)
            LocalModelStorage._assert_not_rasa2_archive(destination)

        LocalModelStorage._extract_archive_to_directory = staticmethod(extract_model)
