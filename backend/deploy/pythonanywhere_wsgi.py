"""WSGI entry point for PythonAnywhere; load private configuration before Flask."""

import os
import sys
from pathlib import Path

from dotenv import dotenv_values, load_dotenv


env_file = Path(
    os.environ.get("CISTERNAS_ENV_FILE", "/home/crismp/.config/cisternas/backend.env")
).expanduser().resolve()
if not env_file.is_file():
    raise RuntimeError("Falta el archivo privado de configuracion de Cisternas.")

private_config = dotenv_values(env_file)
missing = [key for key in ("SECRET_KEY", "DATABASE_URL") if not (private_config.get(key) or "").strip()]
if missing:
    raise RuntimeError("Configure estas variables en el archivo privado: " + ", ".join(missing))

# This explicit deployment file is authoritative, including when WSGI is reloaded.
load_dotenv(env_file, override=True)
repo_dir = Path(
    os.environ.get("CISTERNAS_REPO_DIR", "/home/crismp/cargio_cisterna")
).expanduser().resolve()
backend_dir = repo_dir / "backend"
if not (backend_dir / "app.py").is_file():
    raise RuntimeError("CISTERNAS_REPO_DIR debe apuntar al repositorio que contiene backend/app.py.")
sys.path.insert(0, str(backend_dir))

from app import app as application, db  # noqa: E402

# create_app initializes tables/users on import. Do not share those connections
# with the worker processes that PythonAnywhere forks after loading WSGI.
with application.app_context():
    db.session.remove()
    db.engine.dispose()
