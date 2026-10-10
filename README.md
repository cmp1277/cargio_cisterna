# SCPE · Cisternas

Sistema de registro de carguío de agua: aplicación Flutter para Android e iOS, API Flask y panel administrador.

## Proyectos

| Componente | Ubicación |
| --- | --- |
| App Flutter | [APP_MOVIL_CISTERNAS/flutter_app](APP_MOVIL_CISTERNAS/flutter_app/README.md) |
| API y administración | [backend](backend/README.md) |
| Despliegue PythonAnywhere | [Guía para la cuenta crismp](backend/deploy/PYTHONANYWHERE.md) |
| Resultados de validación móvil | [VALIDACION.md](APP_MOVIL_CISTERNAS/flutter_app/VALIDACION.md) |

## Desarrollo móvil

Abre `APP_MOVIL_CISTERNAS/flutter_app` en Android Studio con los complementos Flutter y Dart. El proyecto se validó con Flutter 3.47.7. Requiere Android 7.0/API 24 o iOS 15 como mínimo.

```sh
cd APP_MOVIL_CISTERNAS/flutter_app
flutter pub get
flutter analyze
flutter test
flutter run
```

La app incluye inicio de sesión, almacenamiento seguro del token, caducidad de sesión, formulario de carguío y cálculo decimal del volumen. El proyecto Android anterior se conserva en la carpeta superior.

## PythonAnywhere

El enlace `https://www.pythonanywhere.com/user/crismp/` corresponde al panel de alojamiento. La dirección de la API se toma del dominio publicado en la pestaña **Web**, seguido de `/api/mobile`.

El perfil de ejemplo propone `https://crismp.pythonanywhere.com/api/mobile`; su comprobación pública devolvió HTTP 404. El despliegue sigue pendiente de acceso a la cuenta y confirmación de la base de datos. La app conserva el servidor predeterminado actual hasta validar el nuevo destino.

Sigue la [guía de despliegue](backend/deploy/PYTHONANYWHERE.md) para configurar el entorno privado, la base de datos y WSGI. Después verifica la API y compila Flutter con el perfil de PythonAnywhere. El cambio de URL no migra los datos del servidor anterior.

## Verificación y distribución

GitHub Actions ejecuta las pruebas del backend y de Flutter. El flujo Flutter genera un APK de prueba ARM64 descargable desde sus artefactos. Ese APK usa firma de desarrollo; la distribución requiere configurar una firma release. iOS se compila y firma desde macOS con Xcode.

Los archivos `.env`, las bases de datos, las claves de firma y los artefactos de compilación están excluidos de Git.
