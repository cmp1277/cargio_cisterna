# DevSecOps aplicado

Esta app ya incorpora controles DevSecOps en codigo, pruebas y pipeline.

## Controles implementados

- HTTPS para API y app web en Render.
- Autenticacion con usuarios y roles.
- Hash de contrasenas con Werkzeug.
- Tokens de sesion con expiracion.
- Validacion de datos del registro y placa con formato `2127 - ACC`.
- Normalizacion de datos en mayusculas.
- Rate limit de login contra fuerza bruta.
- Cabeceras HTTP de seguridad: CSP, HSTS en HTTPS, `X-Frame-Options`, `nosniff`, `Referrer-Policy` y `Permissions-Policy`.
- Auditoria de eventos: login exitoso/fallido, bloqueo por rate limit, creacion/edicion/eliminacion de registros, importaciones y gestion de usuarios.
- Panel administrador con tabla de auditoria.
- Pruebas automatizadas con `pytest`.
- Analisis estatico de seguridad con `bandit`.
- Auditoria de dependencias Python con `pip-audit`.
- Compilacion Android automatizada en GitHub Actions.

## Pipeline

El archivo `.github/workflows/devsecops.yml` corre en cada `push` o `pull_request` a `main`.

El pipeline ejecuta:

- Tests del backend.
- Escaneo estatico de seguridad.
- Revision de vulnerabilidades de dependencias.
- Build debug de la app Android.

## Comandos locales

```powershell
cd backend
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\bandit.exe -r . -x .venv,tests -ll
.\.venv\Scripts\pip-audit.exe -r requirements.txt
```

```powershell
cd APP_MOVIL_CISTERNAS
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
.\gradlew.bat assembleDebug
```

## Variables recomendadas en Render

- `SECRET_KEY`: clave larga y aleatoria.
- `DATABASE_URL`: PostgreSQL de Render.
- `ADMIN_PASSWORD`: cambiar el valor por defecto.
- `USER_PASSWORD`: cambiar el valor por defecto.
- `CLIENT_PASSWORD`: cambiar el valor por defecto.
- `SESSION_DURATION_MINUTES`: por ejemplo `30`.
- `LOGIN_RATE_LIMIT_MAX_ATTEMPTS`: por ejemplo `8`.
- `LOGIN_RATE_LIMIT_WINDOW_MINUTES`: por ejemplo `15`.
- `CORS_ORIGINS`: restringir al dominio real cuando ya no se necesite acceso amplio.

## Pendiente operativo

- Activar backups automaticos en PostgreSQL/Render.
- Proteger la rama `main` en GitHub para exigir que el workflow pase antes de fusionar cambios.
- Rotar contrasenas iniciales en produccion.
- Revisar periodicamente el panel de auditoria.
