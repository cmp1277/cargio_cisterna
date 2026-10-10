# SCPE · Cisternas para Android e iOS

Aplicación Flutter con interfaz nativa para registrar el carguío de agua. Conserva la API de la aplicación Android anterior y su identidad SCPE.

## Abrir y ejecutar

Abre **esta carpeta `flutter_app`** en Android Studio con los complementos Flutter y Dart instalados. La carpeta superior continúa siendo el proyecto Android anterior.

Requisitos: Flutter estable 3.47.7, SDK de Android y JDK compatibles con Flutter. Plataformas mínimas: Android 7.0 (API 24) e iOS 15. Ejecuta `flutter doctor -v` para revisar el equipo. El desarrollo de iOS requiere macOS con Xcode y un equipo de firma configurado para instalar en dispositivos físicos.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

La URL predeterminada corresponde al backend existente. Para usar un servidor de pruebas:

```powershell
flutter run --dart-define=API_URL=https://servidor-de-pruebas.example/api/mobile
```

### Despliegue en PythonAnywhere

El enlace `https://www.pythonanywhere.com/user/crismp/` abre el panel privado de alojamiento. La app necesita la URL pública de la API, que se confirma en la pestaña **Web**. El dominio propuesto `https://crismp.pythonanywhere.com` devolvió HTTP 404 durante la comprobación; todavía no se ha activado como servidor predeterminado.

La configuración y los pasos del servidor están en [backend/deploy/PYTHONANYWHERE.md](../../backend/deploy/PYTHONANYWHERE.md). El perfil de ejemplo para Flutter está en [config/pythonanywhere.json.example](config/pythonanywhere.json.example). Confirma el dominio y que la API responde antes de generar una versión con ese perfil. Cambiar el destino de la app no transfiere los registros ni los usuarios de la base de datos anterior.

GitHub Actions verificará el proyecto Flutter y generará un APK de prueba ARM64 cuando se publiquen los cambios en `main`. Los APK, cachés, contraseñas y claves de firma no se incluyen en el código fuente.

`API_URL` debe ser HTTPS y se configura al compilar; no es un secreto. No coloques contraseñas, tokens ni claves privadas en `--dart-define`, el repositorio o los logs.

## Funciones migradas

- Inicio de sesión y comprobación de conexión.
- Recordar únicamente el nombre de usuario; la contraseña no se guarda.
- Sesión de 30 minutos, con token protegido en almacenamiento seguro de la plataforma y validación al abrir o reanudar la aplicación.
- Carguío: conductor, placa, lecturas inicial/final, volumen, empresa, observaciones y EBAP.
- Placas de cuatro números y tres letras; admite `2127ACC` y normaliza a `2127 - ACC`.
- Lecturas con coma o punto y hasta dos decimales; cálculo en centésimas enteras para evitar errores de resta decimal.
- Campos conservados ante errores de envío, botón bloqueado durante el guardado y confirmación con ID al tener respuesta válida.
- Diseño adaptable, español y soporte de tamaño de texto del dispositivo.

Los textos del registro se normalizan a mayúsculas antes de enviarse. Los catálogos y nombres de campos coinciden con el cliente anterior. Se muestra el rol de la sesión; los permisos se aplican en el servidor.

## Estructura

```text
lib/
  application/       Estado y ciclo de vida de la sesión
  core/              Configuración por entorno
  data/              Cliente HTTP y almacenamiento seguro
  domain/            Modelos, catálogos y validaciones
  presentation/      Pantallas, tema y componentes
test/                Pruebas de dominio, API, sesión y widgets
android/             Proyecto anfitrión Android
ios/                 Proyecto anfitrión iOS
```

Se usa `ChangeNotifier` con dependencias inyectadas: los widgets no construyen peticiones ni acceden directamente a credenciales. `http` permite simular la API en pruebas y `flutter_secure_storage` administra el almacenamiento protegido.

## API y comportamiento de red

Todas las operaciones son `POST` JSON a `/api/mobile`. Acciones: `test`, `login`, `validateToken` y `saveData`. El token se envía en el cuerpo conforme al backend existente. No se agregan endpoints ni se cambia el servidor.

El cliente tiene un tiempo de espera de 15 segundos y no reintenta escrituras automáticamente. Ante timeout, desconexión o respuesta ambigua durante un guardado, el registro **puede haberse guardado**. La app solicita comprobarlo antes de enviarlo nuevamente. La prevención completa de duplicados necesita claves de idempotencia y soporte del backend.

No hay cola offline, sincronización, historial móvil, edición ni borrado de registros en el alcance migrado. El formulario necesita internet para guardar. Si caduca o se cierra la sesión, el formulario local se descarta. El cierre explícito elimina la sesión del dispositivo e intenta revocarla mediante `POST /api/auth/logout`; si no puede confirmarlo, informa al usuario.

## Android

Se conserva el identificador `com.scpe.cisternas` y se aumenta la versión a `2.0.0+5`. Para actualizar instalaciones existentes se necesita la **misma clave de firma** usada anteriormente.

```powershell
flutter build apk --debug
```

Salida universal: `build/app/outputs/flutter-apk/app-debug.apk`.

El APK de prueba validado en esta entrega es para ARM64 y se reproduce con:

```powershell
flutter build apk --debug --target-platform android-arm64 --split-per-abi
```

Salida: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.

Para una distribución real, copia `android/key.properties.example` a `android/key.properties` y configura una clave de firma release propia; no uses la firma debug. El proyecto debe bloquear compilaciones release sin configuración de firma. Después:

```powershell
flutter build appbundle --release
```

## iOS

En un Mac:

```sh
flutter pub get
flutter doctor -v
flutter build ios --simulator
open ios/Runner.xcworkspace
```

Configura el equipo Apple Developer y confirma la disponibilidad del identificador `com.scpe.cisternas`. Prueba inicio de sesión, almacenamiento seguro, reanudación, expiración y guardados contra un servidor de pruebas en iPhone real. Para distribuir:

```sh
flutter build ipa --release
```

La publicación requiere firma y configuración de la cuenta correspondiente, iconos definitivos y los datos de privacidad de las tiendas. Compilar para iOS no puede validarse desde este equipo Windows.

## Verificación previa a entrega

Consulta `VALIDACION.md` para el estado real de las comprobaciones realizadas. Las pruebas automatizadas usan una API simulada y no escriben registros en producción.

Antes de publicar: ejecutar contra una cuenta de pruebas, comprobar permisos de cada rol en servidor, validar errores y expiración en dispositivos reales, generar builds firmados y completar las comprobaciones de Android/iOS. La antigua WebView carga la página `/app` del servidor; el HTML empaquetado localmente no era el que se ejecutaba. Se cotejó con `../backend/mobile_app/index.html`: únicamente cambia la URL de la API. También se verificó el contrato en `../backend/app.py`, sin modificar el servidor.

Documentación: [Flutter](https://docs.flutter.dev/install/custom), [compilar iOS](https://docs.flutter.dev/deployment/ios), [almacenamiento seguro](https://pub.dev/packages/flutter_secure_storage).
