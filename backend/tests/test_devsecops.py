from __future__ import annotations

from io import BytesIO

import pytest
from openpyxl import load_workbook

from app import LOGIN_ATTEMPTS, create_app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    LOGIN_ATTEMPTS.clear()
    monkeypatch.setenv("ADMIN_PASSWORD", "admin123")
    monkeypatch.setenv("USER_PASSWORD", "usuario123")
    monkeypatch.setenv("CLIENT_PASSWORD", "cliente123")

    app = create_app(
        {
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite:///" + str(tmp_path / "test.db"),
            "SESSION_DURATION_MINUTES": 30,
        }
    )
    return app.test_client()


def ok(response):
    data = response.get_json()
    assert response.status_code == 200, (response.status_code, data)
    assert data["success"] is True, data
    return data


def login(client, username: str, password: str) -> dict:
    return ok(client.post("/api/auth/login", json={"username": username, "password": password}))


def auth_header(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_security_headers_are_present(client):
    response = client.get("/api/health", headers={"X-Forwarded-Proto": "https"})

    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert "frame-ancestors 'none'" in response.headers["Content-Security-Policy"]
    assert "Strict-Transport-Security" in response.headers


def test_cors_is_restricted_to_expected_origins(client):
    allowed = client.get("/api/health", headers={"Origin": "https://cisternas-api-wqac.onrender.com"})
    null_origin = client.get("/api/health", headers={"Origin": "null"})
    denied = client.get("/api/health", headers={"Origin": "https://evil.example"})

    assert allowed.headers["Access-Control-Allow-Origin"] == "https://cisternas-api-wqac.onrender.com"
    assert null_origin.headers["Access-Control-Allow-Origin"] == "null"
    assert "Access-Control-Allow-Origin" not in denied.headers


def test_records_are_normalized_and_invalid_plate_is_rejected(client):
    admin = login(client, "admin", "admin123")
    user = login(client, "cliente", "cliente123")

    created = ok(
        client.post(
            "/api/mobile",
            json={
                "action": "saveData",
                "token": user["token"],
                "driverName": "cristian montoya",
                "plateNumber": "2127acc",
                "employeeCode": "emp 1277",
                "ebap": "norte",
                "initialReading": 10,
                "finalReading": 33,
                "loadVolume": 23,
                "companyType": "gobierno nacional",
                "companyName": "andina sa",
                "characteristics": "volvo color blanco",
            },
        )
    )

    records = ok(client.get("/api/records", headers=auth_header(admin["token"])))["records"]
    record = next(item for item in records if item["id"] == created["id"])
    assert record["driverName"] == "CRISTIAN MONTOYA"
    assert record["plateNumber"] == "2127 - ACC"
    assert record["companyName"] == "ANDINA SA"

    invalid = client.post(
        "/api/mobile",
        json={
            "action": "saveData",
            "token": user["token"],
            "driverName": "x",
            "plateNumber": "21acc",
            "employeeCode": "e",
            "ebap": "norte",
            "initialReading": 1,
            "finalReading": 2,
            "loadVolume": 1,
            "companyType": "particular",
            "companyName": "x",
            "characteristics": "",
        },
    )
    assert invalid.status_code == 400
    assert invalid.get_json()["success"] is False


def test_login_rate_limit_blocks_repeated_failures(client, monkeypatch):
    monkeypatch.setenv("LOGIN_RATE_LIMIT_MAX_ATTEMPTS", "2")
    monkeypatch.setenv("LOGIN_RATE_LIMIT_WINDOW_MINUTES", "15")

    first = client.post("/api/auth/login", json={"username": "admin", "password": "bad"})
    second = client.post("/api/auth/login", json={"username": "admin", "password": "bad"})
    third = client.post("/api/auth/login", json={"username": "admin", "password": "bad"})

    assert first.status_code == 401
    assert second.status_code == 401
    assert third.status_code == 429
    assert "Demasiados intentos" in third.get_json()["message"]


def test_admin_actions_are_audited(client):
    admin = login(client, "admin", "admin123")
    user = login(client, "cliente", "cliente123")
    headers = auth_header(admin["token"])

    created = ok(
        client.post(
            "/api/mobile",
            json={
                "action": "saveData",
                "token": user["token"],
                "driverName": "jose ortega",
                "plateNumber": "6161acr",
                "employeeCode": "1276",
                "ebap": "este",
                "initialReading": 80,
                "finalReading": 90,
                "loadVolume": 10,
                "companyType": "bomberos",
                "companyName": "andina",
                "characteristics": "volvo rojo",
            },
        )
    )

    ok(
        client.patch(
            f"/api/records/{created['id']}",
            headers=headers,
            json={
                "driverName": "jose editado",
                "plateNumber": "6161acr",
                "employeeCode": "1276",
                "ebap": "este",
                "initialReading": 80,
                "finalReading": 91,
                "loadVolume": 11,
                "companyType": "bomberos",
                "companyName": "andina",
                "characteristics": "editado",
            },
        )
    )
    ok(client.delete(f"/api/records/{created['id']}", headers=headers))

    logs = ok(client.get("/api/audit-logs?limit=50", headers=headers))["logs"]
    actions = {item["action"] for item in logs}
    assert "record_created" in actions
    assert "record_updated" in actions
    assert "record_deleted" in actions


def test_admin_can_download_full_backup(client):
    admin = login(client, "admin", "admin123")

    response = client.get("/api/backup.xlsx", headers=auth_header(admin["token"]))

    assert response.status_code == 200
    assert response.mimetype == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    assert "respaldo_cisternas_scpe_" in response.headers["Content-Disposition"]

    workbook = load_workbook(BytesIO(response.data), read_only=True)
    assert {"Resumen", "Registros", "Usuarios", "Auditoria"}.issubset(set(workbook.sheetnames))
