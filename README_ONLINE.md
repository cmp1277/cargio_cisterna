# Cisternas Online: app movil + API + panel administrador

Esta version centraliza los datos en un backend Flask. Los celulares ya no guardan la base localmente: todos envian los registros a una API y el administrador los consulta desde un panel web.

## Estructura

- `backend/`: API, base central y panel administrador.
- `APP_MOVIL_CISTERNAS/`: app Android WebView conectada a la API.

## Ejecutar backend en desarrollo

Desde PowerShell:

```powershell
cd "F:\SCPE\NUBE\CARGIO DE CISTERNAS CON LOGIN\backend"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python app.py
```

Abre el panel administrador en:

```text
http://localhost:5000/admin
```

Usuarios iniciales:

- `admin` / `admin123`
- `usuario` / `usuario123`
- `cliente` / `cliente123`

## Configurar la app movil

Edita:

```text
APP_MOVIL_CISTERNAS/app/src/main/assets/www/index.html
```

Cambia:

```html
<meta name="api-url" content="https://TU-DOMINIO.com/api/mobile">
```

Por la URL real del backend, por ejemplo:

```html
<meta name="api-url" content="https://cisternas.midominio.com/api/mobile">
```

Despues recompila e instala el APK en los celulares.

## Base de datos

Por defecto, desarrollo usa SQLite en:

```text
backend/instance/cisternas.db
```

Para produccion, configura `DATABASE_URL` en `backend/.env` con PostgreSQL:

```text
DATABASE_URL=postgresql://usuario:password@host:5432/cisternas
```

## Despliegue recomendado

Para que varios celulares funcionen desde cualquier lugar, necesitas publicar `backend/` en un servidor con HTTPS. Opciones practicas:

- Render, Railway, Fly.io o VPS.
- PostgreSQL administrado para la base central.
- Dominio o subdominio HTTPS para la API.

No pongas credenciales de base de datos dentro del APK. La app solo debe conocer la URL HTTPS de la API.
