import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/session.dart';
import '../domain/water_load.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.unauthorized = false,
    this.uncertainSave = false,
  });

  final String message;
  final bool unauthorized;

  /// A request may have reached the server; retrying could create a duplicate.
  final bool uncertainSave;

  @override
  String toString() => message;
}

/// Adapter for the existing action-based mobile API. Never retries a write.
class MobileApi {
  MobileApi({
    required this.endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasFragment) {
      throw ArgumentError(
        'La dirección de la API debe ser una URL HTTPS válida.',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('El tiempo de espera debe ser mayor que cero.');
    }
  }

  final Uri endpoint;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  Future<Session> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const ApiException('Complete usuario y contraseña.');
    }
    final data = await _post({
      'action': 'login',
      'username': username.trim(),
      'password': password,
    });
    _requireSuccess(data, 'Usuario o contraseña incorrectos.');
    final token = data['token'];
    final user = data['user'];
    if (token is! String ||
        token.trim().isEmpty ||
        user is! Map<String, dynamic>) {
      throw const ApiException('El servidor devolvió una sesión inválida.');
    }
    final name = user['username'];
    final role = user['role'];
    if (name is! String ||
        name.trim().isEmpty ||
        role is! String ||
        role.trim().isEmpty) {
      throw const ApiException('El servidor devolvió una sesión inválida.');
    }
    return Session(
      token: token,
      username: name,
      role: role,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }

  Future<bool> validateToken(String token) async {
    if (token.trim().isEmpty) return false;
    try {
      final data = await _post({'action': 'validateToken', 'token': token});
      if (data['success'] is! bool) {
        throw const ApiException(
          'El servidor devolvió una respuesta inválida.',
        );
      }
      return data['success'] == true;
    } on ApiException catch (error) {
      if (error.unauthorized) return false;
      rethrow;
    }
  }

  /// Revokes the server session through the backend's dedicated auth route.
  Future<void> logout(String token) async {
    if (token.trim().isEmpty) return;
    final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/mobile')) {
      throw const ApiException(
        'No se pudo determinar la ruta para cerrar la sesión en el servidor.',
      );
    }
    final logoutEndpoint = endpoint.replace(
      path: '${path.substring(0, path.length - '/mobile'.length)}/auth/logout',
    );
    final data = await _post({'token': token}, requestEndpoint: logoutEndpoint);
    _requireSuccess(
      data,
      'No se pudo confirmar el cierre de sesión en el servidor.',
    );
  }

  Future<String> testConnection() async {
    final data = await _post({'action': 'test'});
    _requireSuccess(data, 'El servicio no está disponible en este momento.');
    return _safeMessage(
      data['message'],
      'Conexión establecida. API operativa.',
    );
  }

  Future<String> saveLoad(String token, WaterLoad load) async {
    if (token.trim().isEmpty) {
      throw const ApiException(
        'La sesión ha expirado. Inicie sesión nuevamente.',
        unauthorized: true,
      );
    }
    final validation = load.validate();
    if (validation != null) throw ApiException(validation);
    final data = await _post(load.toPayload(token), saving: true);
    _requireSuccess(data, 'No se pudo guardar el registro.', saving: true);
    final id = data['id'];
    if ((id is! String && id is! int) || id.toString().trim().isEmpty) {
      throw const ApiException(
        'El servidor no confirmó el ID del registro. Verifique el registro antes de volver a enviarlo.',
        uncertainSave: true,
      );
    }
    return id.toString();
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    bool saving = false,
    Uri? requestEndpoint,
  }) async {
    try {
      final request = http.Request('POST', requestEndpoint ?? endpoint)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..headers['Accept'] = 'application/json'
        ..body = jsonEncode(payload);
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        // Gateways can return HTML; raw response bodies are never exposed.
      }
      if (response.statusCode == 401 && payload['action'] == 'login') {
        throw ApiException(
          _safeMessage(data?['message'], 'Usuario o contraseña incorrectos.'),
          unauthorized: true,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ApiException(
          'La sesión no es válida o no tiene permiso para esta operación. Inicie sesión nuevamente.',
          unauthorized: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final uncertain = saving && response.statusCode >= 500;
        throw ApiException(
          uncertain
              ? 'No se confirmó el guardado. Verifique el registro antes de volver a enviarlo.'
              : _safeMessage(
                  data?['message'],
                  'No se pudo completar la solicitud. Intente más tarde.',
                ),
          uncertainSave: uncertain,
        );
      }
      if (data == null) {
        throw ApiException(
          saving
              ? 'El servidor no confirmó el guardado. Verifique el registro antes de volver a enviarlo.'
              : 'El servidor devolvió una respuesta inválida. Intente más tarde.',
          uncertainSave: saving,
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        saving
            ? 'Se agotó el tiempo de espera. Verifique el registro antes de volver a enviarlo; podría haberse guardado.'
            : 'El servidor tardó demasiado en responder. Compruebe su conexión e intente nuevamente.',
        uncertainSave: saving,
      );
    } on http.ClientException {
      throw ApiException(
        saving
            ? 'Se perdió la conexión durante el envío. Verifique el registro antes de volver a enviarlo.'
            : 'No se pudo conectar con el servidor. Compruebe su conexión a internet.',
        uncertainSave: saving,
      );
    } catch (_) {
      throw ApiException(
        saving
            ? 'No se confirmó el guardado. Verifique el registro antes de volver a enviarlo.'
            : 'No se pudo completar la solicitud. Intente nuevamente.',
        uncertainSave: saving,
      );
    }
  }

  void _requireSuccess(
    Map<String, dynamic> data,
    String fallback, {
    bool saving = false,
  }) {
    if (data['success'] == true) return;
    if (data['success'] != false) {
      throw ApiException(
        saving
            ? 'El servidor no confirmó el guardado. Verifique el registro antes de volver a enviarlo.'
            : 'El servidor devolvió una respuesta inválida.',
        uncertainSave: saving,
      );
    }
    throw ApiException(_safeMessage(data['message'], fallback));
  }

  /// Only short plain-language errors may cross the API/UI boundary.
  String _safeMessage(Object? value, String fallback) {
    if (value is! String) return fallback;
    final message = value.trim();
    if (message.isEmpty ||
        message.length > 240 ||
        RegExp(r'[<>\r\n\x00-\x1F]').hasMatch(message) ||
        RegExp(
          r'https?://|traceback|stacktrace|exception|sql|authorization|bearer|password\s*[:=]|token\s*[:=]',
          caseSensitive: false,
        ).hasMatch(message)) {
      return fallback;
    }
    return message;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
