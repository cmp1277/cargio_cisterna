# Estado de validación · SCPE Cisternas

Revisión: 9 de octubre de 2026.

## Comprobaciones completadas

- Flutter 3.47.7 estable y Dart 3.13.5; dependencias resueltas en pubspec.lock.
- flutter analyze: sin errores ni advertencias.
- flutter test: 50 pruebas aprobadas de dominio, contrato HTTP, sesión y widgets.
- Vistas previas generadas con Flutter y fuentes reales; revisadas visualmente en móvil y pantalla ancha.
- Pruebas de interfaz a 360×800 y 320×700, con texto al 180 %.
- Cálculo decimal exacto, validación de placa y catálogos, errores HTTP/JSON, caducidad, logout remoto, operaciones concurrentes y conservación del formulario ante fallos.
- Se cotejó el HTML original con ../backend/mobile_app/index.html y el contrato con ../backend/app.py.
- Los iconos iOS tienen las dimensiones requeridas y formato RGB sin canal alfa.

## Compilación

- Android: APK debug ARM64 compilado correctamente; `aapt` confirma `com.scpe.cisternas`, versión `2.0.0`, Android mínimo API 24 y objetivo API 36.
- Artefacto: [app-arm64-v8a-debug.apk](build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk), 87.643.019 bytes. El APK dividido usa `versionCode=2005` por el ajuste de ABI de Flutter; el proyecto declara `2.0.0+5`.
- SHA-256: `BB0193A80A11B4739CBE67C203C8C032CE386EA897418CCAF9F3CA174FF11236`.
- Comando: `flutter build apk --debug --target-platform android-arm64 --split-per-abi`.
- iOS: proyecto anfitrión y Keychain configurados; compilación y firma pendientes en macOS/Xcode.
- Distribución: no se generaron builds release firmados ni se publicó en tiendas.

## Límites de estas comprobaciones

La preparación para PythonAnywhere incluye WSGI, configuración de MySQL y un perfil de API para Flutter. La suite completa del backend pasó 27 pruebas con datos aislados. El verificador de disponibilidad confirmó HTTP 404 en `https://crismp.pythonanywhere.com/api/health` y en `POST /api/mobile` con `action:test`; el despliegue remoto y la migración de datos siguen pendientes. El APK citado arriba conserva la API predeterminada de Render y debe recompilarse cuando el nuevo servidor esté validado.

Las pruebas usan respuestas simuladas; no se enviaron registros a producción. La página remota y la acción pública test de la API no respondieron dentro del tiempo de espera durante la comprobación de red. El contrato se verificó en el código local del servidor, no mediante una cuenta real.

Falta una prueba de acceso y guardado con cuenta de pruebas, y validación de almacenamiento seguro/reanudación en dispositivos físicos Android e iOS. Estas comprobaciones son necesarias antes de distribuir.

## Abrir el proyecto

Abre la carpeta flutter_app en Android Studio, no el build.gradle del proyecto Android anterior. Instala los complementos Flutter/Dart y selecciona un SDK de Flutter. Versiones mínimas de las plantillas utilizadas: Android 7.0/API 24 e iOS 15.

El SDK descargado para esta sesión está en ../.tooling/flutter. Se utilizó un enlace temporal sin espacios para superar una limitación de herramientas de Dart en Windows. Para una instalación permanente, conviene instalar Flutter en una ruta sin espacios como C:/src/flutter y ejecutar flutter pub get para regenerar las rutas locales.

## Capturas

- [Acceso móvil](tool/previews/login_mobile_390x844.png)
- [Registro móvil](tool/previews/registro_mobile_390x844.png)
- [Registro completo](tool/previews/registro_desktop_900x1380.png)

Se regeneran con flutter test tool/preview_test.dart --update-goldens. Los datos que muestran son ficticios.
