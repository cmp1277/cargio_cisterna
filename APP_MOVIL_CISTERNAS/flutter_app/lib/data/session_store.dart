import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/session.dart';

abstract interface class SessionStore {
  Future<Session?> readSession();
  Future<void> writeSession(Session session);
  Future<void> clearSession();
  Future<String> readRememberedUsername();

  /// A null or empty value removes the remembered username.
  Future<void> writeRememberedUsername(String? username);
}

class SessionStoreException implements Exception {
  const SessionStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Tokens live in platform secure storage. Passwords are never persisted.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _sessionKey = 'scpe.session.v1';
  static const _usernameKey = 'scpe.remembered_username.v1';

  @override
  Future<Session?> readSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null || raw.isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid session');
        }
        return Session.fromJson(decoded);
      } catch (_) {
        await _storage.delete(key: _sessionKey);
        throw const SessionStoreException(
          'La sesión guardada no es válida. Inicia sesión nuevamente.',
        );
      }
    } on SessionStoreException {
      rethrow;
    } catch (_) {
      throw const SessionStoreException(
        'No se pudo leer la sesión del almacenamiento seguro. Inicia sesión nuevamente.',
      );
    }
  }

  @override
  Future<void> writeSession(Session session) async {
    try {
      await _storage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
    } catch (_) {
      throw const SessionStoreException(
        'No se pudo guardar la sesión de forma segura en este dispositivo.',
      );
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _sessionKey);
    } catch (_) {
      throw const SessionStoreException(
        'No se pudo borrar la sesión del almacenamiento seguro. Intenta cerrar sesión nuevamente.',
      );
    }
  }

  @override
  Future<String> readRememberedUsername() async {
    try {
      return await _storage.read(key: _usernameKey) ?? '';
    } catch (_) {
      throw const SessionStoreException(
        'No se pudo leer el usuario recordado en este dispositivo.',
      );
    }
  }

  @override
  Future<void> writeRememberedUsername(String? username) async {
    try {
      final normalized = username?.trim();
      if (normalized == null || normalized.isEmpty) {
        await _storage.delete(key: _usernameKey);
      } else {
        await _storage.write(key: _usernameKey, value: normalized);
      }
    } catch (_) {
      throw const SessionStoreException(
        'No se pudo guardar la preferencia de recordar usuario.',
      );
    }
  }
}
