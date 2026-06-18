from __future__ import annotations

import csv
import hashlib
import io
import os
import secrets
import unicodedata
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path

from dotenv import load_dotenv
from flask import Flask, Response, jsonify, redirect, render_template, request, send_from_directory
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from openpyxl import Workbook, load_workbook
from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from sqlalchemy import or_
from werkzeug.security import check_password_hash, generate_password_hash


BASE_DIR = Path(__file__).resolve().parent
MOBILE_APP_DIR = BASE_DIR / "mobile_app"
load_dotenv(BASE_DIR / ".env")

db = SQLAlchemy()

RECORD_EXPORT_HEADERS = [
    "ID",
    "Fecha UTC",
    "Conductor",
    "Placa",
    "Codigo funcionario",
    "EBAP",
    "Lectura inicial",
    "Lectura final",
    "Volumen",
    "Tipo empresa",
    "Empresa/Entidad",
    "Caracteristicas",
    "Registrado por",
]

IMPORT_ALIASES = {
    "timestamp": {"fechautc", "fecha", "timestamp", "timestampiso", "date"},
    "driver_name": {"conductor", "chofer", "driver", "drivername", "drivername"},
    "plate_number": {"placa", "plate", "platenumber", "platenumber"},
    "employee_code": {"codigofuncionario", "funcionario", "employeecode", "employeecode", "codigo"},
    "ebap": {"ebap"},
    "initial_reading": {"lecturainicial", "inicial", "initialreading", "initialreading"},
    "final_reading": {"lecturafinal", "final", "finalreading", "finalreading"},
    "load_volume": {"volumen", "volumencalculado", "loadvolume", "loadvolume"},
    "company_type": {"tipoempresa", "tipo", "companytype", "companytype"},
    "company_name": {"empresaentidad", "empresa", "entidad", "companyname", "companyname"},
    "characteristics": {"caracteristicas", "observaciones", "characteristics"},
    "registered_by": {"registradopor", "usuario", "registeredby", "registeredby"},
}


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def to_timestamp_ms(value: datetime) -> int:
    return int(as_utc(value).timestamp() * 1000)


def normalize_database_url(value: str) -> str:
    if value.startswith("postgres://"):
        return "postgresql://" + value[len("postgres://") :]
    return value


def configured_database_uri(app: Flask) -> str:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if database_url:
        return normalize_database_url(database_url)
    return "sqlite:///" + str(Path(app.instance_path) / "cisternas.db")


class User(db.Model):
    __tablename__ = "users"

    username = db.Column(db.String(80), primary_key=True)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(30), nullable=False, default="user")
    active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=utcnow)


class Session(db.Model):
    __tablename__ = "sessions"

    id = db.Column(db.Integer, primary_key=True)
    token_hash = db.Column(db.String(64), nullable=False, unique=True, index=True)
    username = db.Column(db.String(80), db.ForeignKey("users.username"), nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=utcnow)
    last_seen_at = db.Column(db.DateTime(timezone=True), nullable=False, default=utcnow)

    user = db.relationship("User")


class WaterRecord(db.Model):
    __tablename__ = "registros_agua"

    id = db.Column(db.Integer, primary_key=True)
    timestamp = db.Column(db.DateTime(timezone=True), nullable=False, default=utcnow, index=True)
    driver_name = db.Column(db.String(160), nullable=False)
    plate_number = db.Column(db.String(60), nullable=False, index=True)
    employee_code = db.Column(db.String(80), nullable=False)
    ebap = db.Column(db.String(80), nullable=False, index=True)
    initial_reading = db.Column(db.Float, nullable=False)
    final_reading = db.Column(db.Float, nullable=False)
    load_volume = db.Column(db.Float, nullable=False)
    company_type = db.Column(db.String(120), nullable=False, index=True)
    company_name = db.Column(db.String(180), nullable=False, index=True)
    characteristics = db.Column(db.Text, nullable=True)
    registered_by = db.Column(db.String(80), db.ForeignKey("users.username"), nullable=False, index=True)
    created_at = db.Column(db.DateTime(timezone=True), nullable=False, default=utcnow)

    user = db.relationship("User")


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    Path(app.instance_path).mkdir(parents=True, exist_ok=True)

    app.config.update(
        SECRET_KEY=os.getenv("SECRET_KEY", "change-this-secret-key"),
        SQLALCHEMY_DATABASE_URI=configured_database_uri(app),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        JSON_SORT_KEYS=False,
        SESSION_DURATION_MINUTES=int(os.getenv("SESSION_DURATION_MINUTES", "30")),
    )
    if test_config:
        app.config.update(test_config)

    db.init_app(app)

    origins = [item.strip() for item in os.getenv("CORS_ORIGINS", "*").split(",") if item.strip()]
    CORS(app, resources={r"/api/*": {"origins": origins or "*"}})

    register_routes(app)

    with app.app_context():
        db.create_all()
        seed_default_users()

    return app


def seed_default_users() -> None:
    defaults = [
        ("admin", os.getenv("ADMIN_PASSWORD", "admin123"), "admin"),
        ("usuario", os.getenv("USER_PASSWORD", "usuario123"), "user"),
        ("cliente", os.getenv("CLIENT_PASSWORD", "cliente123"), "user"),
    ]
    for username, password, role in defaults:
        if User.query.get(username):
            continue
        db.session.add(
            User(
                username=username,
                password_hash=generate_password_hash(password),
                role=role,
                active=True,
                created_at=utcnow(),
            )
        )
    db.session.commit()


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_token(username: str, duration_minutes: int) -> str:
    token = secrets.token_urlsafe(32)
    db.session.add(
        Session(
            token_hash=hash_token(token),
            username=username,
            expires_at=utcnow() + timedelta(minutes=duration_minutes),
            created_at=utcnow(),
            last_seen_at=utcnow(),
        )
    )
    db.session.commit()
    return token


def get_token_from_request(data: dict | None = None) -> str:
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()
    if data and data.get("token"):
        return str(data["token"]).strip()
    return request.args.get("token", "").strip()


def find_session_user(token: str, extend: bool = True) -> User | None:
    if not token:
        return None

    session = Session.query.filter_by(token_hash=hash_token(token)).first()
    if not session or not session.user or not session.user.active:
        return None

    now = utcnow()
    if as_utc(session.expires_at) <= now:
        db.session.delete(session)
        db.session.commit()
        return None

    if extend:
        session.expires_at = now + timedelta(minutes=current_session_duration())
        session.last_seen_at = now
        db.session.commit()

    return session.user


def current_session_duration() -> int:
    return int(os.getenv("SESSION_DURATION_MINUTES", "30"))


def api_success(message: str, **extra):
    payload = {"success": True, "message": message}
    payload.update(extra)
    return jsonify(payload)


def api_error(message: str, status: int = 400):
    return jsonify({"success": False, "message": message}), status


def require_auth(admin: bool = False):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            user = find_session_user(get_token_from_request(), extend=True)
            if user is None:
                return api_error("Sesion invalida o expirada.", 401)
            if admin and user.role != "admin":
                return api_error("No tiene permisos de administrador.", 403)
            request.current_user = user
            return func(*args, **kwargs)

        return wrapper

    return decorator


def parse_float(data: dict, key: str) -> float | None:
    try:
        value = data.get(key)
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def clean_text(data: dict, key: str) -> str:
    return str(data.get(key, "")).strip()


def parse_filter_date(value: str, add_day: bool = False) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    parsed = parsed.astimezone(timezone.utc)
    if add_day:
        parsed = parsed + timedelta(days=1)
    return parsed


def record_to_dict(record: WaterRecord) -> dict:
    timestamp = as_utc(record.timestamp)
    return {
        "id": record.id,
        "timestamp": to_timestamp_ms(timestamp),
        "timestampIso": timestamp.isoformat(),
        "driverName": record.driver_name,
        "plateNumber": record.plate_number,
        "employeeCode": record.employee_code,
        "ebap": record.ebap,
        "initialReading": record.initial_reading,
        "finalReading": record.final_reading,
        "loadVolume": record.load_volume,
        "companyType": record.company_type,
        "companyName": record.company_name,
        "characteristics": record.characteristics or "",
        "registeredBy": record.registered_by,
    }


def user_to_dict(user: User) -> dict:
    return {
        "username": user.username,
        "role": user.role,
        "active": user.active,
        "createdAt": as_utc(user.created_at).isoformat(),
    }


def record_export_row(record: WaterRecord) -> list:
    return [
        record.id,
        as_utc(record.timestamp).isoformat(),
        record.driver_name,
        record.plate_number,
        record.employee_code,
        record.ebap,
        record.initial_reading,
        record.final_reading,
        record.load_volume,
        record.company_type,
        record.company_name,
        record.characteristics or "",
        record.registered_by,
    ]


def normalize_header(value) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return "".join(char.lower() for char in text if char.isalnum())


def normalized_import_row(row: dict) -> dict:
    return {normalize_header(key): value for key, value in row.items() if key is not None}


def import_value(row: dict, field: str, default: str = ""):
    aliases = IMPORT_ALIASES[field]
    for alias in aliases:
        if alias in row and row[alias] not in (None, ""):
            return row[alias]
    return default


def parse_import_float(value, field_label: str) -> float:
    if value is None or value == "":
        raise ValueError(f"{field_label} requerido.")
    try:
        return float(str(value).replace(",", ".").strip())
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field_label} no es numerico.") from exc


def parse_import_timestamp(value) -> datetime:
    if isinstance(value, datetime):
        return as_utc(value)
    if value is None or value == "":
        return utcnow()

    raw = str(value).strip()
    if not raw:
        return utcnow()

    try:
        numeric = float(raw)
        if numeric > 1_000_000_000_000:
            return datetime.fromtimestamp(numeric / 1000, tz=timezone.utc)
        if numeric > 1_000_000_000:
            return datetime.fromtimestamp(numeric, tz=timezone.utc)
    except ValueError:
        pass

    iso_value = raw.replace("Z", "+00:00")
    try:
        return as_utc(datetime.fromisoformat(iso_value))
    except ValueError:
        pass

    for fmt in ("%d/%m/%Y %H:%M", "%d/%m/%y %H:%M", "%d/%m/%Y", "%d/%m/%y"):
        try:
            return datetime.strptime(raw, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue

    return utcnow()


def read_csv_import_rows(file_storage) -> list[dict]:
    raw = file_storage.read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    return list(csv.DictReader(io.StringIO(text)))


def read_xlsx_import_rows(file_storage) -> list[dict]:
    file_storage.stream.seek(0)
    workbook = load_workbook(io.BytesIO(file_storage.read()), read_only=True, data_only=True)
    sheet = workbook.active
    rows = list(sheet.iter_rows(values_only=True))
    if not rows:
        return []
    headers = [str(value or "").strip() for value in rows[0]]
    result = []
    for row_values in rows[1:]:
        if not any(value not in (None, "") for value in row_values):
            continue
        result.append({headers[index]: row_values[index] if index < len(row_values) else "" for index in range(len(headers))})
    return result


def read_import_rows(file_storage) -> list[dict]:
    filename = (file_storage.filename or "").lower()
    if filename.endswith(".xlsx"):
        return read_xlsx_import_rows(file_storage)
    if filename.endswith(".csv"):
        return read_csv_import_rows(file_storage)
    raise ValueError("Formato no soportado. Use CSV o XLSX.")


def build_import_record(row: dict, fallback_username: str) -> WaterRecord:
    normalized = normalized_import_row(row)

    driver_name = str(import_value(normalized, "driver_name")).strip()
    plate_number = str(import_value(normalized, "plate_number")).strip().upper()
    employee_code = str(import_value(normalized, "employee_code")).strip()
    ebap = str(import_value(normalized, "ebap")).strip()
    company_type = str(import_value(normalized, "company_type")).strip()
    company_name = str(import_value(normalized, "company_name")).strip()
    characteristics = str(import_value(normalized, "characteristics")).strip()

    if not company_type and " / " in company_name:
        company_type, company_name = [part.strip() for part in company_name.split(" / ", 1)]

    required = {
        "Conductor": driver_name,
        "Placa": plate_number,
        "Codigo funcionario": employee_code,
        "EBAP": ebap,
        "Tipo empresa": company_type,
        "Empresa/Entidad": company_name,
    }
    missing = [label for label, value in required.items() if not value]
    if missing:
        raise ValueError("Faltan campos: " + ", ".join(missing) + ".")

    initial = parse_import_float(import_value(normalized, "initial_reading"), "Lectura inicial")
    final = parse_import_float(import_value(normalized, "final_reading"), "Lectura final")
    if initial < 0 or final < 0 or final <= initial:
        raise ValueError("Lecturas invalidas.")

    volume_value = import_value(normalized, "load_volume", "")
    load_volume = parse_import_float(volume_value, "Volumen") if volume_value not in (None, "") else round(final - initial, 2)
    if load_volume <= 0:
        raise ValueError("Volumen invalido.")

    registered_by = str(import_value(normalized, "registered_by", fallback_username)).strip() or fallback_username
    if not User.query.get(registered_by):
        registered_by = fallback_username

    return WaterRecord(
        timestamp=parse_import_timestamp(import_value(normalized, "timestamp", "")),
        driver_name=driver_name,
        plate_number=plate_number,
        employee_code=employee_code,
        ebap=ebap,
        initial_reading=initial,
        final_reading=final,
        load_volume=round(load_volume, 2),
        company_type=company_type,
        company_name=company_name,
        characteristics=characteristics,
        registered_by=registered_by,
    )


def login_action(data: dict):
    username = clean_text(data, "username")
    password = str(data.get("password", ""))
    if not username or not password:
        return api_error("Usuario y contrasena requeridos.")

    user = User.query.get(username)
    if not user or not user.active or not check_password_hash(user.password_hash, password):
        return api_error("Credenciales incorrectas.", 401)

    token = issue_token(user.username, current_session_duration())
    return api_success(
        "Login exitoso",
        token=token,
        user={"username": user.username, "role": user.role},
    )


def validate_token_action(data: dict):
    user = find_session_user(get_token_from_request(data), extend=True)
    if user is None:
        return api_error("Token invalido o expirado.", 401)
    return api_success("Token valido", user={"username": user.username, "role": user.role})


def save_record_action(data: dict):
    user = find_session_user(get_token_from_request(data), extend=True)
    if user is None:
        return api_error("Sesion expirada. Inicie sesion nuevamente.", 401)

    required_text = {
        "driverName": clean_text(data, "driverName"),
        "plateNumber": clean_text(data, "plateNumber").upper(),
        "employeeCode": clean_text(data, "employeeCode"),
        "ebap": clean_text(data, "ebap"),
        "companyType": clean_text(data, "companyType"),
        "companyName": clean_text(data, "companyName"),
    }
    if any(not value for value in required_text.values()):
        return api_error("Complete todos los campos obligatorios.")

    initial = parse_float(data, "initialReading")
    final = parse_float(data, "finalReading")
    volume = parse_float(data, "loadVolume")
    if initial is None or final is None or initial < 0 or final < 0 or final <= initial:
        return api_error("Las lecturas no son validas.")

    calculated_volume = round(final - initial, 2)
    if volume is None or volume <= 0:
        volume = calculated_volume
    if volume <= 0:
        return api_error("El volumen calculado debe ser mayor a cero.")

    record = WaterRecord(
        timestamp=utcnow(),
        driver_name=required_text["driverName"],
        plate_number=required_text["plateNumber"],
        employee_code=required_text["employeeCode"],
        ebap=required_text["ebap"],
        initial_reading=initial,
        final_reading=final,
        load_volume=round(volume, 2),
        company_type=required_text["companyType"],
        company_name=required_text["companyName"],
        characteristics=clean_text(data, "characteristics"),
        registered_by=user.username,
    )
    db.session.add(record)
    db.session.commit()
    return api_success("Datos guardados en la base central", id=record.id)


def list_records_for_user(data: dict):
    user = find_session_user(get_token_from_request(data), extend=True)
    if user is None:
        return api_error("Sesion expirada. Inicie sesion nuevamente.", 401)

    query = WaterRecord.query
    if user.role != "admin":
        query = query.filter(WaterRecord.registered_by == user.username)
    records = query.order_by(WaterRecord.id.desc()).limit(500).all()
    return api_success("Registros cargados", records=[record_to_dict(item) for item in records])


def apply_record_filters(query):
    q = request.args.get("q", "").strip()
    ebap = request.args.get("ebap", "").strip()
    company_type = request.args.get("companyType", "").strip()
    date_from = request.args.get("dateFrom", "").strip()
    date_to = request.args.get("dateTo", "").strip()

    if q:
        pattern = f"%{q}%"
        query = query.filter(
            or_(
                WaterRecord.driver_name.ilike(pattern),
                WaterRecord.plate_number.ilike(pattern),
                WaterRecord.employee_code.ilike(pattern),
                WaterRecord.company_name.ilike(pattern),
                WaterRecord.registered_by.ilike(pattern),
            )
        )
    if ebap:
        query = query.filter(WaterRecord.ebap == ebap)
    if company_type:
        query = query.filter(WaterRecord.company_type == company_type)
    start = parse_filter_date(date_from)
    if start:
        query = query.filter(WaterRecord.timestamp >= start)
    end = parse_filter_date(date_to, add_day=True)
    if end:
        query = query.filter(WaterRecord.timestamp < end)
    return query


def register_routes(app: Flask) -> None:
    @app.get("/")
    def index():
        return redirect("/admin")

    @app.get("/admin")
    def admin_panel():
        return render_template("admin.html")

    @app.get("/app")
    @app.get("/app/")
    def mobile_web_app():
        return send_from_directory(MOBILE_APP_DIR, "index.html")

    @app.get("/app/<path:filename>")
    def mobile_web_asset(filename: str):
        return send_from_directory(MOBILE_APP_DIR, filename)

    @app.get("/api/health")
    def health():
        return api_success("API operativa")

    @app.post("/api/mobile")
    def mobile_api():
        data = request.get_json(silent=True) or {}
        action = str(data.get("action", "")).strip()
        if action == "login":
            return login_action(data)
        if action == "validateToken":
            return validate_token_action(data)
        if action == "saveData":
            return save_record_action(data)
        if action == "listData":
            return list_records_for_user(data)
        if action == "test":
            return api_success("API central operativa")
        return api_error("Accion no valida.")

    @app.post("/api/auth/login")
    def api_login():
        return login_action(request.get_json(silent=True) or {})

    @app.post("/api/auth/validate")
    def api_validate():
        return validate_token_action(request.get_json(silent=True) or {})

    @app.post("/api/auth/logout")
    def api_logout():
        token = get_token_from_request(request.get_json(silent=True) or {})
        if token:
            Session.query.filter_by(token_hash=hash_token(token)).delete()
            db.session.commit()
        return api_success("Sesion cerrada")

    @app.get("/api/records")
    @require_auth(admin=True)
    def api_records():
        limit = min(max(int(request.args.get("limit", "500")), 1), 2000)
        query = apply_record_filters(WaterRecord.query)
        records = query.order_by(WaterRecord.id.desc()).limit(limit).all()
        total_volume = round(sum(item.load_volume for item in records), 2)
        return api_success(
            "Registros cargados",
            records=[record_to_dict(item) for item in records],
            total=len(records),
            totalVolume=total_volume,
        )

    @app.get("/api/records/export.csv")
    @require_auth(admin=True)
    def export_records_csv():
        query = apply_record_filters(WaterRecord.query)
        records = query.order_by(WaterRecord.id.desc()).limit(10000).all()

        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(RECORD_EXPORT_HEADERS)
        for record in records:
            writer.writerow(record_export_row(record))

        return Response(
            output.getvalue(),
            mimetype="text/csv; charset=utf-8",
            headers={"Content-Disposition": "attachment; filename=registros_cisternas.csv"},
        )

    @app.get("/api/records/export.xlsx")
    @require_auth(admin=True)
    def export_records_xlsx():
        query = apply_record_filters(WaterRecord.query)
        records = query.order_by(WaterRecord.id.desc()).limit(10000).all()

        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Registros"
        sheet.append(RECORD_EXPORT_HEADERS)
        for record in records:
            sheet.append(record_export_row(record))

        widths = [8, 24, 26, 14, 18, 14, 16, 16, 12, 24, 28, 34, 18]
        for index, width in enumerate(widths, start=1):
            sheet.column_dimensions[chr(64 + index)].width = width

        output = io.BytesIO()
        workbook.save(output)
        output.seek(0)
        return Response(
            output.getvalue(),
            mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": "attachment; filename=registros_cisternas.xlsx"},
        )

    @app.get("/api/records/export.pdf")
    @require_auth(admin=True)
    def export_records_pdf():
        query = apply_record_filters(WaterRecord.query)
        records = query.order_by(WaterRecord.id.desc()).limit(2000).all()

        output = io.BytesIO()
        doc = SimpleDocTemplate(
            output,
            pagesize=landscape(letter),
            rightMargin=24,
            leftMargin=24,
            topMargin=24,
            bottomMargin=24,
        )
        styles = getSampleStyleSheet()
        elements = [
            Paragraph("Registro de carguio de cisternas - SCPE", styles["Title"]),
            Paragraph(f"Registros exportados: {len(records)}", styles["Normal"]),
            Spacer(1, 12),
        ]

        pdf_headers = ["ID", "Fecha", "Conductor", "Placa", "Func.", "EBAP", "Lecturas", "Vol.", "Empresa", "Obs.", "Usuario"]
        table_data = [pdf_headers]
        for record in records:
            row = [
                record.id,
                as_utc(record.timestamp).strftime("%d/%m/%Y %H:%M"),
                record.driver_name,
                record.plate_number,
                record.employee_code,
                record.ebap,
                f"{record.initial_reading:g} -> {record.final_reading:g}",
                f"{record.load_volume:.2f}",
                f"{record.company_type} / {record.company_name}",
                record.characteristics or "",
                record.registered_by,
            ]
            table_data.append([Paragraph(str(value), styles["BodyText"]) for value in row])

        table = Table(table_data, repeatRows=1, colWidths=[28, 76, 90, 58, 52, 58, 68, 44, 130, 120, 58])
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0b3f59")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#cfe0ed")),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTSIZE", (0, 0), (-1, -1), 7),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f1fbfd")]),
                ]
            )
        )
        elements.append(table)
        doc.build(elements)
        output.seek(0)
        return Response(
            output.getvalue(),
            mimetype="application/pdf",
            headers={"Content-Disposition": "attachment; filename=registros_cisternas.pdf"},
        )

    @app.post("/api/records/import")
    @require_auth(admin=True)
    def import_records():
        file_storage = request.files.get("file")
        if file_storage is None or not file_storage.filename:
            return api_error("Seleccione un archivo CSV o XLSX.")

        try:
            rows = read_import_rows(file_storage)
        except ValueError as exc:
            return api_error(str(exc))

        imported = 0
        skipped = 0
        errors = []
        for index, row in enumerate(rows, start=2):
            try:
                db.session.add(build_import_record(row, request.current_user.username))
                imported += 1
            except ValueError as exc:
                skipped += 1
                if len(errors) < 20:
                    errors.append(f"Fila {index}: {exc}")

        if imported:
            db.session.commit()
        else:
            db.session.rollback()

        return api_success(
            "Importacion finalizada",
            imported=imported,
            skipped=skipped,
            errors=errors,
        )

    @app.get("/api/users")
    @require_auth(admin=True)
    def api_users():
        users = User.query.order_by(User.username.asc()).all()
        return api_success("Usuarios cargados", users=[user_to_dict(user) for user in users])

    @app.post("/api/users")
    @require_auth(admin=True)
    def api_create_user():
        data = request.get_json(silent=True) or {}
        username = clean_text(data, "username").lower()
        password = str(data.get("password", ""))
        role = clean_text(data, "role") or "user"

        if not username or not password:
            return api_error("Usuario y contrasena requeridos.")
        if len(username) < 3:
            return api_error("El usuario debe tener al menos 3 caracteres.")
        if len(password) < 6:
            return api_error("La contrasena debe tener al menos 6 caracteres.")
        if role not in {"admin", "user"}:
            return api_error("Rol no valido.")
        if User.query.get(username):
            return api_error("Ese usuario ya existe.")

        user = User(
            username=username,
            password_hash=generate_password_hash(password),
            role=role,
            active=True,
            created_at=utcnow(),
        )
        db.session.add(user)
        db.session.commit()
        return api_success("Usuario creado", user=user_to_dict(user))

    @app.patch("/api/users/<username>")
    @require_auth(admin=True)
    def api_update_user(username: str):
        data = request.get_json(silent=True) or {}
        target_username = username.strip().lower()
        user = User.query.get(target_username)
        if not user:
            return api_error("Usuario no encontrado.", 404)

        current_user = request.current_user
        if user.username == current_user.username and data.get("active") is False:
            return api_error("No puede desactivar su propio usuario administrador.")

        if "active" in data:
            user.active = bool(data["active"])

        if "role" in data:
            role = clean_text(data, "role")
            if role not in {"admin", "user"}:
                return api_error("Rol no valido.")
            if user.username == current_user.username and role != "admin":
                return api_error("No puede quitarse su propio rol administrador.")
            user.role = role

        db.session.commit()
        return api_success("Usuario actualizado", user=user_to_dict(user))


app = create_app()


if __name__ == "__main__":
    app.run(host=os.getenv("HOST", "0.0.0.0"), port=int(os.getenv("PORT", "5000")), debug=True)
