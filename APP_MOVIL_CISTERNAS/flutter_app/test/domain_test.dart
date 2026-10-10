import 'package:flutter_test/flutter_test.dart';

import 'package:scpe_cisternas/domain/session.dart';
import 'package:scpe_cisternas/domain/water_load.dart';

WaterLoad load({
  String driver = '  José   Pérez ',
  String plate = '2127acc',
  int initial = 10001,
  int finalReading = 10031,
  String type = 'Particular',
  String company = '  Empresa   uno ',
  String ebap = 'Norte',
}) => WaterLoad(
  driverName: driver,
  plateNumber: plate,
  initialReading: initial,
  finalReading: finalReading,
  companyType: type,
  companyName: company,
  characteristics: '  entrega   urgente ',
  ebap: ebap,
);

void main() {
  group('Readings use exact integer hundredths', () {
    test(
      'accepts decimal comma or point without floating-point arithmetic',
      () {
        expect(parseReading('100.01'), 10001);
        expect(parseReading('100,31'), 10031);
        expect(parseReading(' 0,1 '), 10);
        expect(parseReading('0'), 0);
        expect(parseReading('9999999999.99'), maxReadingCents);
        expect(load().loadVolume, 0.3);
      },
    );

    test('rejects ambiguous, nonfinite and excessive readings', () {
      for (final input in [
        '',
        'NaN',
        'Infinity',
        '-1',
        '1e2',
        '1.234',
        '1,234.56',
        '1 000',
        '10000000000',
        '1.',
        '.5',
      ]) {
        expect(parseReading(input), isNull, reason: input);
      }
    });
  });

  group('Water load validation', () {
    test('preserves API catalogues and normalizes submitted strings', () {
      final value = load();
      expect(value.validate(), isNull);
      final payload = value.toPayload('test-token');
      expect(payload, {
        'action': 'saveData',
        'token': 'test-token',
        'driverName': 'JOSÉ PÉREZ',
        'plateNumber': '2127 - ACC',
        'initialReading': 100.01,
        'finalReading': 100.31,
        'loadVolume': 0.3,
        'companyType': 'PARTICULAR',
        'companyName': 'EMPRESA UNO',
        'characteristics': 'ENTREGA URGENTE',
        'ebap': 'NORTE',
      });
    });

    test(
      'rejects empty required fields, unknown catalogues and nonpositive volumes',
      () {
        final invalidLoads = [
          load(driver: ' '),
          load(company: ' '),
          load(type: 'Otro'),
          load(ebap: 'Oeste'),
          load(initial: -1),
          load(initial: 10031),
          load(initial: 10032),
          load(finalReading: maxReadingCents + 1),
        ];
        for (final value in invalidLoads) {
          expect(value.validate(), isNotNull);
        }
      },
    );

    test(
      'formats valid plates but never drops excess input or rearranges it',
      () {
        expect(normalizePlate(' 2127 - acc '), '2127 - ACC');
        expect(normalizePlate('2127acc'), '2127 - ACC');
        for (final plate in [
          '12345ABC',
          '1234ABCD',
          'ABC1234',
          '123ABC',
          '12A34BC',
        ]) {
          expect(load(plate: plate).validate(), isNotNull, reason: plate);
        }
      },
    );
  });

  group('Session', () {
    test('expires exactly at the deadline and survives UTC serialization', () {
      final deadline = DateTime.utc(2026, 10, 9, 12, 30);
      final session = Session(
        token: 'test-token',
        username: 'operador',
        role: 'usuario',
        expiresAt: deadline,
      );
      expect(
        session.isExpired(deadline.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(session.isExpired(deadline), isTrue);
      final restored = Session.fromJson(session.toJson());
      expect(restored.expiresAt, deadline);
      expect(restored.username, 'operador');
      expect(restored.token, 'test-token');
    });

    test('rejects corrupted persisted sessions', () {
      expect(() => Session.fromJson({}), throwsFormatException);
      expect(
        () => Session.fromJson({
          'token': 'test-token',
          'username': 'operador',
          'role': 'usuario',
          'expiresAt': 'invalid',
        }),
        throwsFormatException,
      );
    });
  });
}
