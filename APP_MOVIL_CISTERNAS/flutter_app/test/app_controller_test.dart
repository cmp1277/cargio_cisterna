import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scpe_cisternas/application/app_controller.dart';
import 'package:scpe_cisternas/data/mobile_api.dart';
import 'package:scpe_cisternas/data/session_store.dart';
import 'package:scpe_cisternas/domain/session.dart';
import 'package:scpe_cisternas/domain/water_load.dart';

void main() {
  late DateTime now;
  late Session validSession;
  late MemorySessionStore store;
  late FakeMobileApi api;
  late AppController controller;

  setUp(() {
    now = DateTime.utc(2026, 10, 9, 12);
    validSession = Session(
      token: 'test-token',
      username: 'operador',
      role: 'user',
      expiresAt: now.add(const Duration(minutes: 30)),
    );
    store = MemorySessionStore();
    api = FakeMobileApi(validSession);
    controller = AppController(api: api, store: store, now: () => now);
  });

  tearDown(() => controller.dispose());

  test('restores remembered username without inventing a session', () async {
    store.rememberedUsername = 'operador';
    await controller.initialize();

    expect(controller.initializing, isFalse);
    expect(controller.session, isNull);
    expect(controller.rememberedUsername, 'operador');
    expect(api.validationCalls, 0);
  });

  test('validating a restored session never extends its deadline', () async {
    store.session = validSession;
    await controller.initialize();
    now = now.add(const Duration(minutes: 10));
    await controller.onResume();

    expect(controller.session, same(validSession));
    expect(controller.remainingSessionTime, const Duration(minutes: 20));
    expect(api.validationCalls, 2);
  });

  test('network failure preserves an unexpired restored session', () async {
    store.session = validSession;
    api.validationHandler = (_) async =>
        throw const ApiException('Sin conexión.');
    await controller.initialize();

    expect(controller.isAuthenticated, isTrue);
    expect(store.session, same(validSession));
    expect(controller.error, contains('Sin conexión'));
    expect(controller.initializing, isFalse);
    expect(controller.busy, isFalse);
  });

  test('a definitively rejected restored token is removed', () async {
    store.session = validSession;
    store.rememberedUsername = 'operador';
    api.validationHandler = (_) async => false;
    await controller.initialize();

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(controller.rememberedUsername, 'operador');
    expect(controller.initializing, isFalse);
    expect(controller.error, contains('ya no es válida'));
    expect(api.logoutCalls, 0);
  });

  test('an expired stored token is removed without a network call', () async {
    store.session = validSession;
    now = validSession.expiresAt;
    await controller.initialize();

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(api.validationCalls, 0);
    expect(controller.error, contains('ha vencido'));
    expect(api.logoutCalls, 0);
  });

  test(
    'login trims username, preserves password and remembers only user',
    () async {
      api.loginHandler = (username, password) async {
        expect(username, 'operador');
        expect(password, ' password with spaces ');
        return validSession;
      };
      await controller.login(
        ' operador ',
        ' password with spaces ',
        remember: true,
      );

      expect(controller.session, same(validSession));
      expect(store.session, same(validSession));
      expect(store.rememberedUsername, 'operador');
      expect(store.session!.toJson().keys, isNot(contains('password')));
      expect(controller.busy, isFalse);
    },
  );

  test(
    'disabling remember removes the previously remembered username',
    () async {
      store.rememberedUsername = 'anterior';
      await controller.login('operador', 'password', remember: false);

      expect(store.rememberedUsername, isEmpty);
      expect(controller.rememberedUsername, isEmpty);
      await controller.logout();
      expect(store.session, isNull);
    },
  );

  test('foreground expiration uses the original absolute deadline', () async {
    await controller.login('operador', 'password', remember: true);
    now = validSession.expiresAt;
    await controller.onResume();

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(store.rememberedUsername, 'operador');
    expect(api.validationCalls, 0);
  });

  testWidgets('timer closes a session exactly at its deadline', (tester) async {
    controller.dispose();
    controller = AppController(api: api, store: store, now: () => now);
    await controller.login('operador', 'password', remember: true);
    now = validSession.expiresAt;
    await tester.pump(const Duration(seconds: 1));

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(controller.remainingSessionTime, Duration.zero);
  });

  test('logout discards a login response that arrives later', () async {
    final pendingLogin = Completer<Session>();
    final loginStarted = Completer<void>();
    api.loginHandler = (_, _) {
      loginStarted.complete();
      return pendingLogin.future;
    };
    final login = controller.login('operador', 'password', remember: true);
    await loginStarted.future;
    await controller.logout();
    pendingLogin.complete(validSession);
    await login;

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(store.rememberedUsername, isEmpty);
  });

  test('logout waits for and removes an in-flight secure write', () async {
    store.writeGate = Completer<void>();
    final login = controller.login('operador', 'password', remember: true);
    await store.writeStarted.future;
    var logoutCompleted = false;
    final logout = controller.logout().then((_) => logoutCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(logoutCompleted, isFalse);

    store.writeGate!.complete();
    await Future.wait([login, logout]);
    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(logoutCompleted, isTrue);
  });

  test(
    'dispose discards pending login and emits no later notification',
    () async {
      final pendingLogin = Completer<Session>();
      final loginStarted = Completer<void>();
      api.loginHandler = (_, _) {
        loginStarted.complete();
        return pendingLogin.future;
      };
      var notifications = 0;
      controller.addListener(() => notifications++);
      final login = controller.login('operador', 'password', remember: true);
      await loginStarted.future;
      controller.dispose();
      final countAtDispose = notifications;
      pendingLogin.complete(validSession);
      await login;

      expect(store.session, isNull);
      expect(controller.session, isNull);
      expect(notifications, countAtDispose);
    },
  );

  test('dispose compensates a secure write that has already started', () async {
    store.writeGate = Completer<void>();
    final login = controller.login('operador', 'password', remember: true);
    await store.writeStarted.future;
    controller.dispose();
    store.writeGate!.complete();
    await login;

    expect(store.session, isNull);
    expect(controller.session, isNull);
  });

  test('partial secure write failure is cleared and explained', () async {
    store.failAfterWrite = true;
    await controller.login('operador', 'password', remember: true);

    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(controller.error, 'No se pudo guardar la sesión de forma segura.');
    expect(controller.busy, isFalse);
  });

  test('only one save request can be in flight at a time', () async {
    await controller.login('operador', 'password', remember: false);
    final pendingSave = Completer<String>();
    api.saveHandler = (_, _) => pendingSave.future;

    final first = controller.submit(exampleLoad);
    final second = await controller.submit(exampleLoad);
    expect(second, isNull);
    expect(api.saveCalls, 1);
    expect(controller.saving, isTrue);

    pendingSave.complete('C-123');
    expect(await first, 'C-123');
    expect(controller.saving, isFalse);
  });

  test('an uncertain save is never automatically retried', () async {
    await controller.login('operador', 'password', remember: false);
    api.saveHandler = (_, _) async => throw const ApiException(
      'Verifica el registro antes de volver a enviarlo.',
      uncertainSave: true,
    );

    expect(await controller.submit(exampleLoad), isNull);
    expect(api.saveCalls, 1);
    expect(controller.isAuthenticated, isTrue);
    expect(
      controller.error,
      'Verifica el registro antes de volver a enviarlo.',
    );
    expect(controller.saving, isFalse);
  });

  test('authorization rejection during save clears the session', () async {
    await controller.login('operador', 'password', remember: false);
    api.saveHandler = (_, _) async =>
        throw const ApiException('Sesión inválida.', unauthorized: true);

    expect(await controller.submit(exampleLoad), isNull);
    expect(controller.session, isNull);
    expect(store.session, isNull);
    expect(controller.error, isNot(contains('envío en curso')));
  });

  test(
    'expiration while saving warns that the write may still succeed',
    () async {
      await controller.login('operador', 'password', remember: false);
      final pendingSave = Completer<String>();
      api.saveHandler = (_, _) => pendingSave.future;
      final submission = controller.submit(exampleLoad);

      now = validSession.expiresAt;
      await controller.onResume();
      expect(controller.error, contains('podría guardarse'));
      pendingSave.complete('C-124');

      expect(await submission, isNull);
      expect(controller.session, isNull);
      expect(controller.error, contains('Verifica el registro'));
    },
  );

  test('a confirmed save at expiration retains its confirmation', () async {
    await controller.login('operador', 'password', remember: false);
    api.saveHandler = (_, _) async {
      now = validSession.expiresAt;
      return 'C-125';
    };

    expect(await controller.submit(exampleLoad), 'C-125');
    expect(controller.session, isNull);
    expect(controller.error, contains('Carga registrada con ID C-125'));
    expect(controller.error, isNot(contains('podría guardarse')));
  });
  test(
    'explicit logout immediately clears local state and revokes its token',
    () async {
      await controller.login('operador', 'password', remember: true);
      final pendingLogout = Completer<void>();
      final logoutStarted = Completer<void>();
      api.logoutHandler = (token) {
        expect(token, validSession.token);
        logoutStarted.complete();
        return pendingLogout.future;
      };

      final logout = controller.logout();
      expect(controller.session, isNull);
      await logoutStarted.future;
      expect(store.session, isNull);
      expect(store.rememberedUsername, 'operador');
      expect(api.logoutCalls, 1);

      pendingLogout.complete();
      await logout;
      expect(controller.error, isNull);
    },
  );

  test(
    'remote logout failure keeps the device signed out and explains it',
    () async {
      await controller.login('operador', 'password', remember: true);
      api.logoutHandler = (_) async =>
          throw const ApiException('Sin conexión.');

      await controller.logout();

      expect(controller.session, isNull);
      expect(store.session, isNull);
      expect(store.rememberedUsername, 'operador');
      expect(
        controller.error,
        contains('no se pudo confirmar el cierre en el servidor'),
      );
    },
  );

  test('failed remote logout retains the pending save warning', () async {
    await controller.login('operador', 'password', remember: false);
    final pendingSave = Completer<String>();
    api.saveHandler = (_, _) => pendingSave.future;
    api.logoutHandler = (_) async => throw const ApiException('Sin conexión.');
    final submission = controller.submit(exampleLoad);

    await controller.logout();
    expect(controller.error, contains('podría guardarse'));
    expect(
      controller.error,
      contains('no se pudo confirmar el cierre en el servidor'),
    );
    pendingSave.complete('C-126');

    expect(await submission, isNull);
    expect(controller.session, isNull);
    expect(controller.error, contains('podría guardarse'));
  });

  test('a late remote logout failure cannot modify a newer login', () async {
    await controller.login('operador', 'password', remember: false);
    final pendingLogout = Completer<void>();
    final logoutStarted = Completer<void>();
    api.logoutHandler = (_) {
      logoutStarted.complete();
      return pendingLogout.future;
    };
    final logout = controller.logout();
    await logoutStarted.future;
    final nextSession = Session(
      token: 'new-token',
      username: 'nuevo',
      role: 'user',
      expiresAt: now.add(const Duration(minutes: 30)),
    );
    api.loginHandler = (_, _) async => nextSession;
    await controller.login('nuevo', 'password', remember: true);

    pendingLogout.completeError(const ApiException('Sin conexión.'));
    await logout;

    expect(controller.session, same(nextSession));
    expect(store.session, same(nextSession));
    expect(controller.error, isNull);
    expect(controller.rememberedUsername, 'nuevo');
  });
}

const exampleLoad = WaterLoad(
  driverName: 'JUAN PEREZ',
  plateNumber: '2127 - ACC',
  initialReading: 10000,
  finalReading: 11000,
  companyType: 'Particular',
  companyName: 'EMPRESA',
  characteristics: '',
  ebap: 'Norte',
);

class MemorySessionStore implements SessionStore {
  Session? session;
  String rememberedUsername = '';
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  bool failAfterWrite = false;

  @override
  Future<Session?> readSession() async => session;

  @override
  Future<String> readRememberedUsername() async => rememberedUsername;

  @override
  Future<void> writeSession(Session value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writeGate != null) await writeGate!.future;
    session = value;
    if (failAfterWrite) {
      throw const SessionStoreException(
        'No se pudo guardar la sesión de forma segura.',
      );
    }
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<void> writeRememberedUsername(String? value) async {
    rememberedUsername = value ?? '';
  }
}

class FakeMobileApi implements MobileApi {
  FakeMobileApi(this.nextSession);

  final Session nextSession;
  Future<Session> Function(String, String)? loginHandler;
  Future<bool> Function(String)? validationHandler;
  Future<String> Function(String, WaterLoad)? saveHandler;
  Future<void> Function(String)? logoutHandler;
  int logoutCalls = 0;
  int validationCalls = 0;
  int saveCalls = 0;

  @override
  Uri get endpoint => Uri.https('example.invalid', '/api');

  @override
  Duration get timeout => const Duration(seconds: 15);

  @override
  Future<Session> login(String username, String password) async {
    if (loginHandler != null) return loginHandler!(username, password);
    return nextSession;
  }

  @override
  Future<bool> validateToken(String token) async {
    validationCalls++;
    if (validationHandler != null) return validationHandler!(token);
    return true;
  }

  @override
  Future<String> saveLoad(String token, WaterLoad load) async {
    saveCalls++;
    if (saveHandler != null) return saveHandler!(token, load);
    return 'C-123';
  }

  @override
  Future<void> logout(String token) async {
    logoutCalls++;
    if (logoutHandler != null) await logoutHandler!(token);
  }

  @override
  Future<String> testConnection() async => 'Conexión establecida.';

  @override
  void close() {}
}
