import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:scpe_cisternas/data/mobile_api.dart';
import 'package:scpe_cisternas/domain/water_load.dart';

final endpoint = Uri.parse('https://example.test/api/mobile');
const load = WaterLoad(
  driverName: 'Juan Pérez',
  plateNumber: '2127acc',
  initialReading: 12025,
  finalReading: 13050,
  companyType: 'Particular',
  companyName: 'Entidad',
  characteristics: '',
  ebap: 'Sur',
);

MobileApi apiWith(String body, {int status = 200}) => MobileApi(
  endpoint: endpoint,
  client: MockClient(
    (_) async => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  ),
);

void main() {
  test('requires HTTPS with no credentials in the endpoint', () {
    expect(
      () => MobileApi(endpoint: Uri.parse('http://example.test/api')),
      throwsArgumentError,
    );
    expect(
      () => MobileApi(
        endpoint: Uri.parse('https://user:secret@example.test/api'),
      ),
      throwsArgumentError,
    );
  });

  test(
    'login honors the existing API contract and absolute 30-minute session',
    () async {
      final before = DateTime.now().toUtc();
      final api = MobileApi(
        endpoint: endpoint,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url, endpoint);
          expect(request.followRedirects, isFalse);
          expect(request.headers['Content-Type'], contains('application/json'));
          expect(jsonDecode(request.body), {
            'action': 'login',
            'username': 'operador',
            'password': ' pass ',
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'token': 'test-token',
              'user': {'username': 'operador', 'role': 'usuario'},
            }),
            200,
          );
        }),
      );
      final session = await api.login(' operador ', ' pass ');
      expect(session.token, 'test-token');
      expect(session.username, 'operador');
      expect(session.role, 'usuario');
      expect(
        session.expiresAt.isBefore(before.add(const Duration(minutes: 30))),
        isFalse,
      );
      expect(
        session.expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
        isFalse,
      );
    },
  );

  test(
    'a rejected login reports invalid credentials instead of an expired session',
    () async {
      await expectLater(
        apiWith('{}', status: 401).login('user', 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Usuario o contraseña incorrectos.',
          ),
        ),
      );
      await expectLater(
        apiWith(
          '{"message":"Credenciales inválidas."}',
          status: 401,
        ).login('user', 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Credenciales inválidas.',
          ),
        ),
      );
    },
  );

  test('requires well-formed session and boolean success', () async {
    for (final body in [
      '{"success":true}',
      '{"success":"true","token":"t","user":{"username":"u","role":"r"}}',
      '{"success":true,"token":"t","user":{"username":"","role":"r"}}',
    ]) {
      await expectLater(
        apiWith(body).login('user', 'pass'),
        throwsA(isA<ApiException>()),
      );
    }
  });

  test(
    'expired tokens are false; service failures remain distinguishable',
    () async {
      expect(
        await apiWith('{"success":false}').validateToken('test-token'),
        isFalse,
      );
      expect(
        await apiWith('{"success":true}').validateToken('test-token'),
        isTrue,
      );
      for (final status in [401, 403]) {
        expect(
          await apiWith('{}', status: status).validateToken('test-token'),
          isFalse,
        );
      }
      await expectLater(
        apiWith('{"success":"true"}').validateToken('test-token'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        apiWith('{}', status: 503).validateToken('test-token'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    '401 and 403 saves report authorization failures without suggesting a retry',
    () async {
      for (final status in [401, 403]) {
        await expectLater(
          apiWith('{}', status: status).saveLoad('test-token', load),
          throwsA(
            isA<ApiException>()
                .having((error) => error.unauthorized, 'unauthorized', isTrue)
                .having(
                  (error) => error.uncertainSave,
                  'uncertainSave',
                  isFalse,
                ),
          ),
        );
      }
    },
  );

  test(
    'logout preserves configured host and prefix and posts only the token',
    () async {
      var requests = 0;
      final api = MobileApi(
        endpoint: Uri.parse('https://example.test/prefix/api/mobile/'),
        client: MockClient((request) async {
          requests++;
          expect(
            request.url.toString(),
            'https://example.test/prefix/api/auth/logout',
          );
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(jsonDecode(request.body), {'token': 'test-token'});
          return http.Response(
            '{"success":true,"message":"Sesion cerrada"}',
            200,
          );
        }),
      );
      await api.logout('test-token');
      expect(requests, 1);
    },
  );

  test(
    'logout rejects a missing confirmation and does not retry a service error',
    () async {
      await expectLater(
        apiWith('{"success":false}').logout('test-token'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        apiWith('{}').logout('test-token'),
        throwsA(isA<ApiException>()),
      );
      var requests = 0;
      final api = MobileApi(
        endpoint: endpoint,
        client: MockClient((_) async {
          requests++;
          return http.Response('<html>upstream error</html>', 503);
        }),
      );
      await expectLater(
        api.logout('test-token'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.uncertainSave,
            'uncertainSave',
            isFalse,
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test(
    'saves normalized fields using token in JSON and accepts numeric ID',
    () async {
      var requests = 0;
      final api = MobileApi(
        endpoint: endpoint,
        client: MockClient((request) async {
          requests++;
          expect(jsonDecode(request.body), load.toPayload('test-token'));
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response('{"success":true,"id":42}', 200);
        }),
      );
      expect(await api.saveLoad('test-token', load), '42');
      expect(requests, 1);
    },
  );

  test('validates before sending invalid loads', () async {
    var requests = 0;
    final api = MobileApi(
      endpoint: endpoint,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    const invalid = WaterLoad(
      driverName: '',
      plateNumber: '2127acc',
      initialReading: 0,
      finalReading: 100,
      companyType: 'Particular',
      companyName: 'Entidad',
      characteristics: '',
      ebap: 'Sur',
    );
    await expectLater(
      api.saveLoad('test-token', invalid),
      throwsA(isA<ApiException>()),
    );
    expect(requests, 0);
  });

  test('timeout leaves the save uncertain and never retries', () async {
    var requests = 0;
    final pending = Completer<http.Response>();
    final api = MobileApi(
      endpoint: endpoint,
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
    await expectLater(
      api.saveLoad('test-token', load),
      throwsA(
        isA<ApiException>().having(
          (error) => error.uncertainSave,
          'uncertainSave',
          isTrue,
        ),
      ),
    );
    expect(requests, 1);
    pending.complete(http.Response('{"success":true,"id":42}', 200));
  });

  test('network interruption is uncertain only for writes', () async {
    final api = MobileApi(
      endpoint: endpoint,
      client: MockClient((_) async {
        throw http.ClientException('private host and technical details');
      }),
    );
    await expectLater(
      api.saveLoad('test-token', load),
      throwsA(
        isA<ApiException>().having(
          (error) => error.uncertainSave,
          'uncertainSave',
          isTrue,
        ),
      ),
    );
    await expectLater(
      api.testConnection(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.uncertainSave, 'uncertainSave', isFalse)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private host')),
            ),
      ),
    );
  });

  test(
    'malformed or incomplete save confirmation is never reported as success',
    () async {
      for (final body in [
        '<html>gateway</html>',
        '[]',
        'null',
        '42',
        '{"success":true}',
        '{"success":"true","id":42}',
      ]) {
        await expectLater(
          apiWith(body).saveLoad('test-token', load),
          throwsA(
            isA<ApiException>().having(
              (error) => error.uncertainSave,
              'uncertainSave',
              isTrue,
            ),
          ),
        );
      }
      await expectLater(
        apiWith('{}', status: 502).saveLoad('test-token', load),
        throwsA(
          isA<ApiException>().having(
            (error) => error.uncertainSave,
            'uncertainSave',
            isTrue,
          ),
        ),
      );
    },
  );

  test(
    'explicit rejection is certain and backend technical details are sanitized',
    () async {
      await expectLater(
        apiWith(
          '{"success":false,"message":"SQL exception: password=hidden"}',
        ).saveLoad('test-token', load),
        throwsA(
          isA<ApiException>()
              .having((error) => error.uncertainSave, 'uncertainSave', isFalse)
              .having(
                (error) => error.message,
                'message',
                'No se pudo guardar el registro.',
              ),
        ),
      );
      expect(
        await apiWith(
          '{"success":true,"message":"API operativa"}',
        ).testConnection(),
        'API operativa',
      );
    },
  );
}
