// Run from flutter_app:
// flutter test tool/preview_test.dart --update-goldens
// This optional visual tool is deliberately outside the normal test/ suite.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scpe_cisternas/application/app_controller.dart';
import 'package:scpe_cisternas/data/mobile_api.dart';
import 'package:scpe_cisternas/data/session_store.dart';
import 'package:scpe_cisternas/domain/session.dart';
import 'package:scpe_cisternas/domain/water_load.dart';
import 'package:scpe_cisternas/presentation/load_screen.dart';
import 'package:scpe_cisternas/presentation/login_screen.dart';
import 'package:scpe_cisternas/presentation/theme.dart';

final _previewTime = DateTime.utc(2026, 10, 9, 12);
const _captureKey = ValueKey('preview-capture');

class _PreviewStore implements SessionStore {
  Session? session;
  String username = '';

  @override
  Future<Session?> readSession() async => session;
  @override
  Future<void> writeSession(Session value) async {
    session = value;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<String> readRememberedUsername() async => username;
  @override
  Future<void> writeRememberedUsername(String? value) async {
    username = value ?? '';
  }
}

class _PreviewApi extends MobileApi {
  _PreviewApi()
    : super(endpoint: Uri.parse('https://example.invalid/api/mobile'));

  @override
  Future<Session> login(String username, String password) async => Session(
    token: 'preview-only-token',
    username: 'OPERADOR DEMO',
    role: 'usuario',
    expiresAt: _previewTime.add(const Duration(minutes: 30)),
  );
  @override
  Future<void> logout(String token) async {}
  @override
  Future<bool> validateToken(String token) async => true;
  @override
  Future<String> testConnection() async => 'Conexión de demostración.';
  @override
  Future<String> saveLoad(String token, WaterLoad load) async => 'DEMO-001';
}

/// Widget tests normally substitute Ahem; use the SDK's real Roboto fonts so
/// these review images contain readable text and realistic font metrics.
Future<void> _loadPreviewFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (sdk != null)
      '$sdk/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts',
    '../.tooling/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts',
  ];
  String? fontDirectory;
  for (final candidate in candidates) {
    if (await File('$candidate/Roboto/Roboto-Regular.ttf').exists()) {
      fontDirectory = candidate;
      break;
    }
  }
  if (fontDirectory == null) {
    throw StateError(
      'No se encontraron fuentes Roboto del SDK. Configure FLUTTER_ROOT para generar vistas previas legibles.',
    );
  }
  Future<ByteData> font(String name) async {
    final bytes = await File('$fontDirectory/$name').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(font('Roboto/Roboto-Regular.ttf'))
    ..addFont(font('Roboto/Roboto-Medium.ttf'))
    ..addFont(font('Roboto/Roboto-Bold.ttf'))
    ..addFont(font('Roboto/Roboto-Black.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(font('MaterialIcons-Regular.otf'));
  await icons.load();
}

Finder _field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

Future<void> _render(
  WidgetTester tester, {
  required Size size,
  required bool authenticated,
  required String filename,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _PreviewApi();
  final controller = AppController(
    api: api,
    store: _PreviewStore(),
    now: () => _previewTime,
  );
  addTearDown(controller.dispose);
  addTearDown(api.close);
  await controller.initialize();
  if (authenticated) {
    await controller.login('demo', 'preview-password', remember: false);
  }
  final theme = buildAppTheme();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: theme.filledButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
        ),
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => authenticated
              ? LoadScreen(controller: controller)
              : LoginScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (authenticated) {
    for (final entry in {
      'Nombre del conductor': 'CARLOS MENDOZA',
      'Placa': '2127 - ACC',
      'Lectura inicial': '1250,25',
      'Lectura final': '1262,75',
    }.entries) {
      await tester.ensureVisible(_field(entry.key));
      await tester.enterText(_field(entry.key), entry.value);
      await tester.pumpAndSettle();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
  } else {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/logo.png'),
        tester.element(find.byType(LoginScreen)),
      ),
    );
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(_captureKey),
    matchesGoldenFile('previews/$filename'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadPreviewFonts);

  testWidgets('Preview login on a mobile viewport', (tester) async {
    await _render(
      tester,
      size: const Size(390, 844),
      authenticated: false,
      filename: 'login_mobile_390x844.png',
    );
  });
  testWidgets('Preview registration on a mobile viewport', (tester) async {
    await _render(
      tester,
      size: const Size(390, 844),
      authenticated: true,
      filename: 'registro_mobile_390x844.png',
    );
  });
  testWidgets('Preview complete registration on a wide viewport', (
    tester,
  ) async {
    await _render(
      tester,
      size: const Size(900, 1380),
      authenticated: true,
      filename: 'registro_desktop_900x1380.png',
    );
  });
}
