# Configurar la API de PythonAnywhere

La URL de administración `https://www.pythonanywhere.com/user/crismp/` no es una API. Consulte la pestaña **Web** de esa cuenta y use el dominio público de la aplicación desplegada.

`pythonanywhere.json.example` propone `https://crismp.pythonanywhere.com/api/mobile`. Confirme ese dominio antes de usarlo. Si la cuenta usa otro dominio o región, cambie la URL del ejemplo. La app conserva su dirección predeterminada actual hasta compilarla con otra configuración.

Desde la carpeta `flutter_app`, compruebe primero el servidor:

```powershell
powershell -NoProfile -File .\tool\check_api.ps1 -ConfigFile .\config\pythonanywhere.json.example
```

El script consulta `GET /api/health` y `POST /api/mobile` con `{"action":"test"}`. Exige HTTPS, rechaza credenciales en la URL y no sigue redirecciones. No inicia sesiones ni crea registros. Devuelve código 0 si ambas rutas responden con JSON `success: true`, 1 si el servicio falla y 2 si la configuración no es válida. Un HTTP 404 significa que esa ruta no está publicada; revise el despliegue antes de compilar. Esta prueba confirma disponibilidad de la API, no el funcionamiento de la base de datos.

Una vez que ambas comprobaciones pasen:

```powershell
flutter run --dart-define-from-file=config/pythonanywhere.json.example
flutter build apk --debug --target-platform android-arm64 --split-per-abi --dart-define-from-file=config/pythonanywhere.json.example
```

La misma opción se utiliza al compilar iOS en un Mac:

```bash
flutter build ios --dart-define-from-file=config/pythonanywhere.json.example
```

Cambiar este archivo después de generar el APK no cambia la dirección dentro de ese APK: es necesario volver a compilar e instalar la nueva versión. Las variables `--dart-define` se incorporan al binario; este archivo contiene solo una URL pública. No incluya contraseñas, tokens, claves de firma ni credenciales de la base de datos.

El workflow de GitHub utiliza Flutter 3.47.7 y Java 21 para analizar, ejecutar las pruebas y generar un APK debug ARM64 descargable como artefacto. Puede definir la variable de repositorio **MOBILE_API_URL** con la URL pública confirmada; el workflow comprobará la API antes de compilar con ella. Sin esa variable, compila con el valor predeterminado de la app. No publica en Play Store ni App Store.

Las acciones oficiales de GitHub están fijadas a los commits publicados de [checkout 4.2.2](https://github.com/actions/checkout/releases/tag/v4.2.2), [setup-java 4.7.1](https://github.com/actions/setup-java/releases/tag/v4.7.1) y [upload-artifact 4.6.2](https://github.com/actions/upload-artifact/releases/tag/v4.6.2). Flutter se obtiene directamente de su repositorio oficial y se verifica el commit probado localmente.
