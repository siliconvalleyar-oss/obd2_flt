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

/// Tokeniza una línea en valores hex.
///
/// - Líneas con espacios: tokens separados por whitespace que sean hex;
///   un token contiguo largo (p. ej. `410C`) se divide en pares.
/// - Líneas continuas (sin espacios): pares de 2 caracteres hex.
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

/// Decodifica un código DTC (P/C/B/U + categoría genérica/fabricante).
String decodeDTCCode(String code) {
  const types = {
    'P0': 'Powertrain - Genérico',
    'P1': 'Powertrain - Fabricante',
    'P2': 'Powertrain - Genérico',
    'P3': 'Powertrain - Genérico',
    'C0': 'Chasis - Genérico',
    'C1': 'Chasis - Fabricante',
    'C2': 'Chasis - Genérico',
    'C3': 'Chasis - Genérico',
    'B0': 'Carrocería - Genérico',
    'B1': 'Carrocería - Fabricante',
    'B2': 'Carrocería - Genérico',
    'B3': 'Carrocería - Genérico',
    'U0': 'Red - Genérico',
    'U1': 'Red - Fabricante',
    'U2': 'Red - Genérico',
    'U3': 'Red - Genérico',
  };
  final prefix = code.length >= 2 ? code.substring(0, 2) : '';
  return types[prefix] ?? code;
}

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
