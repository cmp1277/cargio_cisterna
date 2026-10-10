"""Deployment checks use temporary files and fake connections, never production data."""

import importlib.util
import os
import runpy
import sys
from contextlib import nullcontext
from pathlib import Path
from types import SimpleNamespace

import pytest


BACKEND_DIR = Path(__file__).resolve().parents[1]
WSGI_FILE = BACKEND_DIR / "deploy" / "pythonanywhere_wsgi.py"


@pytest.fixture()
def isolated_backend(tmp_path, monkeypatch):
    # Prevent app.py from loading any developer/production .env during import.
    monkeypatch.setenv("PYTHON_DOTENV_DISABLED", "1")
    monkeypatch.setenv("DATABASE_URL", "sqlite:///" + str(tmp_path / "bootstrap.db"))
    monkeypatch.setenv("SECRET_KEY", "isolated-deployment-test")
    for name in ("ADMIN_PASSWORD", "USER_PASSWORD", "CLIENT_PASSWORD"):
        monkeypatch.setenv(name, "")
    spec = importlib.util.spec_from_file_location("isolated_backend", BACKEND_DIR / "app.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    yield module
    with module.app.app_context():
        module.db.session.remove()
        module.db.engine.dispose()


def configuration_before_connect(module, monkeypatch, config):
    captured = {}

    class ConfigurationCaptured(Exception):
        pass

    def capture(app):
        captured.update(app.config)
        raise ConfigurationCaptured

    monkeypatch.setattr(module.db, "init_app", capture)
    with pytest.raises(ConfigurationCaptured):
        module.create_app(config)
    return captured


@pytest.mark.parametrize("scheme", ["mysql", "mysql+pymysql", "mysql+mysqldb"])
def test_mysql_connection_recovery_configured_before_engine_initialization(isolated_backend, monkeypatch, scheme):
    config = configuration_before_connect(
        isolated_backend, monkeypatch, {"SQLALCHEMY_DATABASE_URI": scheme + "://unused/unused"}
    )
    assert config["SQLALCHEMY_ENGINE_OPTIONS"] == {"pool_recycle": 280, "pool_pre_ping": True}


def test_explicit_engine_options_are_preserved(isolated_backend, monkeypatch):
    custom = {"pool_recycle": 120, "pool_size": 2, "pool_pre_ping": False}
    config = configuration_before_connect(
        isolated_backend,
        monkeypatch,
        {"SQLALCHEMY_DATABASE_URI": "mysql+pymysql://unused/unused", "SQLALCHEMY_ENGINE_OPTIONS": custom},
    )
    assert config["SQLALCHEMY_ENGINE_OPTIONS"] == custom
    assert config["SQLALCHEMY_ENGINE_OPTIONS"] is not custom


@pytest.mark.parametrize("uri", ["sqlite:///:memory:", "postgresql://unused/unused"])
def test_other_database_dialects_keep_existing_options(isolated_backend, monkeypatch, uri):
    config = configuration_before_connect(isolated_backend, monkeypatch, {"SQLALCHEMY_DATABASE_URI": uri})
    assert not config.get("SQLALCHEMY_ENGINE_OPTIONS")


@pytest.fixture()
def wsgi_configuration(tmp_path, monkeypatch):
    monkeypatch.delenv("PYTHON_DOTENV_DISABLED", raising=False)
    env_file = tmp_path / "private.env"
    repo = tmp_path / "repo"
    (repo / "backend").mkdir(parents=True)
    (repo / "backend" / "app.py").touch()
    monkeypatch.setenv("CISTERNAS_ENV_FILE", str(env_file))
    monkeypatch.setenv("CISTERNAS_REPO_DIR", str(repo))
    # dotenv modifies os.environ itself; restore every deployment variable.
    for key in ("SECRET_KEY", "DATABASE_URL", "CORS_ORIGINS"):
        monkeypatch.delenv(key, raising=False)
    original_path = sys.path[:]
    yield env_file, repo
    sys.path[:] = original_path


def test_wsgi_requires_private_file(wsgi_configuration):
    with pytest.raises(RuntimeError, match="Falta el archivo privado"):
        runpy.run_path(str(WSGI_FILE))


@pytest.mark.parametrize(
    "contents, missing",
    [("SECRET_KEY=test-key\nDATABASE_URL=\n", "DATABASE_URL"), ("SECRET_KEY=\nDATABASE_URL=sqlite:///:memory:\n", "SECRET_KEY")],
)
def test_wsgi_rejects_missing_settings_before_app_import(wsgi_configuration, monkeypatch, contents, missing):
    env_file, _ = wsgi_configuration
    env_file.write_text(contents, encoding="utf-8")
    # Even a global value must not hide an incomplete private configuration file.
    monkeypatch.setenv(missing, "unrelated-environment-value")
    with pytest.raises(RuntimeError, match=missing):
        runpy.run_path(str(WSGI_FILE))


def test_wsgi_rejects_wrong_repository(wsgi_configuration, monkeypatch):
    env_file, repo = wsgi_configuration
    env_file.write_text("SECRET_KEY=test-key\nDATABASE_URL=sqlite:///:memory:\n", encoding="utf-8")
    monkeypatch.setenv("CISTERNAS_REPO_DIR", str(repo / "missing"))
    with pytest.raises(RuntimeError, match="CISTERNAS_REPO_DIR"):
        runpy.run_path(str(WSGI_FILE))


def test_wsgi_loads_private_settings_and_closes_bootstrap_connections(wsgi_configuration, monkeypatch):
    env_file, repo = wsgi_configuration
    env_file.write_text(
        "SECRET_KEY=test-key\nDATABASE_URL=mysql+pymysql://unused/unused\nCORS_ORIGINS=https://example.test\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    events = []

    def application_context():
        assert os.environ["DATABASE_URL"] == "mysql+pymysql://unused/unused"
        assert os.environ["SECRET_KEY"] == "test-key"
        events.append("context")
        return nullcontext()

    fake_application = SimpleNamespace(app_context=application_context)
    fake_db = SimpleNamespace(
        session=SimpleNamespace(remove=lambda: events.append("remove")),
        engine=SimpleNamespace(dispose=lambda: events.append("dispose")),
    )
    monkeypatch.setitem(sys.modules, "app", SimpleNamespace(app=fake_application, db=fake_db))
    result = runpy.run_path(str(WSGI_FILE))
    assert result["application"] is fake_application
    assert events == ["context", "remove", "dispose"]
    assert sys.path[0] == str(repo / "backend")
    assert os.environ["CORS_ORIGINS"] == "https://example.test"
