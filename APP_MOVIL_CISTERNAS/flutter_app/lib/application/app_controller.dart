import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mobile_api.dart';
import '../data/session_store.dart';
import '../domain/session.dart';
import '../domain/water_load.dart';

/// Owns the local authentication lifecycle. Session deadlines are absolute:
/// neither activity nor a successful token validation extends them.
class AppController extends ChangeNotifier {
  AppController({
    required MobileApi api,
    required SessionStore store,
    DateTime Function()? now,
  }) : _api = api,
       _store = store,
       _now = now ?? DateTime.now;

  final MobileApi _api;
  final SessionStore _store;
  final DateTime Function() _now;

  Session? _session;
  String _rememberedUsername = '';
  String? _error;
  bool _initializing = true;
  bool _initializationStarted = false;
  bool _authenticating = false;
  bool _testingConnection = false;
  bool _validating = false;
  bool _saving = false;
  bool _disposed = false;
  int _authEpoch = 0;
  int _connectionAttempt = 0;
  Timer? _expiryTimer;
  Future<void> _storeTail = Future<void>.value();

  Session? get session => _session;
  bool get initializing => _initializing;
  bool get busy => _authenticating || _testingConnection || _validating;
  bool get saving => _saving;
  String? get error => _error;
  String get rememberedUsername => _rememberedUsername;
  bool get isAuthenticated => _session != null && !_session!.isExpired(_now());

  Duration get remainingSessionTime {
    final deadline = _session?.expiresAt;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _isCurrent(int epoch) => !_disposed && epoch == _authEpoch;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    if (_disposed || _error == null) return;
    _error = null;
    _notify();
  }

  // A logout queued while a secure write is in flight must clear that write
  // before completing. This also prevents older writes overtaking a new login.
  Future<T> _withStore<T>(Future<T> Function() operation) {
    final result = _storeTail.then((_) => operation());
    _storeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> initialize() async {
    if (_disposed || _initializationStarted) return;
    _initializationStarted = true;
    final epoch = ++_authEpoch;
    try {
      final username = await _withStore(_store.readRememberedUsername);
      if (!_isCurrent(epoch)) return;
      _rememberedUsername = username;
      final restored = await _withStore(_store.readSession);
      if (!_isCurrent(epoch)) return;
      if (restored == null) return;
      if (restored.isExpired(_now())) {
        await _invalidateSession(
          message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
        );
        return;
      }
      _session = restored;
      _startExpiryTimer();
      await _validateSession();
    } on SessionStoreException catch (exception) {
      if (_isCurrent(epoch)) _error = exception.message;
    } catch (_) {
      if (_isCurrent(epoch)) {
        _error =
            'No se pudo recuperar la sesión guardada. Inicia sesión nuevamente.';
      }
    } finally {
      // Invalidating an expired/invalid restored token also changes the epoch.
      // That invalidation already ends initialization.
      if (_isCurrent(epoch)) {
        _initializing = false;
        _notify();
      }
    }
  }

  Future<void> login(
    String username,
    String password, {
    required bool remember,
  }) async {
    if (_disposed) return;
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      _error = 'Ingresa tu usuario y contraseña.';
      _notify();
      return;
    }

    final epoch = ++_authEpoch;
    _expiryTimer?.cancel();
    _session = null;
    _initializing = false;
    _authenticating = true;
    ++_connectionAttempt;
    _testingConnection = false;
    _validating = false;
    _saving = false;
    _error = null;
    _notify();

    try {
      await _withStore(() async {
        if (_isCurrent(epoch)) await _store.clearSession();
      });
      if (!_isCurrent(epoch)) return;
      final authenticated = await _api.login(normalizedUsername, password);
      if (!_isCurrent(epoch)) return;
      if (authenticated.token.isEmpty || authenticated.isExpired(_now())) {
        _error =
            'El servidor devolvió una sesión vencida o inválida. Intenta nuevamente.';
        return;
      }
      final stored = await _withStore(() async {
        if (!_isCurrent(epoch)) return false;
        await _store.writeRememberedUsername(
          remember ? normalizedUsername : null,
        );
        if (!_isCurrent(epoch)) return false;
        try {
          await _store.writeSession(authenticated);
        } catch (_) {
          // A platform write may fail after persisting; remove any partial commit.
          try {
            await _store.clearSession();
          } catch (_) {
            // Preserve the original, readable storage failure.
          }
          rethrow;
        }
        if (!_isCurrent(epoch)) {
          // dispose() cannot await this write; compensate inside the same queue.
          await _store.clearSession();
          return false;
        }
        return true;
      });
      if (!stored || !_isCurrent(epoch)) return;
      if (authenticated.isExpired(_now())) {
        await _invalidateSession(
          message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
        );
        return;
      }
      _session = authenticated;
      _rememberedUsername = remember ? normalizedUsername : '';
      _startExpiryTimer();
    } on ApiException catch (exception) {
      if (_isCurrent(epoch)) _error = exception.message;
    } on SessionStoreException catch (exception) {
      if (_isCurrent(epoch)) _error = exception.message;
    } catch (_) {
      if (_isCurrent(epoch)) {
        _error =
            'No se pudo iniciar sesión. Revisa tu conexión e intenta nuevamente.';
      }
    } finally {
      if (_isCurrent(epoch)) {
        _authenticating = false;
        _notify();
      }
    }
  }

  Future<void> logout() async {
    if (_disposed) return;
    final token = _session?.token;
    // Memory is invalidated synchronously, before either storage or network I/O.
    final localClose = _invalidateSession();
    final epoch = _authEpoch;
    await localClose;
    if (token == null || token.isEmpty) return;
    try {
      await _api.logout(token);
    } catch (_) {
      // A delayed response must never change a newer authentication attempt.
      if (!_isCurrent(epoch)) return;
      const warning =
          'Sesión cerrada en este dispositivo; no se pudo confirmar el cierre en el servidor.';
      final previous = _error;
      _error = previous == null ? warning : '$previous $warning';
      _notify();
    }
  }

  Future<void> _invalidateSession({
    String? message,
    bool pendingSaveMaySucceed = true,
  }) async {
    if (_disposed) return;
    final hadPendingSave = _saving && pendingSaveMaySucceed;
    if (hadPendingSave) {
      final prefix = message ?? 'Se cerró la sesión.';
      message =
          '$prefix Hay un envío en curso que podría guardarse. Verifica el registro antes de volver a enviarlo.';
    }
    final epoch = ++_authEpoch;
    _expiryTimer?.cancel();
    _session = null;
    _initializing = false;
    _authenticating = false;
    ++_connectionAttempt;
    _testingConnection = false;
    _validating = false;
    _saving = false;
    _error = message;
    _notify();
    try {
      await _withStore(_store.clearSession);
    } on SessionStoreException catch (exception) {
      if (_isCurrent(epoch)) {
        _error = message == null
            ? exception.message
            : '$message ${exception.message}';
        _notify();
      }
    } catch (_) {
      if (_isCurrent(epoch)) {
        _error =
            'La sesión se cerró, pero no se pudo borrar el token guardado en este dispositivo.';
        _notify();
      }
    }
  }

  Future<void> onResume() async {
    if (_disposed || _session == null) return;
    if (_session!.isExpired(_now())) {
      await _invalidateSession(
        message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
      );
      return;
    }
    await _validateSession();
  }

  Future<void> _validateSession() async {
    final current = _session;
    if (_disposed || current == null || _validating) return;
    final epoch = _authEpoch;
    _validating = true;
    _notify();
    try {
      final valid = await _api.validateToken(current.token);
      if (!_isCurrent(epoch)) return;
      if (!valid) {
        await _invalidateSession(
          message: 'Tu sesión ya no es válida. Inicia sesión nuevamente.',
        );
      } else if (current.isExpired(_now())) {
        await _invalidateSession(
          message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
        );
      }
    } on ApiException catch (exception) {
      if (!_isCurrent(epoch)) return;
      if (exception.unauthorized) {
        await _invalidateSession(
          message: 'Tu sesión ya no es válida. Inicia sesión nuevamente.',
        );
      } else {
        // A transport failure is not evidence that authentication was revoked.
        _error = 'No se pudo verificar la sesión: ${exception.message}';
      }
    } catch (_) {
      if (_isCurrent(epoch)) {
        _error = 'No se pudo verificar la sesión. Revisa tu conexión.';
      }
    } finally {
      if (_isCurrent(epoch)) {
        _validating = false;
        _notify();
      }
    }
  }

  Future<String?> testConnection() async {
    if (_disposed || _testingConnection) return null;
    final attempt = ++_connectionAttempt;
    _testingConnection = true;
    _error = null;
    _notify();
    try {
      final message = await _api.testConnection();
      return !_disposed && attempt == _connectionAttempt ? message : null;
    } on ApiException catch (exception) {
      if (!_disposed && attempt == _connectionAttempt) {
        _error = exception.message;
      }
      return null;
    } catch (_) {
      if (!_disposed && attempt == _connectionAttempt) {
        _error = 'No se pudo conectar con el servidor. Revisa tu conexión.';
      }
      return null;
    } finally {
      if (!_disposed && attempt == _connectionAttempt) {
        _testingConnection = false;
        _notify();
      }
    }
  }

  Future<String?> submit(WaterLoad load) async {
    if (_disposed || _saving) return null;
    final current = _session;
    if (current == null) {
      _error = 'Inicia sesión para registrar una carga.';
      _notify();
      return null;
    }
    if (current.isExpired(_now())) {
      await _invalidateSession(
        message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
      );
      return null;
    }
    final epoch = _authEpoch;
    _saving = true;
    _error = null;
    _notify();
    try {
      final message = await _api.saveLoad(current.token, load);
      if (!_isCurrent(epoch)) return null;
      if (current.isExpired(_now())) {
        await _invalidateSession(
          message:
              'Carga registrada con ID $message. Tu sesión ha vencido. Inicia sesión nuevamente.',
          pendingSaveMaySucceed: false,
        );
      }
      return message;
    } on ApiException catch (exception) {
      if (!_isCurrent(epoch)) return null;
      if (exception.unauthorized) {
        await _invalidateSession(
          message: 'Tu sesión ya no es válida. Inicia sesión nuevamente.',
          pendingSaveMaySucceed: false,
        );
      } else {
        _error = exception.message;
      }
      return null;
    } catch (_) {
      if (_isCurrent(epoch)) {
        _error =
            'No se pudo confirmar el registro. Verifica si se guardó antes de volver a enviarlo.';
      }
      return null;
    } finally {
      if (_isCurrent(epoch)) {
        _saving = false;
        _notify();
      }
    }
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _session == null) return;
      if (_session!.isExpired(_now())) {
        unawaited(
          _invalidateSession(
            message: 'Tu sesión ha vencido. Inicia sesión nuevamente.',
          ),
        );
      } else {
        _notify();
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_authEpoch;
    ++_connectionAttempt;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
