const companyTypes = <String>[
  'Gobierno Nacional',
  'Gobierno Departamental',
  'Gobierno Municipal',
  'Bomberos',
  'Ayuda Comunitaria',
  'SAGUAPAC',
  'Particular',
];

const ebapOptions = <String>['Norte', 'Sur', 'Este', 'Sudoeste'];

/// Upper bound keeps readings and arithmetic well inside JSON's safe integers.
const maxReadingCents = 999999999999;

String normalizeText(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// Formats a complete plate without silently truncating or rearranging input.
String normalizePlate(String value) {
  final normalized = normalizeText(value);
  final compact = normalized.replaceAll(RegExp(r'[\s-]'), '');
  final match = RegExp(r'^(\d{4})([A-Z]{3})$').firstMatch(compact);
  if (match == null) return normalized;
  return '${match.group(1)} - ${match.group(2)}';
}

/// Reads m³ as integer hundredths, accepting a decimal point or decimal comma.
/// Scientific notation, separators, negatives and excess precision are rejected.
int? parseReading(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(?:\.\d{1,2})?$').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final cents = whole * 100 + fraction;
  return cents <= maxReadingCents ? cents : null;
}

class WaterLoad {
  const WaterLoad({
    required this.driverName,
    required this.plateNumber,
    required this.initialReading,
    required this.finalReading,
    required this.companyType,
    required this.companyName,
    required this.characteristics,
    required this.ebap,
  });

  final String driverName;
  final String plateNumber;

  /// Meter readings are stored as hundredths of a cubic metre.
  final int initialReading;
  final int finalReading;
  final String companyType;
  final String companyName;
  final String characteristics;
  final String ebap;

  double get loadVolume => (finalReading - initialReading) / 100;

  String? validate() {
    if (normalizeText(driverName).isEmpty) {
      return 'Ingrese el nombre del conductor.';
    }
    if (!RegExp(r'^\d{4} - [A-Z]{3}$').hasMatch(normalizePlate(plateNumber))) {
      return 'La placa debe tener el formato 2127 - ACC.';
    }
    if (initialReading < 0 ||
        finalReading < 0 ||
        initialReading > maxReadingCents ||
        finalReading > maxReadingCents) {
      return 'Ingrese lecturas válidas, con hasta dos decimales.';
    }
    if (finalReading <= initialReading) {
      return 'La lectura final debe ser mayor que la inicial.';
    }
    if (!companyTypes.any(
      (type) => normalizeText(type) == normalizeText(companyType),
    )) {
      return 'Seleccione el tipo de empresa.';
    }
    if (normalizeText(companyName).isEmpty) {
      return 'Ingrese la empresa o entidad.';
    }
    if (!ebapOptions.any(
      (option) => normalizeText(option) == normalizeText(ebap),
    )) {
      return 'Seleccione una EBAP válida.';
    }
    return null;
  }

  Map<String, dynamic> toPayload(String token) => {
    'action': 'saveData',
    'token': token,
    'driverName': normalizeText(driverName),
    'plateNumber': normalizePlate(plateNumber),
    'initialReading': initialReading / 100,
    'finalReading': finalReading / 100,
    'loadVolume': loadVolume,
    'companyType': normalizeText(companyType),
    'companyName': normalizeText(companyName),
    'characteristics': normalizeText(characteristics),
    'ebap': normalizeText(ebap),
  };
}
