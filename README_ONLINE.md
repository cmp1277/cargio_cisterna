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

El backend solo los crea si defines `ADMIN_PASSWORD`, `USER_PASSWORD` y `CLIENT_PASSWORD` con contrasenas seguras. No uses valores conocidos como `admin123`, `usuario123` o `cliente123`.

Desde el panel administrador puedes crear mas usuarios. Usa rol `Administrador` para acceso total al panel y rol `Cliente / Usuario` para registrar cargas desde `/app` o desde el APK.

Tambien puedes desactivar usuarios que ya no se utilicen. La desactivacion bloquea el login, pero conserva los registros historicos asociados a ese usuario.

El panel administrador permite importar registros desde archivos `.csv` o `.xlsx`, y exportar los registros filtrados en `.csv`, `.xlsx` o `.pdf`.

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

## Publicar en Render

1. Entra a:

```text
https://dashboard.render.com/
```

2. Conecta tu cuenta de GitHub.

3. Selecciona `New` > `Blueprint`.

4. Elige el repositorio:

```text
cmp1277/cargio_cisterna
```

5. En `Blueprint Path`, coloca:

```text
backend/render.yaml
```

6. Render mostrara un servicio web `cisternas-api` y una base PostgreSQL `cisternas-db`.

7. El Blueprint usa planes gratuitos:

```text
Web Service: free
PostgreSQL: free
```

La base PostgreSQL gratuita de Render expira despues de 30 dias. Para uso real permanente, cambia la base a un plan pagado antes de depender de ella en produccion.

8. Antes de desplegar, define las variables marcadas como secretas:

```text
ADMIN_PASSWORD
USER_PASSWORD
CLIENT_PASSWORD
```

Usa contrasenas largas y unicas. Si dejas una de estas variables vacia, ese usuario inicial no se creara.

9. Haz clic en `Deploy Blueprint`.

Cuando termine, Render te dara una URL parecida a:

```text
https://cisternas-api.onrender.com
```

La API movil sera:

```text
https://cisternas-api.onrender.com/api/mobile
```

El panel administrador sera:

```text
https://cisternas-api.onrender.com/admin
```

La app web para registrar desde navegador sera:

```text
https://cisternas-api.onrender.com/app
```

Despues cambia esa URL en la app movil y recompila el APK.
