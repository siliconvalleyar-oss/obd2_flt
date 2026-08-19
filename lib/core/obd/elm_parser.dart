/// Parser puro de respuestas ELM327 (sin dependencias de plataforma).
///
/// Estrategia (ver docs/02-motor-obd2.md §2.6):
/// 1. Se normaliza la respuesta a líneas (sin `\r`, `\n` ni prompt `>`).
/// 2. Se buscan los tokens hex a partir del marcador de servicio
///    (`41 0C`, `43`, `49 02`, …) tolerando espacios on/off.
/// 3. Con cabeceras ON, las líneas de continuación (multiframe CAN) se
///    reensamblan quitando cabecera + byte de longitud/secuencia.
library;

/// Divide la respuesta en líneas limpias (sin `\r`, `\n`, `>`).
List<String> normalizeLines(String response) {
  final lines = <String>[];
  for (final raw in response.replaceAll('\r', '\n').split('\n')) {
    var line = raw.trim().replaceAll('>', '');
    line = line.trim();
    if (line.isNotEmpty) lines.add(line);
  }
  return lines;
}

/// Detecta si los primeros 3 chars hex forman un ID CAN estándar (11-bit).
/// OBD-II usa 7E8–7EF como IDs de respuesta.
bool _isCanId3(String s) {
  if (s.length < 3) return false;
  final u = s.substring(0, 3).toUpperCase();
  if (!RegExp(r'^[0-9A-F]{3}$').hasMatch(u)) return false;
  if (u.startsWith('7E')) return true;  // 7E0–7EF
  if (u.startsWith('7DF')) return true; // broadcast
  return false;
}

/// Tokeniza una línea en valores hex.
///
/// - Líneas con espacios: tokens separados por whitespace que sean hex;
///   un token contiguo largo (p. ej. `410C`) se divide en pares.
/// - Líneas sin espacios: detecta cabecera CAN de 3 chars (p. ej. `7E8`)
///   o, si no, pares de 2 caracteres hex.
List<String> hexTokens(String line) {
  var s = line.trim();
  if (s.isEmpty) return const <String>[];
  if (s.contains(' ')) {
    final out = <String>[];
    for (final t in s.split(RegExp(r'\s+'))) {
      if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(t)) continue;
      if (t.length <= 2 || t.length == 3) {
        out.add(t);
        continue;
      }
      for (int i = 0; i + 1 < t.length; i += 2) {
        out.add(t.substring(i, i + 2));
      }
    }
    return out;
  }
  // Sin espacios: intentar cabecera CAN de 3 chars primero.
  if (s.length >= 4 && _isCanId3(s)) {
    final tokens = <String>[];
    tokens.add(s.substring(0, 3));
    final rest = s.substring(3);
    for (int i = 0; i + 1 < rest.length; i += 2) {
      final t = rest.substring(i, i + 2);
      if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t)) tokens.add(t);
    }
    return tokens;
  }
  // Sin espacios, sin cabecera CAN: pares de 2 chars.
  final tokens = <String>[];
  final len = s.length - (s.length.isOdd ? 1 : 0);
  for (int i = 0; i + 1 < len; i += 2) {
    final t = s.substring(i, i + 2);
    if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t)) tokens.add(t);
  }
  return tokens;
}

/// Índice de la primera aparición del marcador (en pares hex) dentro de [tokens].
int indexOfMarker(List<String> tokens, String marker) {
  final pairs = <String>[];
  for (int i = 0; i + 1 < marker.length; i += 2) {
    pairs.add(marker.substring(i, i + 2).toUpperCase());
  }
  if (pairs.isEmpty) return -1;
  for (int i = 0; i + pairs.length <= tokens.length; i++) {
    var match = true;
    for (int j = 0; j < pairs.length; j++) {
      if (tokens[i + j].toUpperCase() != pairs[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

bool hasHeader(List<String> tokens) =>
    tokens.isNotEmpty && tokens.first.length != 2;

/// Extrae los tokens hex de la respuesta a partir del marcador de servicio
/// (p. ej. '410C', '43', '4902'). Tolerante a espacios on/off y cabeceras
/// on/off. Las tramas de continuación (multiframe con headers on) se
/// reensamblan quitando cabecera + byte de longitud/secuencia.
List<String> extractPayload(String response, String marker) {
  final lines = normalizeLines(response);
  final tokens = <String>[];
  var found = false;
  for (final line in lines) {
    final t = hexTokens(line);
    if (t.isEmpty) continue;
    if (!found) {
      final idx = indexOfMarker(t, marker);
      if (idx >= 0) {
        found = true;
        tokens.addAll(t.sublist(idx));
      }
      continue;
    }
    if (hasHeader(t)) {
      tokens.addAll(t.sublist(2));
    } else if (t.length >= 3 && t.first.startsWith('2')) {
      // Cabeceras OFF en CAN multiframe: la trama de continuación conserva
      // el byte de secuencia PCI 0x20–0x2F como primer token; se descarta.
      tokens.addAll(t.sublist(1));
    } else {
      tokens.addAll(t);
    }
  }
  return tokens;
}

bool isNoData(String resp) => resp.toUpperCase().contains('NO DATA');

bool isElmError(String resp) {
  final u = resp.toUpperCase();
  return u.contains('?') || u.contains('ERROR') || u.contains('UNABLE');
}

bool isOkResponse(String resp) {
  final u = resp.toUpperCase();
  return u.contains('OK') &&
      !u.contains('?') &&
      !u.contains('ERROR') &&
      !u.contains('UNABLE');
}

/// Decodifica un par de bytes hex DTC en código estándar (p. ej. '0301' → 'P0301').
///
/// Formato OBD-II:
///   Bits 15-14: 00=P, 01=C, 10=B, 11=U
///   Bit 13:     0=genérico, 1=fabricante
///   Bits 12-0:  número DTC (3 dígitos hex)
String decodeDtcBytes(String hex4) {
  if (hex4.length != 4 || !RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(hex4)) {
    return hex4.toUpperCase();
  }
  final hi = int.parse(hex4.substring(0, 2), radix: 16);
  final lo = int.parse(hex4.substring(2, 4), radix: 16);
  String prefix;
  switch ((hi >> 6) & 0x3) {
    case 0: prefix = 'P'; break;
    case 1: prefix = 'C'; break;
    case 2: prefix = 'B'; break;
    default: prefix = 'U'; break;
  }
  final subType = (hi >> 4) & 0x1;
  final number = ((hi & 0xF) << 8) | lo;
  return '$prefix$subType${number.toRadixString(16).toUpperCase().padLeft(3, '0')}';
}

/// Descripción genérica de un código DTC ya formateado (p. ej. 'P0301').
String describeDtc(String code) {
  final prefix = code.length >= 2 ? code.substring(0, 2).toUpperCase() : '';
  const categories = {
    'P0': 'Powertrain genérico',
    'P1': 'Powertrain fabricante',
    'C0': 'Chasis genérico',
    'C1': 'Chasis fabricante',
    'B0': 'Carrocería genérico',
    'B1': 'Carrocería fabricante',
    'U0': 'Red genérico',
    'U1': 'Red fabricante',
  };
  final desc = categories[prefix];
  if (desc != null) return desc;
  if (code == 'NONE') return 'Sin códigos';
  return 'Código $code';
}

/// Decodifica un código DTC (compatibilidad: delega a [describeDtc]).
@Deprecated('Usar decodeDtcBytes + describeDtc')
String decodeDTCCode(String code) => describeDtc(code);

/// Extrae el número de protocolo de la respuesta a `ATDPN`.
///
/// - Respuesta limpia de 1 dígito: `6` → 6, `0` → 0.
/// - Respuesta limpia de 2 dígitos: `06` → 6 (hex); `A5`/`B6` (formato
///   "automático + protocolo") → último dígito → 5/6.
/// - Respuesta ruidosa: se usa el primer carácter hex encontrado.
int? parseProtocolNumber(String resp) {
  final clean = resp.replaceAll(RegExp(r'[\s\r\n>]'), '');
  if (clean.isEmpty) return null;
  if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(clean)) {
    final first = clean[0].toUpperCase();
    if (RegExp(r'[A-F]').hasMatch(first)) {
      return int.tryParse(clean[1], radix: 16);
    }
    return int.tryParse(clean, radix: 16);
  }
  final hexOnly = RegExp(r'[0-9A-Fa-f]')
      .allMatches(clean)
      .map((m) => m.group(0)!)
      .toList();
  if (hexOnly.isEmpty) return null;
  if (hexOnly.length == 1) return int.tryParse(hexOnly.first, radix: 16);
  return int.tryParse(hexOnly.last, radix: 16);
}
