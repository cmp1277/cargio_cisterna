# Backend Cisternas

API Flask para centralizar registros de cargas de agua y servir el panel administrador.

## Instalar

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python app.py
```

Panel administrador:

```text
http://localhost:5000/admin
```

API movil:

```text
POST /api/mobile
```

## Acciones compatibles con la app movil

```json
{ "action": "test" }
```

```json
{ "action": "login", "username": "usuario", "password": "CONTRASENA_CONFIGURADA" }
```

```json
{ "action": "validateToken", "token": "..." }
```

```json
{
  "action": "saveData",
  "token": "...",
  "driverName": "Juan Perez",
  "plateNumber": "ABC123",
  "employeeCode": "1277",
  "ebap": "Norte",
  "initialReading": 10,
  "finalReading": 20,
  "loadVolume": 10,
  "companyType": "Particular",
  "companyName": "Cliente",
  "characteristics": "Sin observaciones"
}
```

## Variables de entorno

- `SECRET_KEY`: clave de Flask.
- `SESSION_DURATION_MINUTES`: duracion de sesion.
- `CORS_ORIGINS`: origenes permitidos. Usa `*` si la app carga desde WebView local.
- `DATABASE_URL`: conexion PostgreSQL. Si queda vacio, usa SQLite local.
- `ADMIN_PASSWORD`, `USER_PASSWORD`, `CLIENT_PASSWORD`: contrasenas iniciales.
- `MAX_UPLOAD_BYTES`: limite maximo para importaciones CSV/XLSX.

Las contrasenas iniciales solo se aplican si el usuario no existe todavia. Si no configuras una variable de contrasena, ese usuario inicial no se crea. Los valores inseguros `admin123`, `usuario123` y `cliente123` se bloquean fuera de pruebas automatizadas.

## Produccion HTTPS

El backend queda listo para desplegar con:

- `Procfile`: servicios Python tipo Render/Railway/Heroku.
- `Dockerfile`: VPS, Railway, Fly.io u otro hosting con contenedores.
- `render.yaml`: blueprint para Render con PostgreSQL.

Despues de publicar, configura en la app movil:

```html
<meta name="api-url" content="https://TU-SERVICIO-HTTPS/api/mobile">
```
