"""Use the installed Rasa CLI with project-local configuration and telemetry disabled."""
import os
from pathlib import Path

os.environ["RASA_TELEMETRY_ENABLED"] = "false"
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import rasa.constants

runtime = Path(__file__).resolve().parent / ".runtime"
runtime.mkdir(exist_ok=True)
config_path = runtime / "global.yml"
disabled_config = "metrics:\n  enabled: false\n"
if not config_path.exists() or config_path.read_text(encoding="utf-8") != disabled_config:
    temporary_config = runtime / f"global-{os.getpid()}.tmp"
    temporary_config.write_text(disabled_config, encoding="utf-8")
    temporary_config.replace(config_path)
rasa.constants.GLOBAL_USER_CONFIG_PATH = str(config_path)

from windows_model_storage import install_windows_compatibility
install_windows_compatibility()

if __name__ == "__main__":
    from rasa.__main__ import main
    main()
