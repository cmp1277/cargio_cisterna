import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scpe_cisternas/application/app_controller.dart';
import 'package:scpe_cisternas/data/mobile_api.dart';
import 'package:scpe_cisternas/data/session_store.dart';
import 'package:scpe_cisternas/domain/session.dart';
import 'package:scpe_cisternas/domain/water_load.dart';
import 'package:scpe_cisternas/presentation/load_screen.dart';
import 'package:scpe_cisternas/presentation/login_screen.dart';
import 'package:scpe_cisternas/presentation/theme.dart';

class _MemoryStore implements SessionStore {
  Session? session;
  String remembered = '';

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
  Future<String> readRememberedUsername() async => remembered;
  @override
  Future<void> writeRememberedUsername(String? value) async {
    remembered = value ?? '';
  }
}

class _FakeApi extends MobileApi {
  _FakeApi() : super(endpoint: Uri.parse('https://example.test/api/mobile'));

  int loginCalls = 0;
  int saveCalls = 0;
  String? receivedUsername;
  String? receivedPassword;
  WaterLoad? savedLoad;
  bool failSave = false;

  @override
  Future<Session> login(String username, String password) async {
    loginCalls++;
    receivedUsername = username;
    receivedPassword = password;
    return Session(
      token: 'test-token',
      username: username,
      role: 'usuario',
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
    );
  }

  @override
  Future<bool> validateToken(String token) async => true;

  @override
  Future<void> logout(String token) async {}

  @override
  Future<String> testConnection() async => 'API operativa.';

  @override
  Future<String> saveLoad(String token, WaterLoad load) async {
    saveCalls++;
    savedLoad = load;
    if (failSave) {
      throw const ApiException(
        'No se confirmó el guardado. Verifique el registro antes de volver a enviarlo.',
        uncertainSave: true,
      );
    }
    return '42';
  }
}

class _ControllerOwner extends StatefulWidget {
  const _ControllerOwner({required this.controller, required this.child});
  final AppController controller;
  final Widget child;
  @override
  State<_ControllerOwner> createState() => _ControllerOwnerState();
}

class _ControllerOwnerState extends State<_ControllerOwner> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Fixture {
  _Fixture(this.api, this.controller);
  final _FakeApi api;
  final AppController controller;
}

Finder _field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

String _value(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(_field(label)).controller!.text;

Future<_Fixture> _mount(
  WidgetTester tester, {
  bool authenticated = false,
  Size size = const Size(360, 800),
  double textScale = 1,
  bool failSave = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _FakeApi()..failSave = failSave;
  final controller = AppController(api: api, store: _MemoryStore());
  addTearDown(controller.dispose);
  addTearDown(api.close);
  await controller.initialize();
  if (authenticated) {
    await controller.login('operador', 'password', remember: false);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: _ControllerOwner(
        controller: controller,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => authenticated
              ? LoadScreen(controller: controller)
              : LoginScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(api, controller);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, int index, String value) async {
  await _tap(tester, find.byType(DropdownButtonFormField<String>).at(index));
  await _tap(tester, find.text(value).last);
}

Future<void> _completeLoad(WidgetTester tester) async {
  await _enter(tester, 'Nombre del conductor', 'Juan Pérez');
  await _enter(tester, 'Placa', '2127acc');
  await _enter(tester, 'Lectura inicial', '120,25');
  await _enter(tester, 'Lectura final', '130,50');
  await _select(tester, 0, 'Particular');
  await _select(tester, 1, 'Sur');
  await _enter(tester, 'Empresa / entidad', 'Empresa uno');
  await _enter(tester, 'Observaciones (opcional)', 'Entrega urgente');
}

void main() {
  testWidgets(
    'Login fits narrow screens with enlarged text and a reachable submit button',
    (tester) async {
      for (final size in [const Size(360, 800), const Size(320, 700)]) {
        final fixture = await _mount(tester, size: size, textScale: 1.8);
        expect(find.text('Iniciar sesión'), findsOneWidget);
        await tester.ensureVisible(find.text('Ingresar'));
        await tester.pumpAndSettle();
        expect(find.text('Ingresar').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.controller.dispose();
      }
    },
  );

  testWidgets(
    'Load form and long company options support narrow screens and enlarged text',
    (tester) async {
      for (final size in [const Size(360, 800), const Size(320, 700)]) {
        final fixture = await _mount(
          tester,
          authenticated: true,
          size: size,
          textScale: 1.8,
        );
        expect(find.text('Nuevo carguío'), findsOneWidget);
        await _select(tester, 0, 'Gobierno Departamental');
        await tester.ensureVisible(find.text('Guardar registro'));
        await tester.pumpAndSettle();
        expect(find.text('Guardar registro').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.controller.dispose();
      }
    },
  );

  testWidgets('Empty login and registration forms do not send requests', (
    tester,
  ) async {
    final login = await _mount(tester);
    await _tap(tester, find.text('Ingresar'));
    expect(login.api.loginCalls, 0);
    expect(find.text('Ingresa tu usuario.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    login.controller.dispose();

    final registration = await _mount(tester, authenticated: true);
    await _tap(tester, find.text('Guardar registro'));
    expect(registration.api.saveCalls, 0);
    expect(find.text('Completa este campo.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Login trims only username and sends the password unchanged', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    await _enter(tester, 'Usuario', ' operador ');
    await _enter(tester, 'Contraseña', ' PaSs Ñ ! ');
    await _tap(tester, find.text('Ingresar'));
    expect(fixture.api.loginCalls, 1);
    expect(fixture.api.receivedUsername, 'operador');
    expect(fixture.api.receivedPassword, ' PaSs Ñ ! ');
    expect(fixture.controller.isAuthenticated, isTrue);
    expect(_value(tester, 'Contraseña'), isEmpty);
  });

  testWidgets('A confirmed save displays ID and clears fields and selectors', (
    tester,
  ) async {
    final fixture = await _mount(tester, authenticated: true);
    await _completeLoad(tester);
    await _tap(tester, find.text('Guardar registro'));
    expect(fixture.api.saveCalls, 1);
    expect(fixture.api.savedLoad!.loadVolume, 10.25);
    expect(
      find.text('Registro guardado correctamente. N.º 42'),
      findsOneWidget,
    );
    expect(find.text('Completa este campo.'), findsNothing);
    expect(find.text('Usa 4 números y 3 letras: 2127 - ACC.'), findsNothing);
    for (final label in [
      'Nombre del conductor',
      'Placa',
      'Lectura inicial',
      'Lectura final',
      'Empresa / entidad',
      'Observaciones (opcional)',
    ]) {
      expect(_value(tester, label), isEmpty, reason: label);
    }
    final selectors = find.byType(DropdownButtonFormField<String>);
    for (var index = 0; index < selectors.evaluate().length; index++) {
      expect(
        tester.state<FormFieldState<String>>(selectors.at(index)).value,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An uncertain save preserves the draft and warns before another submission',
    (tester) async {
      final fixture = await _mount(tester, authenticated: true, failSave: true);
      await _completeLoad(tester);
      await _tap(tester, find.text('Guardar registro'));
      expect(fixture.api.saveCalls, 1);
      expect(_value(tester, 'Nombre del conductor'), 'Juan Pérez');
      expect(_value(tester, 'Placa'), '2127acc');
      expect(_value(tester, 'Lectura inicial'), '120,25');
      expect(_value(tester, 'Lectura final'), '130,50');
      expect(_value(tester, 'Empresa / entidad'), 'Empresa uno');
      expect(_value(tester, 'Observaciones (opcional)'), 'Entrega urgente');
      expect(
        find.textContaining('Verifique el registro antes de volver a enviarlo'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Registro guardado correctamente'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
