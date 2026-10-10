# App Movil Cisternas

## Version Flutter para Android e iOS

La migracion nativa esta en [`flutter_app`](flutter_app/README.md). Abre esa subcarpeta en Android Studio para trabajar con Flutter. Consulta [`flutter_app/VALIDACION.md`](flutter_app/VALIDACION.md) para conocer las comprobaciones realizadas y los pasos pendientes.

La configuracion para alojar la API en la cuenta `crismp` de PythonAnywhere se documenta en [`backend/deploy/PYTHONANYWHERE.md`](../backend/deploy/PYTHONANYWHERE.md). El codigo de esta app y del backend forma parte del repositorio [`cmp1277/cargio_cisterna`](https://github.com/cmp1277/cargio_cisterna).

El proyecto Android de esta carpeta se conserva como referencia. Su `MainActivity` actual carga la pagina remota `https://cisternas-api-wqac.onrender.com/app`; el HTML local de `assets/www` no se ejecuta en esta version. Las instrucciones siguientes describen el proyecto anterior.

Proyecto Android WebView para registrar cargas de agua desde celulares.

Esta version ya no guarda los registros en SQLite local del celular. La app envia login y registros a una API central configurada en:

`app/src/main/assets/www/index.html`

Busca esta linea y reemplaza la URL por tu backend publicado:

```html
<meta name="api-url" content="https://TU-DOMINIO.com/api/mobile">
```

## Contenido

- `app/src/main/assets/www/index.html`: interfaz movil y llamadas a la API central.
- `app/src/main/assets/www/logo.png`: logo usado por la pagina.
- `app/src/main/java/com/scpe/cisternas/MainActivity.java`: WebView nativo que carga la pagina local.

## Usuarios iniciales

Estos usuarios se crean en el backend, no en el celular:

- Administrador: `admin` / valor definido en `ADMIN_PASSWORD`
- Usuario: `usuario` / valor definido en `USER_PASSWORD`
- Cliente: `cliente` / valor definido en `CLIENT_PASSWORD`

Cambia esas contrasenas en `backend/.env` antes de ponerlo en produccion.

## Abrir en Android Studio

1. Abre Android Studio.
2. Selecciona `Open`.
3. Abre esta carpeta: `APP_MOVIL_CISTERNAS`.
4. Configura la URL HTTPS del backend en `app/src/main/assets/www/index.html`.
5. Ejecuta en un emulador o celular con `Run`.

## Generar APK

En Android Studio:

1. Menu `Build`.
2. `Build Bundle(s) / APK(s)`.
3. `Build APK(s)`.

El APK debug queda normalmente en:

`app/build/outputs/apk/debug/app-debug.apk`

Por terminal, desde esta carpeta:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat assembleDebug
```

## Notas tecnicas

- La app necesita internet para iniciar sesion y guardar registros.
- `AndroidManifest.xml` mantiene `usesCleartextTraffic="false"`, por lo que la URL real debe ser HTTPS.
- Si quieres probar contra una IP local con `http://`, debes habilitar trafico claro temporalmente o usar un tunel HTTPS.
