# Publicar Cisternas en PythonAnywhere

Preparación para la cuenta `crismp`. El enlace `https://www.pythonanywhere.com/user/crismp/` es el panel de la cuenta, no la API. El dominio esperado es `https://crismp.pythonanywhere.com`, pero debe confirmarse en la pestaña **Web**. La comprobación inicial devolvió 404; todavía no se ha verificado un backend desplegado allí.

## 1. Confirmar la base y conservar los datos

Antes de cambiar los celulares, identificar qué base contiene los registros actuales: la PostgreSQL de Render, una base de PythonAnywhere o un archivo SQLite. Cambiar el endpoint no copia registros, usuarios ni contraseñas. Hacer un respaldo completo de esa base y comprobar su restauración antes del cambio. No sobrescribir una base existente ni publicar bases o respaldos en GitHub.

PythonAnywhere ofrece SQLite a todas las cuentas, MySQL a planes pagados y cuentas gratuitas anteriores al 15 de enero de 2026 (8 de enero en el sistema europeo), y PostgreSQL como complemento pagado. Las conexiones a bases externas requieren un plan pagado. Verificar la pestaña **Databases** y el plan de `crismp`; no asumir que MySQL está disponible. [Condiciones oficiales](https://help.pythonanywhere.com/pages/KindsOfDatabases).

Para varios operadores, utilizar una base MySQL o PostgreSQL compatible con el plan. SQLite puede servir para pruebas de bajo volumen; PythonAnywhere no la recomienda como base de producción. Si se elige SQLite, usar una ruta absoluta persistente fuera del repositorio y crear previamente su directorio.

El XLSX del panel conserva información visible, pero no contiene los hashes de contraseña ni todos los campos originales. La importación CSV/XLSX tampoco restaura usuarios, auditoría o IDs originales. Para una migración íntegra se necesita un respaldo de base de datos y una restauración adecuada al motor elegido. Las sesiones pueden caducar; los usuarios deben poder iniciar sesión nuevamente. La preparación de este repositorio no migra datos.

## 2. Descargar el código y crear el entorno

En una consola Bash de PythonAnywhere, con el repositorio ya publicado y accesible:

```bash
cd /home/crismp
git clone https://github.com/cmp1277/cargio_cisterna.git
python3.12 -m venv /home/crismp/.virtualenvs/cisternas
source /home/crismp/.virtualenvs/cisternas/bin/activate
python -m pip install -r /home/crismp/cargio_cisterna/backend/requirements-pythonanywhere.txt
```

Si la carpeta ya existe, revisar su estado y actualizarla sin sobrescribir cambios locales. Si el repositorio es privado, autenticar Git por un mecanismo de la cuenta sin incrustar tokens en comandos, archivos publicados o URLs compartidas. La versión Python elegida en **Web** debe coincidir con la del virtualenv.

## 3. Configurar las variables privadas

Crear `/home/crismp/.config/cisternas/` y copiar allí `backend/deploy/pythonanywhere.env.example` con el nombre `backend.env`. Completar el archivo privado mediante el editor de PythonAnywhere. Mantenerlo fuera del repositorio y accesible solamente a la cuenta.

Valores necesarios:

- `SECRET_KEY`: clave privada larga y estable de esta instalación.
- `DATABASE_URL`: URI de la base elegida. El WSGI rechaza un valor vacío para evitar crear SQLite accidentalmente.
- `CORS_ORIGINS`: el origen HTTPS confirmado en **Web**; previsiblemente `https://crismp.pythonanywhere.com`.
- `ADMIN_PASSWORD`, `USER_PASSWORD`, `CLIENT_PASSWORD`: contraseñas iniciales si se necesita crear esos usuarios en una base nueva. Si ya existen, estas variables no cambian sus contraseñas. No usar claves conocidas o de ejemplo.

Para MySQL, copiar el host, usuario y nombre completo de la pestaña **Databases**. El nombre suele llevar el prefijo de la cuenta y un dólar. La estructura de URI es:

```text
mysql+pymysql://USUARIO:CONTRASENA_URLENCODED@HOST/NOMBRE_COMPLETO?charset=utf8mb4
```

Codificar los caracteres especiales de la contraseña según URL; no pegar la URI en el chat. El ejemplo privado incluye comillas simples para conservar el signo `$`. El repositorio instala `PyMySQL[rsa]==1.2.3`, versión estable verificada en [PyPI](https://pypi.org/project/PyMySQL/1.2.3/), incluido el soporte para autenticación SHA-2.

El backend configura reciclado de conexiones MySQL a los 280 segundos y comprobación de conexión antes de usarla. PythonAnywhere cierra conexiones inactivas tras 300 segundos. El WSGI libera las conexiones usadas durante la inicialización antes de crear workers. [Guía oficial de SQLAlchemy](https://help.pythonanywhere.com/pages/UsingSQLAlchemywithMySQL/).

## 4. Crear o configurar la aplicación web

En **Web**, revisar primero si ya existe una aplicación. Para una nueva, elegir **Manual configuration**, Python 3.12 y el dominio de la cuenta. Configurar:

```text
Source code: /home/crismp/cargio_cisterna/backend
Working directory: /home/crismp/cargio_cisterna/backend
Virtualenv: /home/crismp/.virtualenvs/cisternas
```

Abrir el archivo WSGI enlazado en **Web**. Si ya existe una configuración operativa, conservar una copia antes de cambiarla. Su contenido debe cargar la entrada preparada:

```python
import os
import runpy

os.environ["CISTERNAS_REPO_DIR"] = "/home/crismp/cargio_cisterna"
os.environ["CISTERNAS_ENV_FILE"] = "/home/crismp/.config/cisternas/backend.env"
application = runpy.run_path(
    "/home/crismp/cargio_cisterna/backend/deploy/pythonanywhere_wsgi.py"
)["application"]
```

Las rutas se pueden adaptar usando las dos variables anteriores. El archivo privado se carga antes de importar Flask y sus valores prevalecen sobre valores de entorno anteriores. No ejecutar `python app.py` ni Gunicorn para publicar: PythonAnywhere utiliza el WSGI configurado en **Web**. Activar HTTPS y recargar la aplicación. [Guía oficial de Flask](https://help.pythonanywhere.com/pages/Flask/).

Al importar la aplicación se crean las tablas faltantes y los usuarios iniciales configurados; no se migran columnas de tablas existentes. Revisar que la base seleccionada sea la correcta antes de recargar.

## 5. Verificar y conectar Flutter

Con el dominio confirmado, comprobar estas rutas:

```text
GET  https://crismp.pythonanywhere.com/api/health
POST https://crismp.pythonanywhere.com/api/mobile
     {"action":"test"}
GET  https://crismp.pythonanywhere.com/admin
GET  https://crismp.pythonanywhere.com/app
```

Las dos primeras deben devolver JSON con `success: true`. Después verificar inicio de sesión y, con una cuenta autorizada, guardar un registro de prueba identificable y comprobarlo en el panel. La comprobación de salud no prueba credenciales ni escritura de registros.

Para compilar la app Flutter contra el dominio confirmado:

```bash
cd APP_MOVIL_CISTERNAS/flutter_app
flutter build apk --release --dart-define=API_URL=https://crismp.pythonanywhere.com/api/mobile
```

La compilación release requiere configurar la firma Android descrita en el README de Flutter. Para una prueba local se puede compilar con `--debug`. La versión iOS debe compilarse y firmarse desde macOS. Las credenciales de la base permanecen en el servidor; Flutter solo recibe la URL HTTPS.

No retirar la API anterior hasta verificar datos, inicio de sesión, guardado y distribución de la nueva app. Para evitar registros repartidos entre dos bases durante la transición, acordar una ventana de cambio o una estrategia de migración antes de mover usuarios.

## Actualizaciones y pruebas

Actualizar el repositorio, instalar los requisitos en el virtualenv y recargar desde **Web**. Mantener el archivo privado y los datos fuera de la carpeta de código. Consultar el error log de PythonAnywhere si el arranque falla; no publicar logs que incluyan datos de conexión.

Las pruebas locales de despliegue usan archivos temporales y conexiones simuladas:

```bash
cd backend
python -m pytest tests/test_pythonanywhere_deploy.py
```

Comprueban configuración MySQL, preservación de opciones personalizadas, rechazo de configuración incompleta y liberación de conexiones WSGI. No sustituyen la prueba de la cuenta, la base real ni el despliegue HTTPS; esos puntos siguen pendientes de acceso y configuración de `crismp`.
