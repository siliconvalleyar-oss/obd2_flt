import 'package:flutter_test/flutter_test.dart';
import 'package:obd2_scanner/core/obd/elm_parser.dart';

void main() {
  group('normalizeLines', () {
    test('limpia CR, LF y prompts', () {
      expect(normalizeLines('41 0C 0A 0A\r\r>'), ['41 0C 0A 0A']);
      expect(normalizeLines('\rATZ\r\rELM327 v1.5\r\r>'), ['ATZ', 'ELM327 v1.5']);
    });
  });

  group('hexTokens', () {
    test('con espacios on', () {
      expect(hexTokens('41 0C 0A 0A'), ['41', '0C', '0A', '0A']);
    });
    test('con espacios off (línea continua)', () {
      expect(hexTokens('410C0A0A'), ['41', '0C', '0A', '0A']);
    });
    test('ignora ruido no hex', () {
      expect(hexTokens('> 410C \r\n'), ['41', '0C']);
    });
  });

  group('indexOfMarker / extractPayload', () {
    test('respuesta mono-trama con cabeceras off', () {
      final resp = '41 0C 0A 0A\r\r>';
      expect(extractPayload(resp, '410C'), ['41', '0C', '0A', '0A']);
    });

    test('respuesta mono-trama con cabeceras on (7E8)', () {
      final resp = '7E8 41 0C 0A 0A\r\r>';
      expect(extractPayload(resp, '410C'), ['41', '0C', '0A', '0A']);
    });

    test('multiframe CAN reensamblado (VIN 4902)', () {
      final resp =
          '7E8 49 02 01 31 4A 57\r7E8 21 42 4C 54 4A 30\r7E8 22 31 32 33 34 35\r7E8 23 36 37 38 39 30\r\r>';
      final tokens = extractPayload(resp, '4902');
      expect(tokens, [
        '49', '02', '01', '31', '4A', '57',
        '42', '4C', '54', '4A', '30',
        '31', '32', '33', '34', '35',
        '36', '37', '38', '39', '30',
      ]);
    });

    test('multiframe con cabeceras off (no se reensambla)', () {
      final resp = '49 02 01 31 4A 57\r21 42 4C 54 4A 30\r\r>';
      final tokens = extractPayload(resp, '4902');
      expect(tokens, ['49', '02', '01', '31', '4A', '57', '42', '4C', '54', '4A', '30']);
    });

    test('tolerante a "SEARCHING..." y respuestas previas', () {
      final resp =
          'ATDPN\r\rSEARCHING...\r\r7E8 41 0C 0A 0A\r\r>';
      expect(extractPayload(resp, '410C'), ['41', '0C', '0A', '0A']);
    });

    test('marker no encontrado devuelve vacío', () {
      expect(extractPayload('7E8 41 0C 0A 0A', '4307'), isEmpty);
    });
  });

  group('flags de respuesta', () {
    test('no data', () {
      expect(isNoData('NO DATA'), isTrue);
      expect(isNoData('41 0C 0A 0A'), isFalse);
    });
    test('error ELM', () {
      expect(isElmError('?'), isTrue);
      expect(isElmError('ERROR'), isTrue);
      expect(isElmError('UNABLE TO CONNECT'), isTrue);
      expect(isElmError('OK'), isFalse);
    });
    test('ok', () {
      expect(isOkResponse('OK'), isTrue);
      expect(isOkResponse('?'), isFalse);
      expect(isOkResponse('ELM327 v1.5'), isFalse);
    });
  });

  group('decodeDTCCode', () {
    test('mapea prefijos a categorías', () {
      expect(decodeDTCCode('P0100'), contains('Powertrain'));
      expect(decodeDTCCode('C1200'), contains('Chasis'));
      expect(decodeDTCCode('B1000'), contains('Carrocería'));
      expect(decodeDTCCode('U0100'), contains('Red'));
    });
  });

  group('parseProtocolNumber', () {
    test('dígito único', () {
      expect(parseProtocolNumber('6'), 6);
      expect(parseProtocolNumber('0'), 0);
    });
    test('dos dígitos numéricos (hex)', () {
      expect(parseProtocolNumber('06'), 6);
      expect(parseProtocolNumber('09'), 9);
    });
    test('formato "A5"/"B6" (auto + protocolo)', () {
      expect(parseProtocolNumber('A5'), 5);
      expect(parseProtocolNumber('B6'), 6);
    });
    test('con ruido y prompts', () {
      expect(parseProtocolNumber('\r\rATDPN\r\rA5\r\r>'), 5);
      expect(parseProtocolNumber('\r\r06\r\r>'), 6);
    });
    test('vacío / solo whitespace', () {
      expect(parseProtocolNumber(''), isNull);
      expect(parseProtocolNumber('\r\n  '), isNull);
    });
  });
}
